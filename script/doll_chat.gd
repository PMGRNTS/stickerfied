# A chat window for talking to the doll, using a text model on OpenRouter.
# She answers in character (see doll_mood.gd), in her speech bubble and here,
# with a face to match. She knows what she's wearing, what she thinks of it,
# and how she feels (sulking, bored, waiting for something she asked for...).
# The window sits over the menu, so the doll stays in sight while you talk.
# It uses the same OpenRouter key as the AI Create and AI Stylist windows.
# Her system prompt and model can be changed in the window (Settings) or in the Inspector.

extends OverlayDialog

@export var interactivity: Node
# Her faces, bubble and feelings. Without it she still chats, but only here.
@export var doll_mood: Node
@export var doll_name := "Coco"
# Any model from https://openrouter.ai/models works; cheaper ones answer faster.
# Players can pick their own under Settings.
@export var text_model := "anthropic/claude-haiku-5.5"
# How many messages (yours and hers) the model remembers
@export var memory := 20
# Who she is (her system prompt); %s is her name. Players can write their own under Settings.
@export_multiline var chat_instructions := "You are %s, the doll in a dress-up game for all ages, and the player is chatting with you. You are a bratty, high-maintenance fashion diva: dramatic, vain and sassy, but secretly sweet and funny. You care about clothes, colors, looking expensive and being the center of attention. Answer in one or two short sentences, like a text message, and stay in character. Keep it friendly for kids: tease the outfit, never the player, and never comment on anyone's body. Don't ask for or share personal details. If asked about things outside the game, answer briefly in character or change the subject to fashion. Reply only with JSON."

const NAME_COLOR := Color(0.78, 0.2, 0.55)
const YOUR_COLOR := Color(0.45, 0.42, 0.6)

@onready var client: OpenRouterClient = $OpenRouterClient

var history := [] # [{"role": "user" or "assistant", "content": "..."}, ...]
var busy := false
var own_prompt := "" # the player's own system prompt, "" for chat_instructions
var own_model := "" # the player's own model, "" for text_model

func _ready() -> void:
	super()
	%SendButton.pressed.connect(send)
	%MessageEdit.text_submitted.connect(func(_text): send())
	%CloseButton.pressed.connect(close)
	%KeyEdit.text_changed.connect(func(_text): AIKey.save_key(%KeyEdit.text, %RememberKey.button_pressed))
	%RememberKey.toggled.connect(func(on): AIKey.save_key(%KeyEdit.text, on))
	%SettingsToggle.toggled.connect(_show_settings)
	# TextEdit also says its text changed when the game fills it in, so only real changes are saved
	%PromptEdit.text_changed.connect(func():
		var text = %PromptEdit.text.strip_edges()
		text = text if text != chat_instructions.strip_edges() else ""
		if text != own_prompt:
			own_prompt = text
			save_settings())
	%ModelEdit.text_changed.connect(func(text):
		text = text.strip_edges()
		own_model = text if text != text_model else ""
		save_settings())
	%ResetButton.pressed.connect(func():
		own_prompt = ""
		own_model = ""
		_fill_settings()
		save_settings())
	%ClearButton.pressed.connect(func():
		history = []
		for line in %Messages.get_children():
			line.queue_free()
		_show_settings(false))
	%Title.text = "Chat with " + doll_name
	%MessageEdit.placeholder_text = "Say something to %s..." % doll_name
	load_settings()
	_fill_settings()
	_set_status("")

func _on_open() -> void:
	# the key may have been changed in another AI window
	%KeyEdit.text = AIKey.current_key()
	%RememberKey.set_pressed_no_signal(AIKey.remembers_key())
	%MessageEdit.grab_focus()

func send() -> void:
	var message = %MessageEdit.text.strip_edges()
	if busy or message == "":
		return
	client.api_key = %KeyEdit.text.strip_edges()
	if client.api_key == "" and client.base_url.contains("openrouter.ai"):
		_set_status("Paste your OpenRouter API key below first.")
		return
	%MessageEdit.text = ""
	_add_line("You", message)
	_set_busy(true)
	if doll_mood:
		doll_mood.listen()
	_show_settings(false)
	var result = await client.ask_json(own_model if own_model != "" else text_model, _instructions(), message, null, history)
	_set_busy(false)
	if not result.ok:
		_set_status(result.error)
		return
	var text = str(result.data.get("say", "")).strip_edges()
	var feeling = str(result.data.get("feeling", "neutral")).to_lower().strip_edges()
	if text == "":
		_set_status("%s didn't answer. Try again." % doll_name)
		return
	history.append({"role": "user", "content": message})
	history.append({"role": "assistant", "content": JSON.stringify({"say": text, "feeling": feeling})})
	if len(history) > memory:
		history = history.slice(len(history) - memory)
	_add_line(doll_name, text)
	var cost = result.get("cost")
	_set_status("Cost: $%.4f" % cost if cost is float else "")
	if doll_mood:
		doll_mood.answer(text, feeling)

