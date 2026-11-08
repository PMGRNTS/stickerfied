# Pop-up that makes new backgrounds, stickers or doll items with AI.
# The player describes what they want and picks a style.
# Pictures are made with OpenRouter, or with any model on fal, Replicate or RunPod
# (see custom_image_client.gd), such as one the player trained themselves.
#   - Backgrounds are added to the first background folder (the first folder starting with 00).
#   - Stickers are added to the sticker menu and placed on the doll.
#   - Doll items (hair, faces, clothes...) are put on the doll for the player to move
#     into place (see picture_upload.gd), then added to that layer's menu.
#     With "Fit to the doll", the model draws the item on a picture of the doll,
#     so it starts out in the right place and only needs nudging.
# "Write it for me" asks a text model on OpenRouter to turn the player's short idea into a
# detailed description for the picture. What the writer is told first (its system prompt)
# can be changed in the window ("Writer prompt") or in the Inspector. The writer is shown
# a picture of the doll, so what it describes suits the character.
# Pictures are kept in user://generated/ so they're still there next time.

extends OverlayDialog

@export var interactivity: Node
# Puts doll items on the doll so the player can move them into place
@export var picture_upload: Node2D
@export var default_background_model := "black-forest-labs/flux-3-image-klein"
# Stickers work best with a model that can make transparent pictures.
# Other models work too: the game removes their plain background.
@export var default_sticker_model := "openai/gpt-image-1-mini"
# Doll items need a see-through background too
@export var default_item_model := "openai/gpt-image-1-mini"
# The model filled in for each of the other providers, until the player types their own
@export var default_custom_models := {
	"fal": "fal-ai/flux/dev",
	"replicate": "black-forest-labs/flux-dev",
	"runpod": "black-forest-labs-flux-1-schnell",
}
# Added to every prompt so the picture works as a backdrop behind the doll
@export_multiline var background_prompt_suffix := "Background scenery for a dress-up game. Wide view, no people, no characters, no animals in the foreground, no text, no watermark."
# Added to every sticker prompt so the result is one object that can be placed on the doll
@export_multiline var sticker_prompt_suffix := "A single isolated accessory or sticker for a dress-up game, centered, whole object visible, clean dark outline, no person wearing it, no text, no shadow."
# Added to every doll item prompt; %s is the layer's name, such as "Hair"
@export_multiline var item_prompt_suffix := "A single %s piece for a 2D paper doll dress-up game, shaped to be worn by the doll, whole item visible, clean dark outline, no person, no mannequin, no hanger, no text, no shadow."
# Used instead of Item Prompt Suffix for the doll's body (the first doll layer): a new body is a new character
@export_multiline var body_prompt_suffix := "A whole character for a 2D paper doll dress-up game: one figure standing straight and facing forward, arms held a little away from the body, whole body visible from head to feet, dressed only in a simple plain base layer so clothes can go on top, clean dark outline, no text, no shadow."
# Added to doll item prompts with Fit to the doll, when a picture of the doll is sent along
@export_multiline var fit_prompt := "The reference picture shows the doll this item is for, on a canvas the same shape as this picture. Draw the item exactly where it sits when the doll wears it: the same size and the same place on the canvas, following the doll's outline. Draw only the item. Leave out the doll and everything else in the reference picture."
# Used instead of Fit Prompt for a new body: the picture shows the old body
@export_multiline var fit_body_prompt := "The reference picture shows the doll's current body, on a canvas the same shape as this picture. Draw the new character in exactly the same pose, size and place on the canvas, with the same outline, so clothes made for the old body still fit. Draw only the character."
# Added to every sticker and doll item prompt, so clothes come out flat like paper doll
# cutouts instead of showing their inside through the neck or hem
@export_multiline var flat_prompt := "Drawn completely flat like a paper doll cutout: straight-on front view, no perspective, no depth, no 3D. Only the outside front is shown: the inside, lining, back, inner collar and inner hem are never visible. Neck, sleeve and bottom openings are closed edges filled with the item's color, not holes."
# Used instead of Flat Prompt for the 3D and photo styles (see DEPTH_STYLES): they keep their
# depth, but clothes still shouldn't show their inside
@export_multiline var depth_prompt := "Straight-on front view. Only the outside front is shown: the inside, lining, back, inner collar and inner hem are never visible. Neck, sleeve and bottom openings are closed, not holes."

