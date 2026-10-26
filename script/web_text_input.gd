# Typing and pasting on phones and tablets in the web version.
# The game draws its own text boxes, so iOS Safari shows no keyboard or Paste menu for them.
# On a touch screen in a browser, tapping a text box opens the browser's own text prompt instead,
# which has the normal keyboard and Paste, and the answer goes into the text box.

extends Node

func _ready() -> void:
	if not OS.has_feature("web") or not DisplayServer.is_touchscreen_available():
		return
	get_tree().node_added.connect(_watch)
	for node in get_tree().root.find_children("*", "", true, false):
		_watch(node)

func _watch(node:Node) -> void:
	if node is LineEdit or node is TextEdit:
		node.gui_input.connect(func(event): _on_text_box_input(node, event))

func _on_text_box_input(text_box, event:InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		return
	if not text_box.editable:
		return
	text_box.accept_event()
	var label = text_box.placeholder_text if text_box.placeholder_text != "" else "Type here"
	var answer = JavaScriptBridge.eval("prompt(%s, %s)" % [JSON.stringify(label), JSON.stringify(text_box.text)])
	text_box.release_focus()
	if answer == null: # Cancel was pressed
		return
	text_box.text = answer
	if text_box is LineEdit:
		text_box.text_changed.emit(text_box.text)
	else:
		text_box.text_changed.emit()
