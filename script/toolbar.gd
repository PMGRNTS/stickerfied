# The tool buttons around the menu: undo/redo, random, reset, zoom,
# save, saved outfits, share codes, photo, AI Create, AI Stylist and challenges.
# Move or restyle the buttons in GUI/toolbar.tscn.

extends Control

@export var interactivity: Node
# Hidden for a moment while taking a photo, so the menus aren't in the picture
@export var ui_root: Control
@export var outfit_gallery: OverlayDialog
@export var share_dialog: OverlayDialog
@export var ai_create_dialog: OverlayDialog
@export var ai_stylist_dialog: OverlayDialog
# Its selection frame is hidden while taking a photo
@export var sticker_stage: Node2D
# Zooms in on the doll (see stage_zoom.gd); photos are taken zoomed out
@export var stage_zoom: Node

const THUMBNAIL_SIZE := Vector2i(180, 120)
const SOUND_ON_ICON = preload("res://GUI/sound_on.svg")
const SOUND_OFF_ICON = preload("res://GUI/sound_off.svg")

var toast_tween: Tween

func _ready() -> void:
	%UndoButton.pressed.connect(interactivity.undo)
	%RedoButton.pressed.connect(interactivity.redo)
	%RandomButton.pressed.connect(interactivity.randomize_outfit)
	%ResetButton.pressed.connect(interactivity.reset)
	%SaveButton.pressed.connect(save_outfit)
	%OutfitsButton.pressed.connect(outfit_gallery.open)
	%ShareButton.pressed.connect(share_dialog.open)
	%PhotoButton.pressed.connect(take_photo)
	%AIButton.pressed.connect(ai_create_dialog.open)
	%StylistButton.pressed.connect(ai_stylist_dialog.open)
	%ChallengeBar.judge_requested.connect(func(): ai_stylist_dialog.open_for(ai_stylist_dialog.Mode.JUDGE))
	%ChallengeBar.message.connect(show_message)
	interactivity.outfit_changed.connect(_update_buttons)
	if stage_zoom:
		%ZoomInButton.pressed.connect(stage_zoom.zoom_in)
		%ZoomOutButton.pressed.connect(stage_zoom.zoom_out)
		%ZoomResetButton.pressed.connect(stage_zoom.reset)
		stage_zoom.zoom_changed.connect(_show_zoom)
	else:
		%ZoomBar.hide()
	%SoundButton.pressed.connect(func(): Sfx.set_muted(not Sfx.is_muted()))
	Sfx.muted_changed.connect(_show_sound_state)
	_show_sound_state(Sfx.is_muted())
	%Toast.hide()

func _show_sound_state(muted: bool) -> void:
	%SoundButton.icon = SOUND_OFF_ICON if muted else SOUND_ON_ICON
	%SoundButton.tooltip_text = "Sound is off" if muted else "Sound is on"

func _show_zoom(zoom: float) -> void:
	%ZoomResetButton.text = "%d%%" % roundi(zoom * 100)
	%ZoomOutButton.disabled = zoom <= 1.0
	%ZoomInButton.disabled = zoom >= stage_zoom.MAX_ZOOM

func _update_buttons() -> void:
	%UndoButton.disabled = interactivity.undo_stack.is_empty()
	%RedoButton.disabled = interactivity.redo_stack.is_empty()

# Ctrl+Z / Ctrl+Shift+Z (Cmd on Mac)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_redo"):
		interactivity.redo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_undo"):
		interactivity.undo()
		get_viewport().set_input_as_handled()


# The theme of the challenge being played, or "" when there is none
func challenge_theme() -> String:
	return %ChallengeBar.current_theme

# A short message at the top of the screen that fades away
func show_message(text: String) -> void:
	%ToastLabel.text = text
	%Toast.show()
	%Toast.modulate.a = 1.0
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.5)
	toast_tween.tween_property(%Toast, "modulate:a", 0.0, 0.5)
	toast_tween.tween_callback(%Toast.hide)


# Takes a picture of the doll and background, without the menus, zoomed out
func capture_scene() -> Image:
	sticker_stage.deselect()
	ui_root.hide()
	var view = get_viewport().canvas_transform
	get_viewport().canvas_transform = Transform2D()
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	get_viewport().canvas_transform = view
	ui_root.show()
	return image

func save_outfit() -> void:
	var thumbnail: Image = await capture_scene()
	thumbnail.resize(THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, Image.INTERPOLATE_BILINEAR)
	OutfitStore.save_outfit(interactivity.outfit, thumbnail)
	Sfx.play("sparkle")
	show_message("Outfit saved! Find it under Outfits.")

func take_photo() -> void:
	var image: Image = await capture_scene()
	Sfx.play("shutter")
	if OS.has_feature("web"):
		# In the browser, the picture is downloaded like any other file
		JavaScriptBridge.download_buffer(image.save_png_to_buffer(), "my_outfit.png", "image/png")
		show_message("Photo downloaded!")
		return
	var folder = "user://photos/"
	DirAccess.make_dir_recursive_absolute(folder)
	var path = folder + "outfit_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	if image.save_png(path) != OK:
		show_message("Couldn't save the photo.")
		return
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))
	show_message("Photo saved!")
