# The sculpt brush: push the doll into any shape by dragging on it (see body_sculpt.gd).
#   - drag on the doll to push it; the slider in the bar (or the mouse wheel) sizes the brush
#   - with Restore on, the brush eases pushed parts back to the doll as drawn
#   - Undo takes back the last stroke, Clear takes back every push
#   - Done puts it on (it can be undone like any other change), Cancel (or Escape) forgets it
# The Sculpt button in the Body menu starts it. The sliders still work on the sculpted doll,
# and "As drawn" in the Body menu takes the sculpt off too.

extends Node2D

@export var body_shaper: Node2D
# Hidden while sculpting, so the outfit can't change meanwhile
@export var ui_root: Control
@export var sticker_stage: Node2D

const BodyFitter = preload("res://script/body_fitter.gd")
# Smallest and biggest brush (its radius in pixels on screen), and the one it starts with
const BRUSH_SIZES := Vector2(10, 90)
const START_BRUSH := 30.0
# How many strokes Undo can take back
const MAX_UNDO := 30
const COLOR := Color(0.2, 0.33, 0.85)

var sculpting := false
var started_from := PackedVector2Array() # the sculpt when sculpting started, for Cancel
var strokes := [] # the sculpt before each stroke, for Undo
var pressing := false
var last_point := Vector2.ZERO
var cursor := Vector2.ZERO
var bar: Control
var brush_slider: HSlider
var restore_button: Button

func _ready() -> void:
	z_index = 101 # above the doll
	var layer = CanvasLayer.new()
	add_child(layer)
	bar = BodyFitter.make_bar(layer, "Drag on the doll to push it into shape.",
		[["Restore", queue_redraw], ["Undo", _undo], ["Clear", _clear],
		["Cancel", func(): _finish(false)], ["Done", func(): _finish(true)]])
	var row: Control = bar.get_meta("row")
	restore_button = row.get_child(0)
	restore_button.toggle_mode = true
	restore_button.tooltip_text = "Brush pushed parts back to how they were drawn"
	brush_slider = HSlider.new()
	brush_slider.min_value = BRUSH_SIZES.x
	brush_slider.max_value = BRUSH_SIZES.y
	brush_slider.value = START_BRUSH
	brush_slider.custom_minimum_size = Vector2(90, 0)
	brush_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_slider.focus_mode = Control.FOCUS_NONE
	brush_slider.tooltip_text = "Brush size (or scroll)"
	brush_slider.value_changed.connect(func(_value): queue_redraw())
	row.add_child(brush_slider)
	row.move_child(brush_slider, 0)

func start() -> void:
	if sculpting:
		return
	sculpting = true
	started_from = body_shaper.sculpt.offsets.duplicate()
	strokes = []
	restore_button.button_pressed = false
	ui_root.hide()
	sticker_stage.deselect()
	sticker_stage.hide()
	bar.show()
	queue_redraw()

func _finish(keep:bool) -> void:
	if not sculpting:
		return
	sculpting = false
	pressing = false
	ui_root.show()
	sticker_stage.show()
	bar.hide()
	queue_redraw()
	if keep:
		var new_values = body_shaper.values.duplicate()
		var saved = body_shaper.sculpt.to_saved()
		if saved.is_empty():
			new_values.erase(body_shaper.SCULPT)
		else:
			new_values[body_shaper.SCULPT] = saved
		SignalBus.dressup_body_signal.emit(new_values)
	else:
		body_shaper.sculpt.offsets = started_from
		body_shaper.show_sculpt()
		Sfx.play("click")

func _undo() -> void:
	if strokes.is_empty():
		return
	body_shaper.sculpt.offsets = strokes.pop_back()
	body_shaper.show_sculpt()

func _clear() -> void:
	_remember()
	body_shaper.sculpt.clear()
	body_shaper.show_sculpt()

# Keeps the sculpt as it is, for Undo
func _remember() -> void:
	strokes.append(body_shaper.sculpt.offsets.duplicate())
	if len(strokes) > MAX_UNDO:
		strokes.pop_front()

func _unhandled_input(event:InputEvent) -> void:
	if not sculpting:
		return
	# nothing else (stickers, undo...) reacts while sculpting
	get_viewport().set_input_as_handled()
	var point = get_canvas_transform().affine_inverse() * event.position if event is InputEventMouse else Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressing = event.pressed
		if pressing:
			_remember()
			last_point = point
	elif event is InputEventMouseButton and event.pressed:
		var step = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0
		brush_slider.value += step * 4
	elif event is InputEventMouseMotion:
		cursor = point
		if pressing:
			_stroke(last_point, point)
			last_point = point
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_finish(true)
		elif event.keycode == KEY_ESCAPE:
			_finish(false)

# Pushes (or restores) the doll along the brush's move from one point to another on screen
func _stroke(from:Vector2, to:Vector2) -> void:
	if from == to:
		return
	var sculpt = body_shaper.sculpt
	# what is shown under the brush, on the sculpted doll before the sliders change it
	var middle = sculpt.from_screen * sculpt.shaped(body_shaper.unshaped(from))
	var radius = brush_slider.value / sculpt.to_screen.get_scale().x
	if restore_button.button_pressed:
		sculpt.restore(middle, radius, from.distance_to(to) / brush_slider.value)
	else:
		sculpt.push(middle, sculpt.from_screen.basis_xform(to - from), radius)
	body_shaper.show_sculpt()

func _draw() -> void:
	if not sculpting:
		return
	draw_circle(cursor, brush_slider.value, Color(1, 1, 1, 0.12))
	draw_arc(cursor, brush_slider.value, 0.0, TAU, 48, Color.WHITE, 3.0, true)
	draw_arc(cursor, brush_slider.value, 0.0, TAU, 48, COLOR, 1.5, true)
