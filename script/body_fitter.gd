# Lets the player move the Body menu's controls to fit their doll, for bodies that aren't
# shaped like the one the controls were placed on (such as a body made with AI or uploaded).
#   - the doll is shown as drawn, and one point is worked on at a time: its areas are shown,
#     and the other points are small dots. Tap a dot, or step with Prev and Next (Tab and
#     Shift+Tab), to work on another. Hovering over a dot shows what it is.
#     Controls in the same spot (such as everything on one eye) share a point and move together.
#   - drag the point's circle, or anywhere inside its area, onto the matching part of the doll
#     (the arrow keys nudge it, more with Shift)
#   - drag the small square at its corner, or turn the mouse wheel, to make its area bigger or smaller
#   - Find parts puts the points on the parts the game finds in the doll's pictures, and
#     Standard where they usually are on a doll standing straight and facing forward
#     (see body_finder.gd; only controls with a Landmark move)
#   - Done keeps the fit for the body picture worn now (each body has its own, see
#     body_shaper.gd), Reset puts the controls back where the game placed them,
#     and Cancel (or Escape) forgets the changes
# The Fit points button in the Body menu starts it.

extends Node2D

const BodyControl = preload("res://script/body_control.gd")

@export var body_shaper: Node2D
# Hidden while fitting, so the outfit can't change meanwhile
@export var ui_root: Control
@export var sticker_stage: Node2D

const HANDLE_RADIUS := 8.0
const DOT_RADIUS := 4.5
const CORNER_SIZE := 6.0
# How far from a circle, dot or square a press still catches it: more on touch screens, for fingers
const GRAB_MOUSE := 4.0
const GRAB_TOUCH := 14.0
const COLOR := Color(0.2, 0.33, 0.85)
const SWING_COLOR := Color(0.2, 0.6, 0.4)
const LABEL_SIZE := 11
const HINT := "Drag the circle onto the matching part of your doll, and the square to resize it. Tap a dot to fit another point."
# How much one turn of the mouse wheel resizes
const WHEEL_STEP := 1.05

enum Drag { NONE, MOVE, RESIZE }

var fitting := false
var spots := [] # [{"controls": [...], "label": "Eye size, Eye spacing"}], one per point
var before := [] # [position, reach] of every control when fitting started, for Cancel
var chosen := 0 # the spot being worked on
var hovered := -1 # the spot under the mouse
var drag := Drag.NONE
var drag_start_point := Vector2.ZERO
var drag_start := [] # [position, reach] of each control in the chosen spot when the drag started
var grab := GRAB_MOUSE
var bar: Control
var hint: Label
var title: Label # names the chosen spot

func _ready() -> void:
	z_index = 101 # above the doll and the stickers
	grab = GRAB_TOUCH if DisplayServer.is_touchscreen_available() else GRAB_MOUSE
	var layer = CanvasLayer.new()
	add_child(layer)
	bar = make_bar(layer, HINT, [["Find parts", func(): _place(true)], ["Standard", func(): _place(false)],
		["Reset", _reset], ["Cancel", func(): _finish(false)], ["Done", func(): _finish(true)]])
	var row: Control = bar.get_meta("row")
	row.get_child(0).tooltip_text = "Put the points on the parts of the doll the game finds"
	row.get_child(1).tooltip_text = "Put the points where they go on a doll standing straight and facing forward"
	row.get_child(2).tooltip_text = "Put the points back where the game placed them"
	var column = row.get_parent()
	hint = column.get_child(0)
	# Prev, the chosen point's name and Next, above the buttons
	var stepper = HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 8)
	column.add_child(stepper)
	column.move_child(stepper, row.get_index())
	stepper.add_child(_step_button("Prev", -1))
	title = Label.new()
	title.theme_type_variation = &"ToastLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(120, 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stepper.add_child(title)
	stepper.add_child(_step_button("Next", 1))

func _step_button(text:String, step:int) -> Button:
	var button = Button.new()
	button.theme_type_variation = &"ToolButton"
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): _choose(wrapi(chosen + step, 0, len(spots))))
	return button

func start() -> void:
	if fitting:
		return
	fitting = true
	body_shaper.hold_neutral(true)
	ui_root.hide()
	sticker_stage.deselect()
	sticker_stage.hide()
	bar.show()
	hint.text = HINT
	before = body_shaper.controls().map(func(control): return [control.global_position, control.reach])
	_group()
	_choose(0)