# The OpenRouter text model behind "Write it for me". Any model from https://openrouter.ai/models works.
@export var writer_model := "anthropic/claude-haiku-5.5"
# What the writer is told before the player's idea (its system prompt).
# Players can change it in the window; Reset puts this back.
# Shows the writer a picture of the doll (needs a writer model that accepts pictures)
@export var writer_sees_doll := true
@export_multiline var writer_instructions := "You write picture descriptions for an image model in a dress-up game for all ages. The player gives a short idea for a character, a piece of clothing, an accessory or a place. Turn it into one vivid paragraph of 2 to 4 sentences that says exactly how it looks: shapes, colors, materials, patterns and the small details that make it charming. For a character, describe their face, hair, skin and build, and show their personality through how they look. For clothes and accessories, describe only the item, never a person wearing it. Describe only what is drawn: no story, no names, no text in the picture. Don't mention the art style, background, camera or lighting, because the game adds those. Reply only with JSON."

enum Kind { BACKGROUND, STICKER, ITEM }

# Style name shown in the menu : words added to the prompt
const BACKGROUND_STYLES := {
	"Cartoon": "Bright flat cartoon illustration, clean shapes, soft colors.",
	"Anime": "Anime background art, detailed, soft lighting.",
	"Watercolor": "Soft watercolor painting, gentle textures.",
	"Storybook": "Whimsical children's storybook illustration.",
	"Pixel art": "Detailed pixel art, 16-bit video game style.",
	"3D render": "Cute 3D render, soft studio lighting, smooth toy-like shapes.",
	"Photo": "Realistic photograph, natural light.",
}
const STICKER_STYLES := {
	"Cute cartoon": "Cute flat cartoon drawing, bold simple shapes, bright colors.",
	"Flat vector": "Flat vector illustration, solid colors, no gradients.",
	"Anime": "Anime style item illustration, flat cel shading.",
	"Watercolor": "Soft watercolor illustration.",
	"Pixel art": "Pixel art sprite, 32-bit video game style.",
	"Shiny 3D": "Glossy 3D toy-like render, soft studio lighting.",
	"Photo": "Realistic product photo, soft studio lighting.",
}
# Sticker styles that aren't drawn flat, so they get Depth Prompt instead of Flat Prompt
const DEPTH_STYLES := ["Shiny 3D", "Photo"]
# Where pictures can be made. OpenRouter has a list of models to pick from;
# for the others the player types the model, and any extra input it needs.
const PROVIDERS := {
	"openrouter": {"name": "OpenRouter", "key_url": "https://openrouter.ai/keys", "key_hint": "sk-or-..."},
	"fal": {"name": "fal", "key_url": "https://fal.ai/dashboard/keys", "key_hint": "your fal key",
		"model_label": "Model", "model_hint": "fal-ai/flux-lora"},
	"replicate": {"name": "Replicate", "key_url": "https://replicate.com/account/api-tokens", "key_hint": "r8_...",
		"model_label": "Model", "model_hint": "owner/model or owner/model:version"},
	"runpod": {"name": "RunPod", "key_url": "https://console.runpod.io/user/settings", "key_hint": "rpa_...",
		"model_label": "Endpoint", "model_hint": "your serverless endpoint's ID"},
}
const SETTINGS_FILE := AIKey.SETTINGS_FILE

@onready var client: OpenRouterClient = $OpenRouterClient
@onready var custom_client: CustomImageClient = $CustomImageClient

var kind := Kind.BACKGROUND
var item_layer := "" # the doll layer a doll item is made for, such as "03Hair"
var models := [] # every image model, from OpenRouter
var models_loaded := false
var preferred_models := {}
var provider := "openrouter"
var custom_models := {} # provider : {kind : model typed by the player}
var custom_extras := {} # provider : {kind : extra input as JSON text}
var busy_since := -1
var fit_to_doll := true # draw doll items on a picture of the doll
var writing := false
var writer_prompt := "" # the player's own writer prompt, "" for writer_instructions
var writer_model_id := "" # the player's own writer model, "" for writer_model

