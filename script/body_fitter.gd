# Lets the player move the Body menu's controls to fit their doll, for bodies that aren't
# shaped like the one the controls were placed on (such as a body made with AI or uploaded).
#   - the doll is shown as drawn, with a handle on each control; controls in the same
#     spot (such as everything on one eye) share a handle and move together
#   - drag a handle onto the matching part of the doll
#   - drag the small square at its corner to make its area bigger or smaller
#   - Done keeps the fit for the body picture worn now (each body has its own, see
#     body_shaper.gd), Reset puts the controls back where the game placed them,
#     and Cancel (or Escape) forgets the changes
# The Fit points button in the Body menu starts it.

extends Node2D

@export var body_shaper: Node2D
# Hidden while fitting, so the outfit can't change meanwhile
@export var ui_root: Control
@export var sticker_stage: Node2D

const HANDLE_RADIUS := 8.0
const CORNER_SIZE := 6.0
const COLOR := Color(0.2, 0.33, 0.85)
const SWING_COLOR := Color(0.2, 0.6, 0.4)
const LABEL_SIZE := 11

enum Drag { NONE, MOVE, RESIZE }

var fitting := false
var spots := [] # [{"controls": [...], "label": "Eye size, Eye spacing"}], one per handle
var before := [] # [position, reach] of every control when fitting started, for Cancel
var chosen := -1 # the spot being dragged, or touched last
var hovered := -1 # the spot under the mouse
var drag := Drag.NONE
var drag_start_point := Vector2.ZERO
var drag_start := [] # [position, reach] of each control in the chosen spot when the drag started
var bar: Control

func _ready() -> void:
	z_index = 101 # above the doll and the stickers
	var layer = CanvasLayer.new()
	add_child(layer)
	bar = _make_bar(layer, "Drag the circles onto the matching parts of your doll. The squares resize.",
		[["Reset", _reset], ["Cancel", func(): _finish(false)], ["Done", func(): _finish(true)]])

func start() -> void:
	if fitting:
		return
	fitting = true
	body_shaper.hold_neutral(true)
	ui_root.hide()
	sticker_stage.deselect()
	sticker_stage.hide()
	bar.show()
	before = body_shaper.controls().map(func(control): return [control.global_position, control.reach])
	# controls in the same spot share a handle
	var by_spot := {}
	spots = []
	for control in body_shaper.controls():
		var key = Vector2i(control.global_position.round())
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
	chosen = -1
	hovered = -1
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

# Puts every control back where the game placed it
func _reset() -> void:
	for control in body_shaper.controls():
		var placed = body_shaper.default_of(control)
		control.global_position = placed[0]
		control.reach = placed[1]
	queue_redraw()

# The middle of a spot, where its handle is
static func _middle(spot:Dictionary) -> Vector2:
	return spot.controls[0].global_position

# The spot's resize square: at the corner of its biggest area
static func _corner(spot:Dictionary) -> Vector2:
	var biggest = Vector2.ZERO
	for control in spot.controls:
		biggest = biggest.max(control.reach)
	return _middle(spot) + biggest

# The spot under the point, and whether it was its resize square: [index, Drag], or [-1, NONE]
func _spot_at(point:Vector2) -> Array:
	var best = [-1, Drag.NONE]
	var nearest = INF
	for i in len(spots):
		for target in [[_corner(spots[i]), Drag.RESIZE, CORNER_SIZE], [_middle(spots[i]), Drag.MOVE, HANDLE_RADIUS]]:
			var distance = point.distance_to(target[0])
			if distance <= target[2] + 4 and distance < nearest:
				nearest = distance
				best = [i, target[1]]
	return best

