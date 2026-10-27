# Makes pictures with fal ( https://fal.ai ), Replicate ( https://replicate.com ) or
# RunPod ( https://runpod.io ), so players can use any model those sites run,
# including ones they trained themselves. Each site has its own API key.
# The model is named the way each site does it:
#   - fal: the model's id, such as "fal-ai/flux/dev" or "fal-ai/flux-lora"
#   - Replicate: "owner/model", or "owner/model:version" for one exact version
#   - RunPod: the id of a serverless endpoint
# The prompt and size are sent with the names most image models use. Anything else a
# model needs (such as a LoRA, or a workflow) goes in extra_input.

class_name CustomImageClient
extends Node

# Point these at your own proxy server if you'd rather players didn't need their own key.
# Replicate doesn't accept requests from web pages, so a web export needs a proxy for it.
@export var fal_url := "https://fal.run"
@export var replicate_url := "https://api.replicate.com/v1"
@export var runpod_url := "https://api.runpod.ai/v2"
@export var timeout_seconds := 180.0
# How often to ask whether a slow picture is done yet
@export var poll_seconds := 2.0

const PROVIDER_NAMES := {"fal": "fal", "replicate": "Replicate", "runpod": "RunPod"}
const OFFICIAL_URLS := {
	"fal": "https://fal.run",
	"replicate": "https://api.replicate.com/v1",
	"runpod": "https://api.runpod.ai/v2",
}
# The aspect ratios Replicate's image models usually accept
const REPLICATE_RATIOS := ["1:1", "16:9", "21:9", "3:2", "2:3", "4:5", "5:4", "3:4", "4:3", "9:16", "9:21"]

var api_key := ""

func base_url(provider: String) -> String:
	return {"fal": fal_url, "replicate": replicate_url, "runpod": runpod_url}.get(provider, "")

# A key is needed unless requests go through your own proxy
func needs_key(provider: String) -> bool:
	return base_url(provider) == OFFICIAL_URLS.get(provider)

# Makes one image. target_size is used for the shape of the picture.
# extra_input is added to (or replaces parts of) what is sent to the model.
# png asks for a lossless picture, which keeps edges clean when the background is removed.
# Returns {"ok": true, "image": Image, "cost": null} or {"ok": false, "error": "..."}
func generate_image(provider: String, prompt: String, model_id: String, target_size: Vector2, extra_input := {}, png := false) -> Dictionary:
	var size = picture_size(target_size)
	var input := {"prompt": prompt}
	var response: Dictionary
	match provider:
		"fal":
			input.image_size = {"width": size.x, "height": size.y}
			input.num_images = 1
			if png:
				input.output_format = "png"
			input.merge(extra_input, true)
			response = await _request(provider, fal_url + "/" + model_id, HTTPClient.METHOD_POST,
				["Authorization: Key " + api_key], input)
		"replicate":
			input.aspect_ratio = OpenRouterClient.closest_aspect_ratio(REPLICATE_RATIOS, float(size.x) / size.y)
			input.width = size.x
			input.height = size.y
			if png:
				input.output_format = "png"
			input.merge(extra_input, true)
			response = await _replicate(model_id, input)
		"runpod":
			input.width = size.x
			input.height = size.y
			if png:
				input.image_format = "png"
			input.merge(extra_input, true)
			response = await _runpod(model_id, input)
		_:
			return _fail("Unknown provider \"%s\"." % provider)
	if not response.ok:
		return response

	# Replicate and RunPod put the result in "output", fal sends it as it is
	var data = response.data
	var found = find_picture(data.get("output") if data is Dictionary and data.has("output") else data)
	if found == "":
		return _fail("The model didn't send back a picture. Check the model's name and its extra input.")
	var bytes: PackedByteArray
	if found.begins_with("http"):
		var download = await _download(found)
		if not download.ok:
			return download
		bytes = download.bytes
	else:
		bytes = Marshalls.base64_to_raw(found.get_slice("base64,", 1) if found.contains("base64,") else found)
	var image = OpenRouterClient.decode_image(bytes)
	if image == null:
		return _fail("The image came back in a format the game can't read.")
	return {"ok": true, "image": image, "cost": null}

func _replicate(model_id: String, input: Dictionary) -> Dictionary:
	# waits up to a minute for the picture before answering
	var headers := ["Authorization: Bearer " + api_key, "Prefer: wait"]
	var response: Dictionary
	if model_id.contains(":"):
		response = await _request("replicate", replicate_url + "/predictions", HTTPClient.METHOD_POST,
			headers, {"version": model_id.get_slice(":", 1), "input": input})
	else:
		response = await _request("replicate", replicate_url + "/models/" + model_id + "/predictions",
			HTTPClient.METHOD_POST, headers, {"input": input})
	return await _wait_until_done("replicate", response, headers,
		func(data): return str(data.get("urls", {}).get("get", "")))