func _ready() -> void:
	super()
	%GenerateButton.pressed.connect(generate)
	%WriteButton.pressed.connect(write_description)
	%WriterToggle.toggled.connect(_show_writer)
	# TextEdit also says its text changed when the game fills it in, so only real changes are saved
	%WriterEdit.text_changed.connect(func():
		var text = %WriterEdit.text.strip_edges()
		text = text if text != writer_instructions.strip_edges() else ""
		if text != writer_prompt:
			writer_prompt = text
			save_settings())
	%WriterModelEdit.text_changed.connect(func(text):
		text = text.strip_edges()
		writer_model_id = text if text != writer_model else ""
		save_settings())
	%WriterResetButton.pressed.connect(func():
		writer_prompt = ""
		writer_model_id = ""
		_show_writer_settings()
		save_settings())
	%CloseButton.pressed.connect(close)
	%BackgroundKind.pressed.connect(func(): set_kind(Kind.BACKGROUND))
	%StickerKind.pressed.connect(func(): set_kind(Kind.STICKER))
	%ItemKind.pressed.connect(func(): set_kind(Kind.ITEM))
	%LayerOption.item_selected.connect(func(index): set_kind(Kind.ITEM, doll_layers()[index]))
	for id in PROVIDERS:
		%ProviderOption.add_item(PROVIDERS[id].name)
	%ProviderOption.item_selected.connect(func(index): set_provider(PROVIDERS.keys()[index]))
	%KeyEdit.text_changed.connect(func(_text): save_settings())
	%ModelEdit.text_changed.connect(func(text):
		custom_models.get_or_add(provider, {})[kind] = text.strip_edges()
		save_settings())
	%ExtraEdit.text_changed.connect(func(text):
		custom_extras.get_or_add(provider, {})[kind] = text.strip_edges()
		save_settings())
	%RememberKey.toggled.connect(func(_on): save_settings())
	%ModelOption.item_selected.connect(func(index):
		preferred_models[kind] = models[index].id
		_update_fit()
		save_settings())
	%FitCheck.toggled.connect(func(on):
		fit_to_doll = on
		save_settings())
	# the AI buttons in the menus
	SignalBus.dressup_item_signal.connect(func(button, operation):
		if operation != "ai":
			return
		if button.category == interactivity.STICKERS:
			open_for(Kind.STICKER)
		elif interactivity.is_background(button.category):
			open_for(Kind.BACKGROUND)
		else:
			open_for(Kind.ITEM, button.category))
	_load_settings()
	_show_writer_settings()
	set_kind(Kind.BACKGROUND)
	set_provider(provider)

func open_for(new_kind:Kind, layer := "") -> void:
	set_kind(new_kind, layer)
	open()

func _on_open() -> void:
	# the key may have been changed in the AI Stylist window
	%KeyEdit.text = AIKey.current_key(provider)
	if provider == "openrouter" and not models_loaded:
		_load_models()
	%PromptEdit.grab_focus()

# layer is the doll layer for Kind.ITEM; "" keeps the one chosen before
func set_kind(new_kind:Kind, layer := "") -> void:
	kind = new_kind
	if layer != "":
		item_layer = layer
	if not item_layer in doll_layers():
		item_layer = doll_layers()[0] if not doll_layers().is_empty() else ""
	%BackgroundKind.set_pressed_no_signal(kind == Kind.BACKGROUND)
	%StickerKind.set_pressed_no_signal(kind == Kind.STICKER)
	%ItemKind.set_pressed_no_signal(kind == Kind.ITEM)
	%LayerRow.visible = kind == Kind.ITEM
	%LayerOption.clear()
	for other in doll_layers():
		%LayerOption.add_item(layer_name(other))
	%LayerOption.select(doll_layers().find(item_layer))
	match kind:
		Kind.BACKGROUND:
			%PromptHint.text = "Describe a place:"
			%PromptEdit.placeholder_text = "a cozy bedroom with fairy lights"
		Kind.STICKER:
			%PromptHint.text = "Describe an accessory or sticker:"
			%PromptEdit.placeholder_text = "a tiny golden crown with pink gems"
		Kind.ITEM:
			%PromptHint.text = "Describe the new %s:" % layer_name(item_layer).to_lower()
			%PromptEdit.placeholder_text = "purple with little gold stars"
	%StyleOption.clear()
	for style in _styles():
		%StyleOption.add_item(style)
	_show_models()
	_set_status("")
	%GenerateButton.disabled = kind == Kind.BACKGROUND and background_layer() == ""
	if %GenerateButton.disabled:
		_set_status("This game has no background folder (a folder starting with 00).")
	elif kind == Kind.ITEM and item_layer == "":
		%GenerateButton.disabled = true
		_set_status("This game has no doll layers yet.")