# Who she is, what she's wearing and how she feels right now, and how to answer
func _instructions() -> String:
	var prompt = own_prompt if own_prompt != "" else chat_instructions
	var who = prompt.replace("%s", doll_name)
	var lines := [who, "", "Right now:"]
	lines.append_array(_outfit_lines())
	if doll_mood:
		lines.append_array(doll_mood.describe_for_chat())
	lines.append("")
	var feelings = doll_mood.FEELINGS if doll_mood else ["neutral"]
	lines.append("Reply with JSON like: {\"say\": \"<what you say>\", \"feeling\": \"<one of: %s>\"}" % ", ".join(feelings))
	return "\n".join(lines)

# What she's wearing, such as "- Hair: epic curly, in pink (you love it)"
func _outfit_lines() -> Array:
	var lines := []
	var tab = interactivity.tab_nodes[0]
	for i in len(interactivity.layers):
		var layer: String = interactivity.layers[i]
		var worn = interactivity.outfit.get(layer, {})
		if worn.get("item", "") == "":
			continue
		var line = "- %s: %s" % [_layer_name(layer), tab.item_label(worn.item)]
		if worn.hue >= 0.0:
			line += ", in " + tab.SWATCH_NAMES[_closest_swatch(worn.hue)]
		if interactivity.is_background(layer):
			line = "- Background: " + tab.item_label(worn.item)
		elif interactivity.is_required(layer):
			continue # her body
		if doll_mood:
			line += [" (you hate it)", "", " (you love it)"][doll_mood.opinion_of(layer, worn.item, worn.hue) + 1]
		lines.append(line)
	var stickers = interactivity.outfit.get(interactivity.STICKERS, [])
	if not stickers.is_empty():
		lines.append("- Stickers: " + ", ".join(stickers.map(func(sticker): return tab.item_label(sticker.id))))
	if lines.is_empty():
		return ["You're wearing nothing but your base look."]
	lines.push_front("You're wearing:")
	return lines

func _closest_swatch(hue:float) -> int:
	var hues: Array = interactivity.tab_nodes[0].SWATCH_HUES
	var closest = 1
	for i in range(1, len(hues)):
		if absf(hues[i] - hue) < absf(hues[closest] - hue):
			closest = i
	return closest

# "03Hair" is "Hair"
static func _layer_name(layer:String) -> String:
	var name = layer.lstrip("0123456789 _-")
	return name if name != "" else layer

# Shows her prompt and model in place of the conversation, or the other way around
func _show_settings(on:bool) -> void:
	%SettingsToggle.set_pressed_no_signal(on)
	%SettingsBox.visible = on
	%Log.visible = not on

func _fill_settings() -> void:
	%PromptEdit.text = own_prompt if own_prompt != "" else chat_instructions
	%ModelEdit.placeholder_text = text_model
	%ModelEdit.text = own_model if own_model != "" else text_model

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(AIKey.SETTINGS_FILE) != OK:
		return
	own_prompt = config.get_value("doll_chat", "prompt", "")
	own_model = config.get_value("doll_chat", "model", "")

func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(AIKey.SETTINGS_FILE) # keeps the settings saved by other windows
	config.set_value("doll_chat", "prompt", own_prompt)
	config.set_value("doll_chat", "model", own_model)
	config.save(AIKey.SETTINGS_FILE)

# Adds a message to the conversation, and scrolls down to it
func _add_line(who:String, text:String) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.selection_enabled = true
	line.add_theme_color_override("default_color", get_theme_color("font_color", "Label"))
	var color = NAME_COLOR if who == doll_name else YOUR_COLOR
	line.text = "[color=#%s]%s:[/color] %s" % [color.to_html(false), who, text.replace("[", "[lb]")]
	%Messages.add_child(line)
	await get_tree().process_frame
	%Log.scroll_vertical = int(%Log.get_v_scroll_bar().max_value)

func _set_busy(on:bool) -> void:
	busy = on
	%SendButton.disabled = on
	%Typing.text = "%s is typing..." % doll_name
	%Typing.visible = on
	if on:
		_set_status("")

func _set_status(text: String) -> void:
	%StatusLabel.text = text
	%StatusLabel.visible = text != ""