# Controls in the same spot, on the same landmark, share a point
func _group() -> void:
	var was = spots[chosen].controls[0] if chosen < len(spots) else null
	var by_spot := {}
	spots = []
	for control in body_shaper.controls():
		var spot = Vector2i(control.global_position.round())
		var key = Vector3i(spot.x, spot.y, control.landmark)
		if not by_spot.has(key):
			by_spot[key] = {"controls": [], "label": ""}
			spots.append(by_spot[key])
		by_spot[key].controls.append(control)
	for spot in spots:
		var names := []
		for control in spot.controls:
			var name_shown = control.slider if control.slider != "" and control.group != "" else String(control.name).capitalize()
			if not name_shown in names:
				names.append(name_shown)
		spot.label = ", ".join(names)
	hovered = -1
	# keep working on the same point
	chosen = maxi(0, spots.find_custom(func(spot): return was in spot.controls))

func _choose(index:int) -> void:
	chosen = index
	if chosen < len(spots):
		title.text = "%s\n%d of %d" % [spots[chosen].label, chosen + 1, len(spots)]
	queue_redraw()

func _finish(keep:bool) -> void:
	if not fitting:
		return
	fitting = false
	drag = Drag.NONE
	if keep:
		body_shaper.save_fit()
	else:
		var controls = body_shaper.controls()
		for i in len(controls):
			controls[i].global_position = before[i][0]
			controls[i].reach = before[i][1]
	body_shaper.hold_neutral(false)
	ui_root.show()
	sticker_stage.show()
	bar.hide()
	queue_redraw()
	Sfx.play("click")

# Puts the controls on the doll's parts: found in its pictures, or where they usually are
func _place(find:bool) -> void:
	if not body_shaper.place_on_parts(find):
		hint.text = "The doll's picture couldn't be looked at, so the points stay where they are."
		return
	hint.text = HINT
	_group()
	_choose(chosen)
	Sfx.play("click")

# Puts every control back where the game placed it
func _reset() -> void:
	for control in body_shaper.controls():
		var placed = body_shaper.default_of(control)
		control.global_position = placed[0]
		control.reach = placed[1]
	_group()
	_choose(chosen)

# The middle of a spot, where its point is
static func _middle(spot:Dictionary) -> Vector2:
	return spot.controls[0].global_position

# The spot's resize square: at the corner of its biggest area
static func _corner(spot:Dictionary) -> Vector2:
	var biggest = Vector2.ZERO
	for control in spot.controls:
		biggest = biggest.max(control.reach)
	return _middle(spot) + biggest

# Whether point is inside the control's oval, strip or turn band
static func _inside(control:Node2D, point:Vector2) -> bool:
	var away = (point - control.global_position) / control.reach.max(Vector2.ONE)
	return away.length() < 1.0 if control.shape == BodyControl.Shape.AREA else absf(away.x) < 1.0 and absf(away.y) < 1.0

# What a press at point catches: [spot index, Drag], or [-1, NONE] for nothing.
# The chosen spot's square and circle come first, then the other dots,
# then anywhere inside the chosen spot's areas.
func _spot_at(point:Vector2) -> Array:
	if chosen < len(spots):
		if point.distance_to(_corner(spots[chosen])) <= CORNER_SIZE + grab:
			return [chosen, Drag.RESIZE]
		if point.distance_to(_middle(spots[chosen])) <= HANDLE_RADIUS + grab:
			return [chosen, Drag.MOVE]
	var best = -1
	var nearest = INF
	for i in len(spots):
		var distance = point.distance_to(_middle(spots[i]))
		if i != chosen and distance <= DOT_RADIUS + grab and distance < nearest:
			nearest = distance
			best = i
	if best >= 0:
		return [best, Drag.MOVE]
	if chosen < len(spots) and spots[chosen].controls.any(func(control): return _inside(control, point)):
		return [chosen, Drag.MOVE]
	return [-1, Drag.NONE]

func _unhandled_input(event:InputEvent) -> void:
	if not fitting:
		return
	# nothing else (stickers, undo...) reacts while fitting
	get_viewport().set_input_as_handled()
	var point = get_canvas_transform().affine_inverse() * event.position if event is InputEventMouse else Vector2.ZERO
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed and drag == Drag.NONE and chosen < len(spots):
			var factor = WHEEL_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_STEP
			for control in spots[chosen].controls:
				control.reach = (control.reach * factor).max(Vector2.ONE * 2.0)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			drag = Drag.NONE
			return
		var found = _spot_at(point)
		drag = found[1]
		if found[0] < 0:
			return
		_choose(found[0])
		drag_start_point = point
		drag_start = spots[chosen].controls.map(func(control): return [control.global_position, control.reach])
	elif event is InputEventMouseMotion and drag == Drag.NONE:
		var under = _spot_at(point)[0]
		if under != hovered:
			hovered = under
			queue_redraw()
	elif event is InputEventMouseMotion:
		var offset = point - drag_start_point
		var controls = spots[chosen].controls
		for i in len(controls):
			if drag == Drag.MOVE:
				controls[i].global_position = drag_start[i][0] + offset
			else:
				# areas grow by how far the corner moved, compared to the biggest area
				var corner = _corner_from(drag_start)
				var factor = ((corner + offset) / corner.max(Vector2.ONE)).clamp(Vector2.ONE * 0.2, Vector2.ONE * 5.0)
				controls[i].reach = (drag_start[i][1] * factor).max(Vector2.ONE * 2.0)
		queue_redraw()
	elif event is InputEventKey and event.pressed:
		var nudge = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}
		if event.keycode in nudge and drag == Drag.NONE and chosen < len(spots):
			for control in spots[chosen].controls:
				control.global_position += nudge[event.keycode] * (10.0 if event.shift_pressed else 1.0)
			queue_redraw()
		elif event.echo:
			return
		elif event.keycode == KEY_TAB and not spots.is_empty():
			_choose(wrapi(chosen + (-1 if event.shift_pressed else 1), 0, len(spots)))
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_finish(true)
		elif event.keycode == KEY_ESCAPE:
			_finish(false)

