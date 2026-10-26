# Pop-up with two AI helpers that use a text model on OpenRouter:
#   - Dress me: the player says where the doll is going, and the stylist
#     picks items and colors from this game's menus (so it works with your own art).
#   - Judge me: the judge looks at a picture of the doll and gives a score,
#     a name for the look and a comment. During a challenge, it judges how well
#     the outfit fits the challenge's theme.
# It uses the same OpenRouter key as the AI Create window.

extends OverlayDialog

@export var interactivity: Node
# Takes the picture the judge looks at, and knows the challenge's theme
@export var toolbar: Control
# The model must accept pictures, for the judge. Any model from https://openrouter.ai/models
# with "image" input works; cheaper ones answer faster.
@export var text_model := "anthropic/claude-haiku-5.5"
# Size of the picture sent to the judge (smaller is cheaper and faster)
@export var judge_picture_width := 600
@export_multiline var stylist_instructions := "You are a cheerful fashion stylist in a dress-up game for all ages. The player tells you where their doll is going. Choose one item for each layer, using only the exact item names you are given, and a color for each layer that can be recolored. Keep the outfit fun and fitting for the occasion. Reply only with JSON."
@export_multiline var judge_instructions := "You are a kind, funny fashion judge in a dress-up game for all ages. Look at the picture of the doll (ignore the game's background unless it fits the look). Give a score from 1 to 10, a short catchy name for the look, and one or two friendly sentences of feedback with a small tip. Be encouraging: most looks deserve 6 or more. If there is a theme, judge how well the look fits it. Never comment on the doll's body. Reply only with JSON."

enum Mode { DRESS, JUDGE }

const STAR = preload("res://stickers/star.svg")
const MAX_SCORE := 10

@onready var client: OpenRouterClient = $OpenRouterClient

var mode := Mode.DRESS
var busy := false

func _ready() -> void:
	super()
	%DressMode.pressed.connect(func(): set_mode(Mode.DRESS))
	%JudgeMode.pressed.connect(func(): set_mode(Mode.JUDGE))
	%DressButton.pressed.connect(dress)
	%OccasionEdit.text_submitted.connect(func(_text): dress())
	%JudgeButton.pressed.connect(judge)
	%CloseButton.pressed.connect(close)
	%KeyEdit.text_changed.connect(func(_text): AIKey.save_key(%KeyEdit.text, %RememberKey.button_pressed))
	%RememberKey.toggled.connect(func(on): AIKey.save_key(%KeyEdit.text, on))
	for i in MAX_SCORE:
		var star := TextureRect.new()
		star.texture = STAR
		star.custom_minimum_size = Vector2(22, 22)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		%Stars.add_child(star)
	%Result.hide()
	set_mode(Mode.DRESS)

func open_for(new_mode:Mode) -> void:
	set_mode(new_mode)
	open()

func _on_open() -> void:
	# the key may have been changed in the AI Create window
	%KeyEdit.text = AIKey.current_key()
	%RememberKey.set_pressed_no_signal(AIKey.remembers_key())
	set_mode(mode)
	if mode == Mode.DRESS:
		%OccasionEdit.grab_focus()

func set_mode(new_mode:Mode) -> void:
	mode = new_mode
	%DressMode.set_pressed_no_signal(mode == Mode.DRESS)
	%JudgeMode.set_pressed_no_signal(mode == Mode.JUDGE)
	%DressBox.visible = mode == Mode.DRESS
	%JudgeBox.visible = mode == Mode.JUDGE
	var theme_name = toolbar.challenge_theme()
	%JudgeHint.text = "Challenge theme: %s" % theme_name if theme_name != "" else \
		"The judge looks at your doll and gives the look a score."
	if not busy:
		_set_status("")

func _has_key() -> bool:
	client.api_key = %KeyEdit.text.strip_edges()
	if client.api_key == "" and client.base_url.contains("openrouter.ai"):
		_set_status("Paste your OpenRouter API key below first.")
		return false
	return true

func _set_busy(on:bool, text := "") -> void:
	busy = on
	%DressButton.disabled = on
	%JudgeButton.disabled = on
	if text != "":
		_set_status(text)

func _cost_text(result:Dictionary) -> String:
	var cost = result.get("cost")
	return "  (Cost: $%.4f)" % cost if cost is float else ""


#####################################
############## DRESS ME #############
#####################################

func dress() -> void:
	if busy:
		return
	var occasion = %OccasionEdit.text.strip_edges()
	if occasion == "":
		_set_status("Say where the doll is going first, like \"%s\"." % %OccasionEdit.placeholder_text)
		return
	if not _has_key():
		return
	var menu = _menu()
	_set_busy(true, "Picking an outfit...")
	var result = await client.ask_json(text_model, stylist_instructions, _stylist_question(occasion, menu))
	_set_busy(false)
	if not result.ok:
		_set_status(result.error)
		return
	var changed = _wear_choices(result.data, menu)
	if changed == 0:
		_set_status("The stylist couldn't find anything new to try. Describe it differently?")
		return
	var comment = str(result.data.get("comment", "")).strip_edges()
	_set_status((comment if comment != "" else "Here's your new look!") + _cost_text(result))
	Sfx.play("sparkle")