func _styles() -> Dictionary:
	return BACKGROUND_STYLES if kind == Kind.BACKGROUND else STICKER_STYLES

func _process(_delta: float) -> void:
	if busy_since >= 0:
		var seconds = (Time.get_ticks_msec() - busy_since) / 1000
		_set_status(["Painting your background... %ds", "Drawing your sticker... %ds", "Drawing your item... %ds"][kind] % seconds)

func background_layer() -> String:
	for layer in interactivity.layers:
		if interactivity.is_background(layer):
			return layer
	return ""

# Layers of the doll itself (not backgrounds), such as "01Skin" and "03Hair"
func doll_layers() -> Array:
	return interactivity.layers.filter(func(layer): return not interactivity.is_background(layer))

# "03Hair" is "Hair"
static func layer_name(layer:String) -> String:
	var short_name = layer.lstrip("0123456789 _-")
	return short_name.capitalize() if short_name != "" else layer


#####################################
############## GENERATING ###########
#####################################

func generate() -> void:
	if busy_since >= 0 or writing:
		return
	var prompt = %PromptEdit.text.strip_edges()
	if prompt == "":
		_set_status("Describe it first, like \"%s\"." % %PromptEdit.placeholder_text)
		return
	var key = %KeyEdit.text.strip_edges()
	var needs_key = client.base_url.contains("openrouter.ai") if provider == "openrouter" else custom_client.needs_key(provider)
	if key == "" and needs_key:
		_set_status("Paste your %s API key below first." % PROVIDERS[provider].name)
		return
	var using = provider # the player could switch providers while waiting
	var custom_model = %ModelEdit.text.strip_edges()
	var custom_extra = {}
	if using != "openrouter":
		if custom_model == "":
			_set_status("Type the %s to use first." % PROVIDERS[using].model_label.to_lower())
			return
		if %ExtraEdit.text.strip_edges() != "":
			var json := JSON.new()
			custom_extra = json.data if json.parse(%ExtraEdit.text) == OK else null
			if not custom_extra is Dictionary:
				_set_status("Extra input has to be written as JSON, like {\"lora_scale\": 0.8}.")
				return

	var making = kind # the player could switch tabs while waiting
	var layer = item_layer
	var model = _selected_model() if using == "openrouter" else {}
	var style_name = %StyleOption.get_item_text(%StyleOption.selected)
	var style = _styles()[style_name]
	var full_prompt: String
	var size: Vector2
	var extra := {}
	var fit := {} # the doll's picture sent with the prompt, see _fit_reference()
	if making == Kind.BACKGROUND:
		full_prompt = "%s. %s %s" % [prompt.trim_suffix("."), style, background_prompt_suffix]
		size = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	else:
		# a doll item is drawn in the shape of the doll's images, so it is about the right size
		size = Vector2(picture_upload.doll_size(layer)) if making == Kind.ITEM else Vector2(1, 1)
		var transparent = using == "openrouter" and can_make_transparent(model)
		if transparent:
			extra.background = "transparent"
			if OpenRouterClient.supports(model, "output_format", "png"):
				extra.output_format = "png"
		if OpenRouterClient.supports(model, "quality", "medium"):
			extra.quality = "medium"
		var body = making == Kind.ITEM and interactivity.is_required(layer)
		var suffix = sticker_prompt_suffix
		if making == Kind.ITEM:
			suffix = body_prompt_suffix if body else item_prompt_suffix % layer_name(layer).to_lower()
		# the flat and depth prompts are about clothes, so a body doesn't get them
		var shape = "" if body else (depth_prompt if style_name in DEPTH_STYLES else flat_prompt)
		full_prompt = "%s. %s %s %s %s" % [prompt.trim_suffix("."), style, shape, suffix,
			"Transparent background." if transparent else "On a plain flat pure white background."]
		if making == Kind.ITEM and using == "openrouter" and fit_to_doll and can_fit(model):
			fit = _fit_reference(layer, model)
			extra.input_references = [{"type": "image_url", "image_url": {"url": "data:image/png;base64," +
				Marshalls.raw_to_base64(fit.image.save_png_to_buffer())}}]
			full_prompt += " " + (fit_body_prompt if body else fit_prompt)

	busy_since = Time.get_ticks_msec()
	%GenerateButton.disabled = true
	%WriteButton.disabled = true
	var result: Dictionary
	if using == "openrouter":
		client.api_key = key
		result = await client.generate_image(full_prompt, model, size, extra)
	else:
		custom_client.api_key = key
		result = await custom_client.generate_image(using, full_prompt, custom_model, size, custom_extra,
			making != Kind.BACKGROUND)
	busy_since = -1
	%GenerateButton.disabled = false
	%WriteButton.disabled = false

	if not result.ok:
		_set_status(result.error)
		return
	var cost = result.get("cost")
	var cost_text = " Cost: $%.3f" % cost if cost is float else ""

	if making == Kind.BACKGROUND:
		var image = fit_to_size(result.image, Vector2i(size))
		var path = GeneratedItems.save(background_layer(), image, prompt)
		if path == "":
			_set_status("The background was made, but couldn't be saved.")
			return
		interactivity.add_runtime_item(background_layer(), ImageTexture.create_from_image(image), path)
		_set_status("Done! It's in the backgrounds menu." + cost_text)
	elif making == Kind.ITEM:
		var image: Image = result.image
		if not fit.is_empty():
			# back to the doll's own canvas, so the item sits where it was drawn
			image = fit_to_size(image, fit.image.get_size()).get_region(fit.doll)
		# the player moves it into place; it's saved when they press Done
		_set_status("Done! It was put on the doll to move into place." + cost_text)
		close()
		picture_upload.place_picture(layer, image, prompt, "ai", not fit.is_empty())
	else:
		var image = StickerImage.prepare(result.image)
		var path = GeneratedItems.save(interactivity.STICKERS, image, prompt)
		if path == "":
			_set_status("The sticker was made, but couldn't be saved.")
			return
		interactivity.add_runtime_sticker(ImageTexture.create_from_image(image), path)
		_set_status("Done! Close this window to move your sticker." + cost_text)
	Sfx.play("sparkle")

