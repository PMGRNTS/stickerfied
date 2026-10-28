# Zooms in on the doll, so stickers and pictures can be put on small parts of it.
# Everything but the menus zooms (the menus are on their own CanvasLayer, "Menus").
#   - the zoom buttons (top left), or Ctrl/Cmd + plus, minus and 0
#   - Ctrl/Cmd + mouse wheel, or pinching on a trackpad (away from a selected sticker,
#     which pinching resizes), zooms around the pointer
#   - when zoomed in, drag with the right or middle mouse button, or hold Space and drag,
#     to look around; two-finger scrolling on a trackpad does too
# These also work while erasing, sculpting and fitting points.
# Photos and saved outfits' pictures always show the whole doll (see toolbar.gd).

extends Node

signal zoom_changed(zoom:float)

const MAX_ZOOM := 4.0
# How much one press of a zoom button, or one turn of the mouse wheel, zooms
const BUTTON_STEP := 1.25
const WHEEL_STEP := 1.1
# How far two-finger scrolling on a trackpad moves the view
const PAN_SPEED := 40.0

# Pinching on its selection resizes the stickers instead of zooming
@export var sticker_stage: Node2D
# The buttons zoom around the selected stickers, or this when none are selected
# (the SpritePlaceholder marks the middle of the doll)
@export var focus_point: Node2D

var zoom := 1.0
var origin := Vector2.ZERO # where the stage's top-left corner is on the screen
var panning := false

func zoom_in() -> void:
	zoom_by(BUTTON_STEP, _focus())

func zoom_out() -> void:
	zoom_by(1.0 / BUTTON_STEP, _focus())

# Back to the whole doll
func reset() -> void:
	zoom = 1.0
	origin = Vector2.ZERO
	_apply()

# Zooms by factor, keeping around (a point on the stage) where it is on the screen
func zoom_by(factor:float, around:Vector2) -> void:
	var on_screen = _view() * around
	zoom = clampf(zoom * factor, 1.0, MAX_ZOOM)
	origin = on_screen - around * zoom
	_apply()

func pan_by(offset:Vector2) -> void:
	origin += offset
	_apply()

func _view() -> Transform2D:
	return Transform2D(0.0, Vector2.ONE * zoom, 0.0, origin)

func _focus() -> Vector2:
	if sticker_stage and sticker_stage.visible and not sticker_stage.selection.is_empty():
		return sticker_stage.selection_middle()
	if focus_point:
		return focus_point.global_position
	return get_viewport().get_visible_rect().size / 2

# Shows the zoom, never past the edges of the stage
func _apply() -> void:
	var size = get_viewport().get_visible_rect().size
	origin = origin.clamp(size * (1.0 - zoom), Vector2.ZERO)
	get_viewport().canvas_transform = _view()
	zoom_changed.emit(zoom)

# This node is last in the scene, so it sees input before the stickers and tools do,
# and only takes what it uses
func _unhandled_input(event:InputEvent) -> void:
	var point = _view().affine_inverse() * event.position if event is InputEventMouse or event is InputEventGesture else Vector2.ZERO
	if event is InputEventMouseButton:
		var drags = event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE] \
			or (event.button_index == MOUSE_BUTTON_LEFT and (panning or (event.pressed and Input.is_key_pressed(KEY_SPACE))))
		var step = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0
		if drags and (zoom > 1.0 or panning):
			panning = event.pressed
		elif step != 0 and event.pressed and _with_ctrl(event):
			zoom_by(pow(WHEEL_STEP, step), point)
		else:
			return
	elif event is InputEventMouseMotion and panning:
		pan_by(event.relative)
	elif event is InputEventPanGesture and zoom > 1.0:
		pan_by(-event.delta * PAN_SPEED)
	elif event is InputEventMagnifyGesture and sticker_stage and sticker_stage.visible \
			and not (not sticker_stage.selection.is_empty() and sticker_stage.is_on_selection(point)):
		zoom_by(event.factor, point)
	elif event is InputEventKey and event.pressed and _with_ctrl(event):
		if event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			zoom_in()
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			zoom_out()
		elif event.keycode in [KEY_0, KEY_KP_0]:
			reset()
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()

# Ctrl, or Cmd on a Mac (either works everywhere)
static func _with_ctrl(event:InputEventWithModifiers) -> bool:
	return event.ctrl_pressed or event.meta_pressed
