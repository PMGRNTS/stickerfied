# Pop-up that makes new backgrounds, stickers or doll items with AI, using OpenRouter.
# The player describes what they want and picks a style.
#   - Backgrounds are added to the first background folder (the first folder starting with 00).
#   - Stickers are added to the sticker menu and placed on the doll.
#   - Doll items (hair, faces, clothes...) are put on the doll for the player to move
#     into place (see picture_upload.gd), then added to that layer's menu.
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
# Added to every prompt so the picture works as a backdrop behind the doll
@export_multiline var background_prompt_suffix := "Background scenery for a dress-up game. Wide view, no people, no characters, no animals in the foreground, no text, no watermark."
# Added to every sticker prompt so the result is one object that can be placed on the doll
@export_multiline var sticker_prompt_suffix := "A single isolated accessory or sticker for a dress-up game, centered, whole object visible, clean dark outline, no person wearing it, no text, no shadow."
# Added to every doll item prompt; %s is the layer's name, such as "Hair"
@export_multiline var item_prompt_suffix := "A single %s piece for a 2D paper doll dress-up game, shaped to be worn by the doll, whole item visible, clean dark outline, no person, no mannequin, no hanger, no text, no shadow."
# Added to every sticker and doll item prompt, so clothes come out flat like paper doll
# cutouts instead of showing their inside through the neck or hem
@export_multiline var flat_prompt := "Drawn completely flat like a paper doll cutout: straight-on front view, no perspective, no depth, no 3D. Only the outside front is shown: the inside, lining, back, inner collar and inner hem are never visible. Neck, sleeve and bottom openings are closed edges filled with the item's color, not holes."

enum Kind { BACKGROUND, STICKER, ITEM }

# Style name shown in the menu : words added to the prompt
const BACKGROUND_STYLES := {
	"Cartoon": "Bright flat cartoon illustration, clean shapes, soft colors.",
	"Anime": "Anime background art, detailed, soft lighting.",
	"Watercolor": "Soft watercolor painting, gentle textures.",
	"Storybook": "Whimsical children's storybook illustration.",
	"Pixel art": "Detailed pixel art, 16-bit video game style.",
	"Photo": "Realistic photograph, natural light.",
}
# Stickers and doll items have no 3D styles: they have to look flat to sit on the doll
const STICKER_STYLES := {
	"Cute cartoon": "Cute flat cartoon drawing, bold simple shapes, bright colors.",
	"Flat vector": "Flat vector illustration, solid colors, no gradients.",
	"Anime": "Anime style item illustration, flat cel shading.",
	"Watercolor": "Soft watercolor illustration.",
	"Pixel art": "Pixel art sprite, 32-bit video game style.",
}
const SETTINGS_FILE := AIKey.SETTINGS_FILE

@onready var client: OpenRouterClient = $OpenRouterClient

var kind := Kind.BACKGROUND
var item_layer := "" # the doll layer a doll item is made for, such as "03Hair"
var models := [] # every image model, from OpenRouter
var models_loaded := false
var preferred_models := {}
var busy_since := -1

func _ready() -> void:
	super()
	%GenerateButton.pressed.connect(generate)
	%CloseButton.pressed.connect(close)
	%BackgroundKind.pressed.connect(func(): set_kind(Kind.BACKGROUND))
	%StickerKind.pressed.connect(func(): set_kind(Kind.STICKER))
	%ItemKind.pressed.connect(func(): set_kind(Kind.ITEM))
	%LayerOption.item_selected.connect(func(index): set_kind(Kind.ITEM, doll_layers()[index]))
	%KeyEdit.text_changed.connect(func(_text): save_settings())
	%RememberKey.toggled.connect(func(_on): save_settings())
	%ModelOption.item_selected.connect(func(index):
		preferred_models[kind] = models[index].id
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
	set_kind(Kind.BACKGROUND)

func open_for(new_kind:Kind, layer := "") -> void:
	set_kind(new_kind, layer)
	open()

func _on_open() -> void:
	# the key may have been changed in the AI Stylist window
	%KeyEdit.text = AIKey.current_key()
	if not models_loaded:
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
	if busy_since >= 0:
		return
	var prompt = %PromptEdit.text.strip_edges()
	if prompt == "":
		_set_status("Describe it first, like \"%s\"." % %PromptEdit.placeholder_text)
		return
	client.api_key = %KeyEdit.text.strip_edges()
	if client.api_key == "" and client.base_url.contains("openrouter.ai"):
		_set_status("Paste your OpenRouter API key below first.")
		return

	var making = kind # the player could switch tabs while waiting
	var layer = item_layer
	var model = _selected_model()
	var style = _styles()[%StyleOption.get_item_text(%StyleOption.selected)]
	var full_prompt: String
	var size: Vector2
	var extra := {}
	if making == Kind.BACKGROUND:
		full_prompt = "%s. %s %s" % [prompt.trim_suffix("."), style, background_prompt_suffix]
		size = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	else:
		# a doll item is drawn in the shape of the doll's images, so it is about the right size
		size = Vector2(picture_upload.doll_size(layer)) if making == Kind.ITEM else Vector2(1, 1)
		var transparent = can_make_transparent(model)
		if transparent:
			extra.background = "transparent"
			if OpenRouterClient.supports(model, "output_format", "png"):
				extra.output_format = "png"
		if OpenRouterClient.supports(model, "quality", "medium"):
			extra.quality = "medium"
		var suffix = sticker_prompt_suffix if making == Kind.STICKER else item_prompt_suffix % layer_name(layer).to_lower()
		full_prompt = "%s. %s %s %s %s" % [prompt.trim_suffix("."), style, flat_prompt, suffix,
			"Transparent background." if transparent else "On a plain flat pure white background."]

	busy_since = Time.get_ticks_msec()
	%GenerateButton.disabled = true
	var result = await client.generate_image(full_prompt, model, size, extra)
	busy_since = -1
	%GenerateButton.disabled = false

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
		# the player moves it into place; it's saved when they press Done
		_set_status("Done! It was put on the doll to move into place." + cost_text)
		close()
		picture_upload.place_picture(layer, result.image, prompt, "ai")
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

# A model can only make a see-through sticker if it supports transparent
# backgrounds AND sends back a format that keeps transparency (not jpeg)
static func can_make_transparent(model: Dictionary) -> bool:
	if not OpenRouterClient.supports(model, "background", "transparent"):
		return false
	var formats = model.params.get("output_format", {}).get("values", ["png"])
	return "png" in formats or "webp" in formats


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

# Lists the models; for stickers and doll items, the ones that make transparent pictures are marked
func _show_models() -> void:
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
	%KeyEdit.text = AIKey.load_key()
	%RememberKey.set_pressed_no_signal(AIKey.remembers_key())

func save_settings() -> void:
	AIKey.save_key(%KeyEdit.text, %RememberKey.button_pressed)
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE) # keeps the settings saved by other windows
	config.set_value("openrouter", "background_model", preferred_models.get(Kind.BACKGROUND, default_background_model))
	config.set_value("openrouter", "sticker_model", preferred_models.get(Kind.STICKER, default_sticker_model))
	config.set_value("openrouter", "item_model", preferred_models.get(Kind.ITEM, default_item_model))
	config.save(SETTINGS_FILE)

func _set_status(text: String) -> void:
	%StatusLabel.text = text