# Scales the picture to cover the whole screen, cutting off any extra at the edges
static func fit_to_size(image: Image, size: Vector2i) -> Image:
	var scale = maxf(float(size.x) / image.get_width(), float(size.y) / image.get_height())
	var scaled = Vector2i(ceili(image.get_width() * scale), ceili(image.get_height() * scale))
	image.resize(scaled.x, scaled.y, Image.INTERPOLATE_LANCZOS)
	return image.get_region(Rect2i((scaled - size) / 2, size))

# Fit to the doll needs a model that can look at a picture while it draws
static func can_fit(model: Dictionary) -> bool:
	return OpenRouterClient.supports(model, "input_references")

# The doll's picture for Fit to the doll: the doll without the layer the item is for
# (or only the old body, for a new body), with white added around it so it has the
# shape the model draws in. Returns {"image": Image, "doll": Rect2i, where the doll is in it}
func _fit_reference(layer: String, model: Dictionary) -> Dictionary:
	var layers = [layer] if interactivity.is_required(layer) else doll_layers().filter(func(other): return other != layer)
	var doll: Image = picture_upload.doll_picture(layers)
	var size = Vector2(doll.get_size())
	# the same ratio generate_image() asks for, since it is given the doll's size
	var ratio = OpenRouterClient.closest_aspect_ratio(model.get("aspect_ratios", []), size.x / size.y)
	var wanted = size.x / size.y if ratio == "" else float(ratio.get_slice(":", 0)) / float(ratio.get_slice(":", 1))
	var canvas_size = Vector2i(size.max(Vector2(size.y * wanted, size.x / wanted)).round())
	var canvas = Image.create_empty(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.WHITE)
	var doll_rect = Rect2i((canvas_size - doll.get_size()) / 2, doll.get_size())
	canvas.blit_rect(doll, Rect2i(Vector2i.ZERO, doll.get_size()), doll_rect.position)
	return {"image": canvas, "doll": doll_rect}

# A model can only make a see-through sticker if it supports transparent
# backgrounds AND sends back a format that keeps transparency (not jpeg)
static func can_make_transparent(model: Dictionary) -> bool:
	if not OpenRouterClient.supports(model, "background", "transparent"):
		return false
	var formats = model.params.get("output_format", {}).get("values", ["png"])
	return "png" in formats or "webp" in formats