func _runpod(endpoint_id: String, input: Dictionary) -> Dictionary:
	var headers := ["Authorization: Bearer " + api_key]
	var url = runpod_url + "/" + endpoint_id
	var response = await _request("runpod", url + "/runsync", HTTPClient.METHOD_POST, headers, {"input": input})
	return await _wait_until_done("runpod", response, headers,
		func(data): return url + "/status/" + str(data.get("id", "")))

# Keeps asking about a job that isn't finished yet. status_url gives the address to ask, from a reply.
func _wait_until_done(provider: String, response: Dictionary, headers: Array, status_url: Callable) -> Dictionary:
	var started = Time.get_ticks_msec()
	while response.ok and _job_state(response.data) == "running":
		if (Time.get_ticks_msec() - started) / 1000.0 > timeout_seconds:
			return _fail(OpenRouterClient.describe_result(HTTPRequest.RESULT_TIMEOUT))
		await get_tree().create_timer(poll_seconds).timeout
		response = await _request(provider, status_url.call(response.data), HTTPClient.METHOD_GET, headers)
	if response.ok and _job_state(response.data) == "failed":
		var reason = _error_message(response.data)
		return _fail("The model couldn't make the picture. (%s)" % (reason if reason != "" else "no reason given"))
	return response

# "running", "failed" or "done", from Replicate's or RunPod's status
static func _job_state(data) -> String:
	if not data is Dictionary:
		return "done"
	var status = str(data.get("status", "")).to_lower()
	if status in ["starting", "processing", "in_queue", "in_progress"]:
		return "running"
	if status in ["failed", "canceled", "cancelled", "timed_out"]:
		return "failed"
	return "done"

# Finds the picture in a model's answer, which each model shapes its own way:
# a link, a data URL or base64 text, on its own or inside lists and dictionaries.
# Returns "" if there is none.
static func find_picture(value) -> String:
	if value is String:
		if value.begins_with("http") or value.begins_with("data:image"):
			return value
		if value.length() >= 64 and _looks_like_base64(value):
			return value
	elif value is Array:
		for part in value:
			var found = find_picture(part)
			if found != "":
				return found
	elif value is Dictionary:
		# the usual places first, then anywhere else
		for key in ["images", "image", "image_url", "url", "data", "message", "base64"] + value.keys():
			if value.has(key):
				var found = find_picture(value[key])
				if found != "":
					return found
	return ""

static func _looks_like_base64(text: String) -> bool:
	for character in text.substr(0, 64):
		if not (character.is_valid_identifier() or character.is_valid_int() or character in "+/="):
			return false
	return true

# About a million pixels in the shape of target_size, in steps of 64 (which every model accepts)
static func picture_size(target_size: Vector2) -> Vector2i:
	var ratio = clampf(target_size.x / target_size.y, 0.25, 4.0)
	var width = maxi(256, snappedi(int(sqrt(1024 * 1024 * ratio)), 64))
	var height = maxi(256, snappedi(int(width / ratio), 64))
	return Vector2i(width, height)


#####################################
############## HELPERS ##############
#####################################

func _request(provider: String, url: String, method: int, headers: Array, body = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	var all_headers := PackedStringArray(["Content-Type: application/json"] + headers)
	var error = http.request(url, all_headers, method, JSON.stringify(body) if body != null else "")
	if error != OK:
		http.queue_free()
		return _fail("Couldn't start the request (%s)." % error_string(error))
	var response = await http.request_completed # [result, response_code, headers, body]
	http.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		var message = OpenRouterClient.describe_result(response[0])
		if OS.has_feature("web") and response[0] != HTTPRequest.RESULT_TIMEOUT:
			message += " Some sites don't let web games connect to them directly (see the readme)."
		return _fail(message)
	var data = JSON.parse_string(response[3].get_string_from_utf8())
	var code: int = response[1]
	if code < 200 or code >= 300:
		var reason = _error_message(data)
		var message = reason if reason != "" else "The server answered with error %d." % code
		var name = PROVIDER_NAMES.get(provider, provider)
		match code:
			401, 403:
				message = "%s didn't accept the API key. (%s)" % [name, message]
			402:
				message = "Your %s account is out of credits. (%s)" % [name, message]
			404:
				message = "%s couldn't find that model. Check its name. (%s)" % [name, message]
			422:
				message = "The model didn't accept what was sent. (%s)" % message
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

# The reason a site gives for an error, in whichever shape it uses
static func _error_message(data) -> String:
	if not data is Dictionary:
		return ""
	for key in ["detail", "error", "message", "title"]:
		var value = data.get(key)
		if value is String and value != "":
			return value
		if value is Dictionary and value.has("message"):
			return str(value.message)
		if value is Array and not value.is_empty(): # fal lists each problem with the input
			var first = value[0]
			return str(first.get("msg", first)) if first is Dictionary else str(first)
	return ""

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
