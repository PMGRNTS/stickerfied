# Shared code for the pop-up windows (saved outfits, share codes, AI backgrounds).
# The window dims the game behind it. Press Escape or the Close button to hide it.

class_name OverlayDialog
extends Control

func _ready() -> void:
	hide()

func open() -> void:
	show()
	_on_open()

func close() -> void:
	hide()

# Override this in a pop-up's script to refresh its contents when it opens
func _on_open() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