# Everything the stylist can choose from:
#   [{"layer": "03Hair", "name": "Hair", "items": {"bob curly": "bob_curly.PNG", ...}}, ...]
func _menu() -> Array:
	var menu := []
	for i in len(interactivity.layers):
		var layer: String = interactivity.layers[i]
		var items := {}
		for id in interactivity.tab_nodes[i].get_item_ids():
			var label = interactivity.tab_nodes[i].item_label(id).to_lower().left(80)
			var unique = label
			var number = 2
			while items.has(unique):
				unique = "%s %d" % [label, number]
				number += 1
			items[unique] = id
		if items.is_empty():
			continue
		# "03Hair" is shown to the model as "Hair"
		var layer_name = layer.lstrip("0123456789 _-")
		if layer_name == "" or menu.any(func(entry): return entry.name == layer_name):
			layer_name = layer
		menu.append({"layer": layer, "name": layer_name, "items": items})
	return menu

func _stylist_question(occasion:String, menu:Array) -> String:
	var lines := ["Occasion: " + occasion, "", "Layers and the items you can choose from:"]
	for entry in menu:
		var notes := []
		if interactivity.is_background(entry.layer):
			notes.append("the background behind the doll, can't be recolored")
		elif interactivity.is_required(entry.layer):
			notes.append("must have an item")
		else:
			notes.append("can be \"none\"")
		lines.append("- %s (%s): %s" % [entry.name, ", ".join(notes), JSON.stringify(entry.items.keys())])
	lines.append("")
	lines.append("Colors: " + ", ".join(interactivity.tab_nodes[0].SWATCH_NAMES))
	lines.append("(\"original\" keeps the item's own colors.)")
	lines.append("")
	lines.append("Reply with JSON like: {\"choices\": {\"<layer>\": {\"item\": \"<item name or none>\", \"color\": \"<color>\"}}, \"comment\": \"<one fun sentence about the look>\"}")
	return "\n".join(lines)

# Puts on what the stylist picked. Names that aren't in the menu are skipped.
# Returns how many layers changed.
func _wear_choices(answer:Dictionary, menu:Array) -> int:
	var choices = answer.get("choices")
	if not choices is Dictionary:
		return 0
	var names: Array = interactivity.tab_nodes[0].SWATCH_NAMES
	var hues: Array = interactivity.tab_nodes[0].SWATCH_HUES
	var new_outfit = interactivity.outfit.duplicate(true)
	for layer_name in choices:
		var entry = menu.filter(func(e): return e.name.to_lower() == str(layer_name).to_lower().strip_edges())
		var choice = choices[layer_name]
		if entry.is_empty() or not choice is Dictionary:
			continue
		var layer: String = entry[0].layer
		var item = str(choice.get("item", "")).to_lower().strip_edges()
		if item in ["none", "nothing", ""]:
			if not interactivity.is_required(layer):
				new_outfit[layer].item = ""
		elif entry[0].items.has(item):
			new_outfit[layer].item = entry[0].items[item]
		var color = names.find(str(choice.get("color", "original")).to_lower().strip_edges())
		if not interactivity.is_background(layer):
			new_outfit[layer].hue = hues[color] if color >= 0 else interactivity.NO_COLOR
	var changed = 0
	for layer in interactivity.layers:
		if interactivity.cleaned_outfit(new_outfit)[layer] != interactivity.outfit[layer]:
			changed += 1
	interactivity.set_outfit(new_outfit)
	return changed


#####################################
############## JUDGE ME #############
#####################################

func judge() -> void:
	if busy or not _has_key():
		return
	_set_busy(true, "The judge is taking a good look...")
	%Result.hide()
	# the picture is taken without this window in it
	hide()
	var picture: Image = await toolbar.capture_scene()
	show()
	var height = roundi(judge_picture_width * float(picture.get_height()) / picture.get_width())
	picture.resize(judge_picture_width, height, Image.INTERPOLATE_BILINEAR)

	var theme_name = toolbar.challenge_theme()
	var question = "The challenge theme is: %s." % theme_name if theme_name != "" else "There is no theme. Just judge the look."
	question += "\nReply with JSON like: {\"score\": 8, \"title\": \"<name for the look>\", \"comment\": \"<feedback>\"}"
	var result = await client.ask_json(text_model, judge_instructions, question, picture)
	_set_busy(false)
	if not result.ok:
		_set_status(result.error)
		return
	var score = clampi(roundi(float(result.data.get("score", 0))), 1, MAX_SCORE)
	for i in MAX_SCORE:
		%Stars.get_child(i).modulate = Color.WHITE if i < score else Color(1, 1, 1, 0.18)
	%ScoreLabel.text = "%d / %d" % [score, MAX_SCORE]
	%ResultTitle.text = str(result.data.get("title", "")).strip_edges()
	%ResultTitle.visible = %ResultTitle.text != ""
	%ResultComment.text = str(result.data.get("comment", "")).strip_edges()
	%Result.show()
	_set_status(_cost_text(result).strip_edges())
	Sfx.play("sparkle")

func _set_status(text: String) -> void:
	%StatusLabel.text = text
	%StatusLabel.visible = text != ""