# The biggest reach among [position, reach] pairs
static func _corner_from(pairs:Array) -> Vector2:
	var biggest = Vector2.ZERO
	for pair in pairs:
		biggest = biggest.max(pair[1])
	return biggest

func _draw() -> void:
	if not fitting or chosen >= len(spots):
		return
	# the hovered spot's areas, faintly, so the mouse can show what a dot is
	if hovered >= 0 and hovered != chosen:
		for control in spots[hovered].controls:
			control.draw_shape(self, control.global_position, Color(_color(spots[hovered]), 0.35))
	var spot = spots[chosen]
	var color = _color(spot)
	for control in spot.controls:
		control.draw_shape(self, control.global_position, Color(color, 0.9))
	# the other spots are dots
	for i in len(spots):
		if i != chosen:
			draw_circle(_middle(spots[i]), DOT_RADIUS, Color.WHITE)
			draw_circle(_middle(spots[i]), DOT_RADIUS, Color(_color(spots[i]), 1.0 if i == hovered else 0.6), false, 1.5, true)
	# the chosen spot's circle and square on top
	var middle = _middle(spot)
	draw_circle(middle, HANDLE_RADIUS, Color.WHITE)
	draw_circle(middle, HANDLE_RADIUS, color, false, 2.0, true)
	draw_circle(middle, 2.5, color)
	var corner = _corner(spot)
	draw_rect(Rect2(corner - Vector2.ONE * CORNER_SIZE / 2, Vector2.ONE * CORNER_SIZE), Color.WHITE)
	draw_rect(Rect2(corner - Vector2.ONE * CORNER_SIZE / 2, Vector2.ONE * CORNER_SIZE), color, false, 1.5)
	var taken = [_draw_label(chosen, [])]
	if hovered >= 0 and hovered != chosen:
		_draw_label(hovered, taken)

static func _color(spot:Dictionary) -> Color:
	return SWING_COLOR if spot.controls.any(func(control): return control.swing > 0.0) else COLOR

# Names a spot beside its point: on the right, or else left, above or below it,
# wherever it doesn't cover the boxes in taken. Returns the box it took.
func _draw_label(index:int, taken:Array) -> Rect2:
	var font = ThemeDB.fallback_font
	var label = spots[index].label
	var size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var middle = _middle(spots[index])
	var gap = HANDLE_RADIUS + 3
	var places = [middle + Vector2(gap, -size.y / 2), middle + Vector2(-gap - size.x, -size.y / 2),
		middle + Vector2(-size.x / 2, -gap - size.y), middle + Vector2(-size.x / 2, gap)]
	var box = Rect2(places[0], size)
	for place in places:
		var tried = Rect2(place, size)
		if not taken.any(func(other): return other.intersects(tried.grow(1))):
			box = tried
			break
	var baseline = box.position + Vector2(0, font.get_ascent(LABEL_SIZE))
	draw_string_outline(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 3, Color.WHITE)
	draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, _color(spots[index]).darkened(0.3))
	return box

# The panel with a hint and buttons, where the menu usually is, so the whole doll can be
# reached (the doll goes up to the top of the screen). The sculpt brush (body_sculptor.gd)
# uses it too; its buttons are in the panel's "row" meta.
static func make_bar(layer:CanvasLayer, text:String, choices:Array) -> Control:
	var holder = MarginContainer.new()
	holder.theme = preload("res://theme.tres")
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	holder.add_theme_constant_override("margin_top", 80)
	holder.add_theme_constant_override("margin_right", 50)
	layer.add_child(holder)
	var panel = PanelContainer.new()
	panel.theme_type_variation = &"Toast"
	holder.add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var hint = Label.new()
	hint.theme_type_variation = &"ToastLabel"
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(240, 0)
	column.add_child(hint)
	var row = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	column.add_child(row)
	for choice in choices:
		var button = Button.new()
		button.theme_type_variation = &"ToolButton"
		button.text = choice[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(choice[1])
		row.add_child(button)
	holder.set_meta("row", row)
	holder.hide()
	return holder
