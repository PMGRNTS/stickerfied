# Talks to OpenRouter ( https://openrouter.ai ), which gives access to many
# image generation models with one API key.
# OpenRouter allows requests from web pages, so this also works in a web export.

class_name OpenRouterClient
extends Node

# Point this at your own proxy server if you'd rather players didn't need their own key
@export var base_url := "https://openrouter.ai/api/v1"
# Shown on OpenRouter's activity page, so you can tell which app made a request
@export var app_title := "DressUpBase"
@export var timeout_seconds := 180.0

var api_key := ""

# Returns {"ok": true, "models": [{"id", "name", "aspect_ratios", "resolutions", "params"}, ...]}
# or {"ok": false, "error": "..."}. Listing models doesn't need an API key.
func fetch_image_models() -> Dictionary:
	var response = await _request("/images/models", HTTPClient.METHOD_GET)
	if not response.ok:
		return response
	var list = response.data
	if list is Dictionary:
		list = list.get("data", [])
	var models := []
	for entry in list:
		if not entry is Dictionary or not entry.has("id"):
			continue
		var params = entry.get("supported_parameters")
		if not params is Dictionary:
			params = {}
		models.append({
			"id": entry.id,
			"name": entry.get("name", entry.id),
			"aspect_ratios": _enum_values(params.get("aspect_ratio")),
			"resolutions": _enum_values(params.get("resolution")),
			"params": params, # everything the model supports, see supports()
		})
	models.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return {"ok": true, "models": models}

# Makes one image. model is an entry from fetch_image_models().
# target_size is used to pick the closest aspect ratio the model supports.
# extra is added to the request, such as {"background": "transparent"}
# (check the model supports it with supports() first).
# Returns {"ok": true, "image": Image, "cost": float or null} or {"ok": false, "error": "..."}
func generate_image(prompt: String, model: Dictionary, target_size: Vector2, extra := {}) -> Dictionary:
	var body := {"model": model.id, "prompt": prompt}
	body.merge(extra)
	var ratio = closest_aspect_ratio(model.get("aspect_ratios", []), target_size.x / target_size.y)
	if ratio != "":
		body.aspect_ratio = ratio
	if "1K" in model.get("resolutions", []):
		body.resolution = "1K"

	var response = await _request("/images", HTTPClient.METHOD_POST, body)
	if not response.ok:
		return response
	var images = response.data.get("data") if response.data is Dictionary else null
	if not images is Array or images.is_empty() or not images[0] is Dictionary:
		return _fail("The model didn't send back an image. Try a different prompt or model.")

	var bytes: PackedByteArray
	var first: Dictionary = images[0]
	if first.get("b64_json") is String:
		var b64: String = first.b64_json
		if b64.contains("base64,"):
			b64 = b64.get_slice("base64,", 1) # data URL
		bytes = Marshalls.base64_to_raw(b64)
	elif first.get("url") is String:
		var download = await _download(first.url)
		if not download.ok:
			return download
		bytes = download.bytes

	var image = decode_image(bytes)
	if image == null:
		return _fail("The image came back in a format the game can't read.")
	var usage = response.data.get("usage")
	return {"ok": true, "image": image, "cost": usage.get("cost") if usage is Dictionary else null}

# Asks a text model a question and expects a JSON object back.
# picture is optional: an Image the model can look at (it needs a model that accepts images).
# Returns {"ok": true, "data": Dictionary, "cost": float or null} or {"ok": false, "error": "..."}
func ask_json(model_id: String, instructions: String, question: String, picture: Image = null) -> Dictionary:
	var content: Variant = question
	if picture:
		content = [
			{"type": "text", "text": question},
			{"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," +
				Marshalls.raw_to_base64(picture.save_jpg_to_buffer(0.85))}},
		]
	var body := {
		"model": model_id,
		"messages": [
			{"role": "system", "content": instructions},
			{"role": "user", "content": content},
		],
		"response_format": {"type": "json_object"},
		"max_tokens": 1500,
	}
	var response = await _request("/chat/completions", HTTPClient.METHOD_POST, body)
	if not response.ok:
		return response
	var choices = response.data.get("choices") if response.data is Dictionary else null
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		return _fail("The model didn't answer. Try again.")
	var message = choices[0].get("message", {})
	var text = message.get("content", "") if message is Dictionary else ""
	if text is Array: # some models send a list of text parts
		text = "".join(text.map(func(part): return str(part.get("text", "")) if part is Dictionary else ""))
	var data = parse_json_reply(str(text))
	if data.is_empty():
		return _fail("The model's answer couldn't be read. Try again.")
	var usage = response.data.get("usage")
	return {"ok": true, "data": data, "cost": usage.get("cost") if usage is Dictionary else null}

# Finds the JSON object in a reply, even if the model wrapped it in other text
static func parse_json_reply(text: String) -> Dictionary:
	var start = text.find("{")
	var end = text.rfind("}")
	if start < 0 or end <= start:
		return {}
	var data = JSON.parse_string(text.substr(start, end - start + 1))
	return data if data is Dictionary else {}


#####################################
############## HELPERS ##############
#####################################

func _request(path: String, method: int, body = null) -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json", "X-Title: " + app_title])
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	var error = http.request(base_url + path, headers, method, JSON.stringify(body) if body != null else "")
	if error != OK:
		http.queue_free()
		return _fail("Couldn't start the request (%s)." % error_string(error))
	var response = await http.request_completed # [result, response_code, headers, body]
	http.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return _fail(_describe_result(response[0]))
	var data = JSON.parse_string(response[3].get_string_from_utf8())
	var code: int = response[1]
	if code < 200 or code >= 300:
		var message = "The server answered with error %d." % code
		if data is Dictionary and data.get("error") is Dictionary and data.error.has("message"):
			message = str(data.error.message)
		if code == 401:
			message = "OpenRouter didn't accept the API key. (%s)" % message
		elif code == 402:
			message = "Your OpenRouter account is out of credits. (%s)" % message
		return _fail(message)
	if data == null:
		return _fail("The server's reply couldn't be read.")
	return {"ok": true, "data": data}

func _download(url: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return _fail("Couldn't download the image.")
	var response = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return _fail("Couldn't download the image.")
	return {"ok": true, "bytes": response[3]}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _describe_result(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "It took too long to answer. Try again, or pick a faster model."
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Couldn't reach the server. Check your internet connection."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Couldn't make a secure connection to the server."
	return "Network error (%d)." % result

# True if the model accepts this setting (and this value, when one is given),
# for example supports(model, "background", "transparent")
static func supports(model: Dictionary, param: String, value = null) -> bool:
	var params = model.get("params", {})
	if not params.has(param):
		return false
	return value == null or value in _enum_values(params[param])

static func _enum_values(param) -> Array:
	if param is Dictionary and param.get("values") is Array:
		return param.values
	return []

# Picks the supported ratio (such as "3:2") closest to the wanted width/height ratio
static func closest_aspect_ratio(ratios: Array, wanted: float) -> String:
	var best := ""
	var best_difference := INF
	for ratio in ratios:
		var parts = str(ratio).split(":")
		if len(parts) != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float() or float(parts[1]) == 0:
			continue
		var difference = absf(log(float(parts[0]) / float(parts[1])) - log(wanted))
		if difference < best_difference:
			best = ratio
			best_difference = difference
	return best

# Reads png, jpg or webp data, whichever it turns out to be
static func decode_image(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		error = image.load_webp_from_buffer(bytes)
	return image if error == OK else null