#####################################
############## WRITING ##############
#####################################

# Turns the player's idea into a detailed description with a text model on OpenRouter.
# The description replaces the idea in the prompt box (Ctrl+Z brings the idea back).
func write_description() -> void:
	if writing or busy_since >= 0:
		return
	client.api_key = AIKey.current_key("openrouter")
	if client.api_key == "" and client.base_url.contains("openrouter.ai"):
		_show_writer(false)
		_set_status("Paste your OpenRouter API key below first." if provider == "openrouter" else
			"The writer uses OpenRouter: pick OpenRouter as the Provider below and paste your key first.")
		return
	writing = true
	%WriteButton.disabled = true
	_set_status("Writing a description...")
	var result = await client.ask_json(writer_model_id if writer_model_id != "" else writer_model,
		writer_prompt if writer_prompt != "" else writer_instructions, _writer_question(),
		picture_upload.doll_picture(_writer_layers()) if writer_sees_doll else null)
	writing = false
	%WriteButton.disabled = false
	if not result.ok:
		_set_status(result.error)
		return
	var description = str(result.data.get("description", "")).strip_edges()
	if description == "":
		_set_status("The writer didn't come up with anything. Try again?")
		return
	%PromptEdit.select_all()
	%PromptEdit.insert_text_at_caret(description)
	var cost = result.get("cost")
	_set_status("Change anything you like, then press Generate." + (" Cost: $%.4f" % cost if cost is float else ""))

func _writer_question() -> String:
	var idea = %PromptEdit.text.strip_edges()
	var making: String
	match kind:
		Kind.BACKGROUND:
			making = "a background: a place shown behind the doll, with no characters in it"
		Kind.STICKER:
			making = "a sticker: one accessory or object that is placed on the doll"
		Kind.ITEM:
			# the first doll layer is the doll's body, so a new one is a new character
			if interactivity.is_required(item_layer):
				making = "a new character: the doll's whole body for a 2D paper doll, standing straight and facing forward"
			else:
				making = "a new %s piece for a 2D paper doll" % layer_name(item_layer).to_lower()
	var lines := [
		"Making: " + making,
		"Style: " + %StyleOption.get_item_text(%StyleOption.selected),
		"Idea: " + (idea if idea != "" else "(none, surprise me with something fun)"),
		"",
	]
	if writer_sees_doll:
		var without = " (without its %s)" % layer_name(item_layer).to_lower() if not item_layer in _writer_layers() else ""
		lines.append("The picture shows the doll as it looks now%s. Make what you describe suit this character." % without)
	lines.append("Reply with JSON like: {\"description\": \"<the description>\"}")
	return "\n".join(lines)

# The doll's layers in the writer's picture: all of them, except the layer a new item replaces
func _writer_layers() -> Array:
	if kind == Kind.ITEM and not interactivity.is_required(item_layer):
		return doll_layers().filter(func(layer): return layer != item_layer)
	return doll_layers()

# Shows the writer's prompt and model in place of the AI settings, or the other way around
func _show_writer(on: bool) -> void:
	%WriterToggle.set_pressed_no_signal(on)
	%WriterBox.visible = on
	%SettingsBox.visible = not on

func _show_writer_settings() -> void:
	%WriterEdit.text = writer_prompt if writer_prompt != "" else writer_instructions
	%WriterModelEdit.placeholder_text = writer_model
	%WriterModelEdit.text = writer_model_id if writer_model_id != "" else writer_model


#####################################
############## MODELS & SETTINGS ####
#####################################

func _load_models() -> void:
	_set_status("Loading the list of models...")
	var result = await client.fetch_image_models()
	if result.ok:
		models = result.models
		models_loaded = true
		_set_status("")
	else:
		_set_status("Couldn't load the list of models, so the default one will be used. (%s)" % result.error)
	_show_models()

func _default_model() -> String:
	return [default_background_model, default_sticker_model, default_item_model][kind]