func _unhandled_input(event:InputEvent) -> void:
	if not fitting:
		return
	# nothing else (stickers, undo...) reacts while fitting
	get_viewport().set_input_as_handled()
	var point = get_canvas_transform().affine_inverse() * event.position if event is InputEventMouse else Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			drag = Drag.NONE
			return
		var found = _spot_at(point)
		chosen = found[0]
		drag = found[1]
		drag_start_point = point
		if chosen >= 0:
			drag_start = spots[chosen].controls.map(func(control): return [control.global_position, control.reach])
		queue_redraw()
	elif event is InputEventMouseMotion and drag == Drag.NONE:
		var under = _spot_at(point)[0]
		if under != hovered:
			hovered = under
			queue_redraw()
	elif event is InputEventMouseMotion and drag != Drag.NONE:
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
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
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
	if not fitting:
		return
	var lit = [chosen] if hovered == chosen else [chosen, hovered]
	for i in len(spots):
		var faded = Color(_color(spots[i]), 0.9 if i in lit else 0.3)
		for control in spots[i].controls:
			control.draw_shape(self, control.global_position, faded)
	# handles on top of all the shapes, the chosen and hovered ones last
	var order = range(len(spots)).filter(func(i): return not i in lit)
	order += lit.filter(func(i): return i >= 0)
	for i in order:
		var spot = spots[i]
		var color = _color(spot)
		var middle = _middle(spot)
		draw_circle(middle, HANDLE_RADIUS, Color.WHITE)
		draw_circle(middle, HANDLE_RADIUS, color, false, 2.0, true)
		draw_circle(middle, 2.5, color)
		var corner = _corner(spot)
		draw_rect(Rect2(corner - Vector2.ONE * CORNER_SIZE / 2, Vector2.ONE * CORNER_SIZE), Color.WHITE)
		draw_rect(Rect2(corner - Vector2.ONE * CORNER_SIZE / 2, Vector2.ONE * CORNER_SIZE), color, false, 1.5)
	_draw_labels(lit)

static func _color(spot:Dictionary) -> Color:
	return SWING_COLOR if spot.controls.any(func(control): return control.swing > 0.0) else COLOR

# Names the handles, beside them where there is room. The chosen and hovered
# handles are always named; a name that would cover another is left out.
func _draw_labels(lit:Array) -> void:
	var font = ThemeDB.fallback_font
	var taken := []
	var order = lit.filter(func(i): return i >= 0) + range(len(spots)).filter(func(i): return not i in lit)
	for i in order:
		var size = font.get_string_size(spots[i].label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var middle = _middle(spots[i])
		var gap = HANDLE_RADIUS + 3
		# right, left, above and below the handle
		var places = [middle + Vector2(gap, -size.y / 2), middle + Vector2(-gap - size.x, -size.y / 2),
			middle + Vector2(-size.x / 2, -gap - size.y), middle + Vector2(-size.x / 2, gap)]
		var box = null
		for place in places:
			var tried = Rect2(place, size)
			if not taken.any(func(other): return other.intersects(tried.grow(1))):
				box = tried
				break
		if box == null:
			if not i in lit:
				continue
			box = Rect2(places[0], size)
		taken.append(box)
		var baseline = box.position + Vector2(0, font.get_ascent(LABEL_SIZE))
		draw_string_outline(font, baseline, spots[i].label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 3, Color.WHITE)
		draw_string(font, baseline, spots[i].label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, _color(spots[i]).darkened(0.3))

# The strip at the top of the screen with a hint and buttons (like picture_upload.gd's)
func _make_bar(layer:CanvasLayer, text:String, choices:Array) -> Control:
	var holder = MarginContainer.new()
	holder.theme = preload("res://theme.tres")
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.add_theme_constant_override("margin_top", 12)
	layer.add_child(holder)
	var panel = PanelContainer.new()
	panel.theme_type_variation = &"Toast"
	holder.add_child(panel)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var hint = Label.new()
	hint.theme_type_variation = &"ToastLabel"
	hint.text = text
	row.add_child(hint)
	for choice in choices:
		var button = Button.new()
		button.theme_type_variation = &"ToolButton"
		button.text = choice[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(choice[1])
		row.add_child(button)
	holder.hide()
	return holder