# Lists the models; for stickers and doll items, the ones that make transparent pictures are marked.
# For the other providers, shows the model and extra input typed for this kind of picture.
func _show_models() -> void:
	if provider != "openrouter":
		%ModelEdit.text = custom_models.get(provider, {}).get(kind, default_custom_models.get(provider, ""))
		%ExtraEdit.text = custom_extras.get(provider, {}).get(kind, "")
		_update_fit()
		return
	for id in [default_background_model, default_sticker_model, default_item_model]:
		if not models.any(func(model): return model.id == id):
			models.push_front({"id": id, "name": id, "aspect_ratios": [], "resolutions": [], "params": {}})
	var wanted = preferred_models.get(kind, _default_model())
	%ModelOption.clear()
	for model in models:
		var label = model.name
		if kind != Kind.BACKGROUND and can_make_transparent(model):
			label += "  (transparent)"
		%ModelOption.add_item(label)
		if model.id == wanted:
			%ModelOption.select(%ModelOption.item_count - 1)
	_update_fit()

# Fit to the doll can only be ticked when the model can look at the doll's picture
func _update_fit() -> void:
	var possible = provider == "openrouter" and not models.is_empty() and can_fit(_selected_model())
	%FitCheck.disabled = not possible
	%FitCheck.set_pressed_no_signal(fit_to_doll and possible)
	%FitCheck.tooltip_text = "The model draws the item on a picture of the doll, so it starts out in the right place." \
		if possible else "Needs an OpenRouter model that can look at a picture while it draws (most can)."

func set_provider(new_provider: String) -> void:
	provider = new_provider if new_provider in PROVIDERS else "openrouter"
	var info: Dictionary = PROVIDERS[provider]
	var custom = provider != "openrouter"
	%ProviderOption.select(PROVIDERS.keys().find(provider))
	%KeyEdit.text = AIKey.current_key(provider)
	%KeyEdit.placeholder_text = info.key_hint
	%RememberKey.set_pressed_no_signal(AIKey.remembers_key(provider))
	%GetKeyLink.uri = info.key_url
	%ModelLabel.text = info.get("model_label", "Model")
	%ModelOption.visible = not custom
	%ModelEdit.visible = custom
	%ModelEdit.placeholder_text = info.get("model_hint", "")
	%ExtraRow.visible = custom
	_show_models()
	_set_status("")
	if provider == "replicate" and OS.has_feature("web") and custom_client.needs_key(provider):
		_set_status("Replicate doesn't let web games connect to it directly. It works in the downloaded game, or through a proxy (see the readme).")
	elif provider == "openrouter" and not models_loaded and visible:
		_load_models()
	save_settings()

func _selected_model() -> Dictionary:
	return models[%ModelOption.selected] if %ModelOption.selected >= 0 else models[0]

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) != OK:
		return
	# "model" is where older versions kept the background model
	preferred_models[Kind.BACKGROUND] = config.get_value("openrouter", "background_model",
		config.get_value("openrouter", "model", default_background_model))
	preferred_models[Kind.STICKER] = config.get_value("openrouter", "sticker_model", default_sticker_model)
	preferred_models[Kind.ITEM] = config.get_value("openrouter", "item_model", default_item_model)
	provider = config.get_value("ai_create", "provider", "openrouter")
	writer_prompt = config.get_value("ai_create", "writer_prompt", "")
	fit_to_doll = config.get_value("ai_create", "fit_to_doll", true)
	writer_model_id = config.get_value("ai_create", "writer_model", "")
	for id in PROVIDERS:
		if config.has_section_key(id, "models"):
			custom_models[id] = config.get_value(id, "models")
		if config.has_section_key(id, "extras"):
			custom_extras[id] = config.get_value(id, "extras")

func save_settings() -> void:
	AIKey.save_key(%KeyEdit.text, %RememberKey.button_pressed, provider)
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE) # keeps the settings saved by other windows
	config.set_value("ai_create", "provider", provider)
	config.set_value("ai_create", "writer_prompt", writer_prompt)
	config.set_value("ai_create", "fit_to_doll", fit_to_doll)
	config.set_value("ai_create", "writer_model", writer_model_id)
	for id in custom_models:
		config.set_value(id, "models", custom_models[id])
	for id in custom_extras:
		config.set_value(id, "extras", custom_extras[id])
	config.set_value("openrouter", "background_model", preferred_models.get(Kind.BACKGROUND, default_background_model))
	config.set_value("openrouter", "sticker_model", preferred_models.get(Kind.STICKER, default_sticker_model))
	config.set_value("openrouter", "item_model", preferred_models.get(Kind.ITEM, default_item_model))
	config.save(SETTINGS_FILE)

func _set_status(text: String) -> void:
	%StatusLabel.text = text
