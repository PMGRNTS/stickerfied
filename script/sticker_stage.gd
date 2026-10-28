# Shows the stickers placed on the doll and lets the player arrange them:
#   - click a sticker to select it (it comes to the front), drag to move it
#   - drag a box over empty space to select several stickers, Shift + click adds or
#     removes one, Ctrl/Cmd + A selects them all. Selected stickers change together.
#   - drag the round handle at the corner to resize and turn the selection
#   - drag the square handles on the right and bottom edges to make one sticker
#     wider or taller without keeping its shape (the opposite edge stays put)
#   - the red handle (or the Delete key) takes it off
#   - the green handle (or the D key) makes a copy, the bottom-left handle (or F) mirrors it
#   - the eraser handle at the top (or the E key) rubs out parts of one sticker (see picture_upload.gd)
#   - mouse wheel resizes the selection, Shift + wheel turns it
# Changes are sent to interactivity.gd when the player lets go, so they can be undone.
# Stickers follow the doll's shape (the Body menu): outfits keep where each sticker is on
# the doll as drawn, and its picture is bent along with that part of the doll, breathing too
# (see sticker_mesh.gd). Its frame and handles move, turn and grow with it, but stay straight.

extends Node2D

const StickerMesh = preload("res://script/sticker_mesh.gd")

# The player wants to erase parts of the sticker at this index
signal erase_requested(index:int)

@export var interactivity: Node
# New stickers appear near this node (the SpritePlaceholder marks the middle of the doll)
@export var spawn_point: Node2D
# Reshapes the doll (see body_shaper.gd); the stickers move with it
@export var body_shaper: Node2D

const HANDLE_RADIUS := 11.0
const FRAME_COLOR := Color(0.2, 0.33, 0.85)
const DELETE_COLOR := Color(0.86, 0.25, 0.4)
const COPY_COLOR := Color(0.2, 0.68, 0.45)
const ERASER_COLOR := Color(0.95, 0.55, 0.65)
# How far a copy is placed from the sticker it was copied from
const COPY_OFFSET := Vector2(24, 24)
# Space between a group of stickers and the frame around them
const GROUP_PADDING := 6.0
# A selection box smaller than this (in pixels) counts as a click
const MIN_BOX_SIZE := 4.0
# A sticker's picture is bent on a grid with squares about this many pixels across,
# and at most this many squares each way
const MESH_SPACING := 16.0
const MAX_MESH_SQUARES := 16

enum Drag { NONE, MOVE, TRANSFORM, STRETCH, BOX }

var drawn := [] # the sticker data from the outfit: where they are on the doll as drawn
var stickers := [] # the same stickers where they are shown, on the reshaped doll
var sprites := [] # one Sprite2D per sticker, not drawn: its child StickerMesh shows the picture
var selection := [] # indexes of the selected stickers, lowest first
var drag := Drag.NONE
var drag_start_point := Vector2.ZERO
var box_end := Vector2.ZERO # the selection box's other corner
var drag_start := [] # the selected stickers when the drag started, see _capture()
var drag_start_frame := {}
var drag_pivot := Vector2.ZERO
var drag_factor := 1.0
var drag_angle := 0.0
var drag_axis := 0 # the edge being stretched: 0 makes the sticker wider, 1 taller
var changed_while_dragging := false
var breathed := 0.0 # how far the stickers are shown breathed in

@onready var handles: Node2D = Node2D.new()
@onready var commit_timer: Timer = Timer.new()

func _ready() -> void:
	# Handles are drawn by a separate node added last, so they show on top of the stickers
	add_child(handles)
	handles.draw.connect(_draw_handles)
	commit_timer.one_shot = true
	commit_timer.wait_time = 0.4
	commit_timer.timeout.connect(_commit)
	add_child(commit_timer)
	if body_shaper:
		body_shaper.shape_changed.connect(_follow_shape)


#####################################
############## SHOWING ##############
#####################################

# Called by interactivity.gd whenever the outfit changes
func show_stickers(new_stickers:Array) -> void:
	drawn = new_stickers.duplicate(true)
	stickers = drawn.map(_shown)
	while len(sprites) < len(stickers):
		var sprite = Sprite2D.new()
		sprite.self_modulate = Color.TRANSPARENT
		var mesh = StickerMesh.new()
		sprite.add_child(mesh)
		# the eraser shows its work on the sprite's texture (see picture_upload.gd)
		sprite.texture_changed.connect(func(): mesh.texture = sprite.texture)
		add_child(sprite)
		sprites.append(sprite)
	while len(sprites) > len(stickers):
		sprites.pop_back().queue_free()
	for i in len(stickers):
		var button = interactivity.sticker_tab.get_item_button(stickers[i].id)
		sprites[i].texture = button.image if button else null
		_place_sprite(i)
	move_child(handles, -1)
	selection = selection.filter(func(i): return i < len(stickers))
	handles.queue_redraw()

func _place_sprite(i:int) -> void:
	sprites[i].position = Vector2(stickers[i].x, stickers[i].y)
	sprites[i].scale = Vector2(stickers[i].get("stretch", 1.0), 1.0) * stickers[i].scale
	sprites[i].rotation = stickers[i].rot
	sprites[i].flip_h = stickers[i].get("flip", false)
	_bend(i)

# Lays a grid over sticker i's picture and bends it along with the doll:
# the sticker is placed on the doll as drawn, and each grid point goes where the doll's
# shape moves that spot. The points are kept in the sprite's own coordinates.
func _bend(i:int) -> void:
	var sprite: Sprite2D = sprites[i]
	var mesh = sprite.get_child(0)
	if sprite.texture == null:
		return
	var size = sprite.texture.get_size()
	var squares = Vector2i((size * sprite.scale.abs() / MESH_SPACING).ceil()).clamp(
		Vector2i.ONE, Vector2i.ONE * MAX_MESH_SQUARES)
	var flat := PackedVector2Array() # the grid on the sticker, not bent
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var triangles := PackedInt32Array()
	for row in squares.y + 1:
		for column in squares.x + 1:
			var uv = Vector2(column, row) / Vector2(squares)
			flat.append((uv - Vector2(0.5, 0.5)) * size)
			uvs.append(Vector2(1.0 - uv.x, uv.y) if sprite.flip_h else uv)
			colors.append(Color.WHITE)
			if row < squares.y and column < squares.x:
				var corner = row * (squares.x + 1) + column
				var below = corner + squares.x + 1
				triangles.append_array([corner, corner + 1, below + 1, corner, below + 1, below])
	mesh.uvs = uvs
	mesh.colors = colors
	mesh.triangles = triangles
	mesh.still = flat
	mesh.inhaled = PackedVector2Array()
	if body_shaper:
		var on_doll = _drawn(stickers[i])
		var placed = Transform2D(on_doll.rot, Vector2(on_doll.get("stretch", 1.0), 1.0) * on_doll.scale,
			0.0, Vector2(on_doll.x, on_doll.y)) * flat
		var back = sprite.transform.affine_inverse()
		mesh.still = back * body_shaper.bent(placed)
		if body_shaper.can_breathe:
			var inhaled = back * body_shaper.bent(placed, 1.0)
			if inhaled != mesh.still:
				mesh.inhaled = inhaled
	mesh.set_points(mesh.still)
	mesh.breathe(breathed)

# Stickers on the part of the doll that breathes breathe with it.
# The handles are drawn in screen pixels, so they stay the same size when zoomed in (see stage_zoom.gd).
func _process(_delta:float) -> void:
	var to_screen = get_canvas_transform()
	if handles.transform != to_screen.affine_inverse():
		handles.transform = to_screen.affine_inverse()
		handles.queue_redraw()
	if body_shaper == null or body_shaper.breath == breathed or not visible:
		return
	breathed = body_shaper.breath
	for sprite in sprites:
		sprite.get_child(0).breathe(breathed)

# Where a new sticker goes, on the doll as drawn (where outfits keep stickers)
func new_sticker_position() -> Vector2:
	var center = spawn_point.position if spawn_point else get_viewport_rect().size / 2
	var spot = center + Vector2(randf_range(-50, 50), randf_range(-140, 0))
	# when zoomed in, somewhere that can be seen
	var seen = (get_canvas_transform().affine_inverse() * get_viewport_rect()).grow(-40)
	spot = spot.clamp(seen.position, seen.end)
	return body_shaper.unshaped(spot) if body_shaper else spot

# The doll changed shape: the stickers move with it
func _follow_shape() -> void:
	stickers = drawn.map(_shown)
	for i in len(stickers):
		_place_sprite(i)
	handles.queue_redraw()

# A sticker from the outfit, where it shows on the reshaped doll.
# It remembers the sticker it was made from, see _drawn().
func _shown(sticker:Dictionary) -> Dictionary:
	var shown = sticker.duplicate()
	shown.from = sticker
	if body_shaper == null:
		return shown
	var pose = body_shaper.pose_at(Vector2(sticker.x, sticker.y))
	shown.x = pose.position.x
	shown.y = pose.position.y
	shown.scale = sticker.scale * pose.scale
	shown.rot = wrapf(sticker.rot + pose.angle, -PI, PI)
	return shown

# A sticker as shown, back where it is on the doll as drawn, to keep in the outfit.
# Stickers the player didn't change keep their old place exactly.
func _drawn(sticker:Dictionary) -> Dictionary:
	if sticker.has("from") and _same_place(sticker, _shown(sticker.from)):
		return sticker.from.duplicate()
	var result = {"id": sticker.id, "x": sticker.x, "y": sticker.y, "scale": sticker.scale,
		"stretch": sticker.get("stretch", 1.0), "rot": sticker.rot, "flip": sticker.get("flip", false)}
	if body_shaper == null:
		return result
	var spot = body_shaper.unshaped(Vector2(sticker.x, sticker.y))
	var pose = body_shaper.pose_at(spot)
	result.x = spot.x
	result.y = spot.y
	result.scale = sticker.scale / maxf(pose.scale, 0.01)
	result.rot = wrapf(sticker.rot - pose.angle, -PI, PI)
	return result

static func _same_place(a:Dictionary, b:Dictionary) -> bool:
	return is_equal_approx(a.x, b.x) and is_equal_approx(a.y, b.y) and is_equal_approx(a.scale, b.scale) \
		and is_equal_approx(a.get("stretch", 1.0), b.get("stretch", 1.0)) \
		and is_equal_approx(a.rot, b.rot) and a.get("flip", false) == b.get("flip", false)

# Selects one sticker, or nothing when index is -1
func select(index:int) -> void:
	set_selection([index] if index >= 0 else [])

func set_selection(indexes:Array) -> void:
	selection = indexes.filter(func(i): return i >= 0 and i < len(stickers))
	selection.sort()
	handles.queue_redraw()

func deselect() -> void:
	set_selection([])

func select_all() -> void:
	set_selection(range(len(stickers)))


#####################################
############## INPUT ################
#####################################

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		var point = _to_stage(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_press(point, event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and drag != Drag.NONE:
			_on_release(point, event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif event.pressed and not selection.is_empty() and _is_on_selection(point):
			var step = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0
			if step != 0:
				var center = _frame().center
				if event.shift_pressed:
					_transform_selection(_capture(), center, 1.0, step * deg_to_rad(15))
				else:
					_transform_selection(_capture(), center, pow(1.1, step), 0.0)
				commit_timer.start()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and drag != Drag.NONE:
		_on_drag(_to_stage(event.position))
		get_viewport().set_input_as_handled()

	# pinch on a trackpad
	elif event is InputEventMagnifyGesture and not selection.is_empty():
		_transform_selection(_capture(), _frame().center, event.factor, 0.0)
		commit_timer.start()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_A and event.is_command_or_control_pressed() and not stickers.is_empty():
			select_all()
		elif selection.is_empty():
			return
		elif event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
			_remove_selection()
		elif event.keycode == KEY_D and not event.is_command_or_control_pressed():
			_duplicate_selection()
		elif event.keycode == KEY_F and not event.is_command_or_control_pressed():
			_flip_selection()
		elif event.keycode == KEY_E and not event.is_command_or_control_pressed() and len(selection) == 1:
			erase_requested.emit(selection[0])
		elif event.keycode == KEY_ESCAPE:
			deselect()
		else:
			return
		get_viewport().set_input_as_handled()

# Mouse positions are in window pixels; the stage may be scaled to fit the window
func _to_stage(window_position:Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * window_position

func _on_press(point:Vector2, shift:bool) -> void:
	if not selection.is_empty() and not shift:
		var corners = _frame_corners()
		if point.distance_to(corners[1]) <= _grab_distance():
			_remove_selection()
			get_viewport().set_input_as_handled()
			return
		if point.distance_to(corners[0]) <= _grab_distance():
			_duplicate_selection()
			get_viewport().set_input_as_handled()
			return
		if point.distance_to(corners[3]) <= _grab_distance():
			_flip_selection()
			get_viewport().set_input_as_handled()
			return
		if len(selection) == 1 and point.distance_to(_eraser_handle(corners)) <= _grab_distance():
			erase_requested.emit(selection[0])
			get_viewport().set_input_as_handled()
			return
		if point.distance_to(corners[2]) <= _grab_distance():
			drag_start_frame = _frame()
			drag_pivot = drag_start_frame.center
			drag_start_point = point
			drag_start = _capture()
			drag_factor = 1.0
			drag_angle = 0.0
			drag = Drag.TRANSFORM
			changed_while_dragging = false
			get_viewport().set_input_as_handled()
			return
		for axis in 2:
			if len(selection) == 1 and point.distance_to(_stretch_handle(corners, axis)) <= _grab_distance():
				drag_axis = axis
				drag_start_point = point
				drag_start = _capture()
				drag = Drag.STRETCH
				changed_while_dragging = false
				get_viewport().set_input_as_handled()
				return

	var index = _sticker_at(point)
	if shift and index >= 0:
		# Shift + click adds the sticker to the selection, or takes it out
		if index in selection:
			set_selection(selection.filter(func(i): return i != index))
		else:
			set_selection(selection + [index])
		get_viewport().set_input_as_handled()
		return

	changed_while_dragging = false
	if index >= 0 and (not index in selection or len(selection) == 1):
		# a single sticker: it comes to the front
		if index != len(stickers) - 1:
			index = _bring_to_front(index)
			changed_while_dragging = true
		select(index)
	elif index < 0 and not (len(selection) > 1 and _frame_has_point(point)):
		# empty space: start a selection box
		if not shift:
			deselect()
		drag = Drag.BOX
		drag_start_point = point
		box_end = point
		get_viewport().set_input_as_handled()
		return
	# dragging any selected sticker (or the space between them) moves them all
	drag = Drag.MOVE
	drag_start_point = point
	drag_start = _capture()
	get_viewport().set_input_as_handled()

func _on_drag(point:Vector2) -> void:
	if drag == Drag.BOX:
		box_end = point
	elif drag == Drag.MOVE:
		changed_while_dragging = true
		_move_selection(drag_start, point - drag_start_point)
	elif drag == Drag.TRANSFORM:
		changed_while_dragging = true
		var start_vector = drag_start_point - drag_pivot
		var vector = point - drag_pivot
		var factor = vector.length() / start_vector.length() if start_vector.length() > 1 else 1.0
		drag_angle = start_vector.angle_to(vector)
		drag_factor = _transform_selection(drag_start, drag_pivot, factor, drag_angle)
	elif drag == Drag.STRETCH:
		changed_while_dragging = true
		_stretch_sticker(drag_start[0], drag_axis, point - drag_start_point)
	handles.queue_redraw()

func _on_release(point:Vector2, shift:bool) -> void:
	var was = drag
	drag = Drag.NONE
	if was == Drag.BOX:
		var box = _box(drag_start_point, point)
		if box.size.length() >= MIN_BOX_SIZE:
			var inside = _stickers_in_box(box)
			set_selection(selection + inside.filter(func(i): return not i in selection) if shift else inside)
		handles.queue_redraw()
	elif changed_while_dragging:
		_commit()
	else:
		handles.queue_redraw()


#####################################
############## CHANGES ##############
#####################################

# The selected stickers' positions, sizes and turns, to change them from
func _capture() -> Array:
	return selection.map(func(i): return {"i": i, "pos": Vector2(stickers[i].x, stickers[i].y),
		"scale": stickers[i].scale, "stretch": stickers[i].get("stretch", 1.0), "rot": stickers[i].rot})

# Moves the selection, but not past the edge of the screen
func _move_selection(start:Array, offset:Vector2) -> void:
	var area = get_viewport_rect()
	for sticker in start:
		offset = offset.clamp(area.position - sticker.pos, area.end - sticker.pos)
	for sticker in start:
		stickers[sticker.i].x = sticker.pos.x + offset.x
		stickers[sticker.i].y = sticker.pos.y + offset.y
		_place_sprite(sticker.i)
	handles.queue_redraw()

# Resizes and turns the selection around pivot. The size change is limited so that
# no sticker gets too small or too big, which would bend the group out of shape.
# Returns the size change that was used.
func _transform_selection(start:Array, pivot:Vector2, factor:float, angle:float) -> float:
	var limits: Vector2 = interactivity.STICKER_SCALE_LIMITS
	var smallest := 0.0
	var largest := INF
	for sticker in start:
		smallest = maxf(smallest, limits.x / sticker.scale)
		largest = minf(largest, limits.y / sticker.scale)
	factor = clampf(factor, smallest, largest) if smallest <= largest else 1.0
	for sticker in start:
		var pos = pivot + (sticker.pos - pivot).rotated(angle) * factor
		stickers[sticker.i].x = pos.x
		stickers[sticker.i].y = pos.y
		stickers[sticker.i].scale = sticker.scale * factor
		stickers[sticker.i].rot = wrapf(sticker.rot + angle, -PI, PI)
		_place_sprite(sticker.i)
	handles.queue_redraw()
	return factor

# Makes one sticker wider (axis 0) or taller (axis 1) by how far its edge was pulled,
# keeping the opposite edge where it is. "scale" stays the sticker's height and
# "stretch" how much wider it is than its picture's shape.
func _stretch_sticker(start:Dictionary, axis:int, pulled:Vector2) -> void:
	var picture = sprites[start.i].texture.get_size() if sprites[start.i].texture else Vector2.ONE
	var size = picture * Vector2(start.stretch, 1.0) * start.scale
	var direction = (Vector2.RIGHT if axis == 0 else Vector2.DOWN).rotated(start.rot)
	var length = size[axis] + pulled.dot(direction)
	var limits: Vector2 = interactivity.STICKER_SCALE_LIMITS
	var stretch_limits: Vector2 = interactivity.STICKER_STRETCH_LIMITS
	var scale = start.scale
	if axis == 1:
		# the width stays as it was, so the height stops where the stretch would go too far
		var lowest = maxf(limits.x, size.x / (picture.x * stretch_limits.y))
		var highest = minf(limits.y, size.x / (picture.x * stretch_limits.x))
		scale = clampf(length / picture.y, lowest, highest)
		length = size.x
	var stretch = clampf(length / (picture.x * scale), stretch_limits.x, stretch_limits.y)
	var new_size = picture * Vector2(stretch, 1.0) * scale
	var pos = start.pos + direction * (new_size[axis] - size[axis]) / 2
	var sticker = stickers[start.i]
	sticker.x = pos.x
	sticker.y = pos.y
	sticker.scale = scale
	sticker.stretch = stretch
	_place_sprite(start.i)

func _bring_to_front(index:int) -> int:
	stickers.append(stickers.pop_at(index))
	var sprite = sprites.pop_at(index)
	sprites.append(sprite)
	move_child(sprite, -1)
	move_child(handles, -1)
	return len(stickers) - 1

func _remove_selection() -> void:
	for i in range(len(selection) - 1, -1, -1):
		stickers.remove_at(selection[i])
	selection = []
	drag = Drag.NONE
	_commit()
	Sfx.play("click")

# Copies the selected stickers (as many as fit) and selects the copies
func _duplicate_selection() -> void:
	var room = interactivity.MAX_STICKERS - len(stickers)
	if room <= 0:
		return
	var copies = selection.slice(0, room).map(func(i): return stickers[i].duplicate())
	var offset = COPY_OFFSET
	var area = get_viewport_rect()
	for copy in copies:
		offset = offset.clamp(area.position - Vector2(copy.x, copy.y), area.end - Vector2(copy.x, copy.y))
	for copy in copies:
		copy.x += offset.x
		copy.y += offset.y
	var first = len(stickers)
	stickers.append_array(copies)
	selection = range(first, len(stickers))
	_commit()
	Sfx.play("pop")

# Mirrors the selection left to right, as one piece
func _flip_selection() -> void:
	var middle = _frame().center.x
	for i in selection:
		stickers[i].x = 2 * middle - stickers[i].x
		stickers[i].rot = wrapf(-stickers[i].rot, -PI, PI)
		stickers[i].flip = not stickers[i].get("flip", false)
		_place_sprite(i)
	_commit()
	Sfx.play("click")

func _commit() -> void:
	commit_timer.stop()
	var keep_selected = selection.duplicate()
	interactivity.set_stickers(stickers.map(_drawn))
	set_selection(keep_selected)


#####################################
############## HIT TESTS ############
#####################################

# The top-most sticker under the point, or -1
func _sticker_at(point:Vector2) -> int:
	for i in range(len(sprites) - 1, -1, -1):
		var sprite: Sprite2D = sprites[i]
		if sprite.texture == null:
			continue
		var local = sprite.transform.affine_inverse() * point
		if sprite.get_rect().has_point(local) and (i in selection or sprite.is_pixel_opaque(local)):
			return i
	return -1

# How close (on the stage) the pointer must be to a handle to grab it
func _grab_distance() -> float:
	return (HANDLE_RADIUS + 3) / get_canvas_transform().get_scale().x

# The middle of the selection's frame, which the zoom buttons zoom around
func selection_middle() -> Vector2:
	return _frame().center

func is_on_selection(point:Vector2) -> bool:
	return _is_on_selection(point)

func _is_on_selection(point:Vector2) -> bool:
	return _sticker_at(point) in selection or (len(selection) > 1 and _frame_has_point(point))

# Stickers whose middle is inside the box
func _stickers_in_box(box:Rect2) -> Array:
	return range(len(stickers)).filter(func(i): return box.has_point(sprites[i].position))

static func _box(a:Vector2, b:Vector2) -> Rect2:
	return Rect2(a, Vector2.ZERO).expand(b)

# A sticker's corners on screen: top-left, top-right, bottom-right, bottom-left
func _corners(i:int) -> Array:
	var half = sprites[i].texture.get_size() / 2 if sprites[i].texture else Vector2.ZERO
	var t = sprites[i].transform
	return [t * Vector2(-half.x, -half.y), t * Vector2(half.x, -half.y),
		t * Vector2(half.x, half.y), t * Vector2(-half.x, half.y)]

# The frame around the selection: {"center", "half" (half its size), "angle"}.
# One sticker gets a frame that turns with it; a group gets a straight frame
# around all of them, which turns while the group is being turned.
func _frame() -> Dictionary:
	if drag == Drag.TRANSFORM:
		return {"center": drag_pivot, "half": drag_start_frame.half * drag_factor,
			"angle": drag_start_frame.angle + drag_angle}
	if len(selection) == 1:
		var i = selection[0]
		var size = sprites[i].texture.get_size() if sprites[i].texture else Vector2.ZERO
		return {"center": sprites[i].position, "half": size / 2 * sprites[i].scale, "angle": stickers[i].rot}
	var box = Rect2(sprites[selection[0]].position, Vector2.ZERO)
	for i in selection:
		for corner in _corners(i):
			box = box.expand(corner)
	box = box.grow(GROUP_PADDING)
	return {"center": box.get_center(), "half": box.size / 2, "angle": 0.0}

# top-left, top-right, bottom-right, bottom-left
func _frame_corners() -> Array:
	var frame = _frame()
	return [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)].map(
		func(corner): return frame.center + (corner * frame.half).rotated(frame.angle))

# The eraser handle sits in the middle of the frame's top edge (one sticker only)
static func _eraser_handle(corners:Array) -> Vector2:
	return (corners[0] + corners[1]) / 2

# The stretch handles sit in the middle of the right edge (axis 0, wider)
# and the bottom edge (axis 1, taller), one sticker only
static func _stretch_handle(corners:Array, axis:int) -> Vector2:
	return (corners[1] + corners[2]) / 2 if axis == 0 else (corners[2] + corners[3]) / 2

func _frame_has_point(point:Vector2) -> bool:
	var frame = _frame()
	var local = (point - frame.center).rotated(-frame.angle)
	return absf(local.x) <= frame.half.x and absf(local.y) <= frame.half.y


#####################################
############## HANDLES ##############
#####################################

# Draws in screen pixels: points on the stage go through to_screen first
func _draw_handles() -> void:
	var to_screen = get_canvas_transform()
	var on_screen = func(points:Array): return points.map(func(p): return to_screen * p)
	if drag == Drag.BOX:
		var box = _box(drag_start_point, box_end)
		handles.draw_rect(to_screen * box, Color(FRAME_COLOR, 0.12))
		handles.draw_rect(to_screen * box, FRAME_COLOR, false, 1.5)
		# outline the stickers that will be selected
		for i in _stickers_in_box(box):
			_draw_outline(on_screen.call(_corners(i)), Color(FRAME_COLOR, 0.6), 1.5)
		return
	if selection.is_empty():
		return
	if len(selection) > 1:
		for i in selection:
			_draw_outline(on_screen.call(_corners(i)), Color(FRAME_COLOR, 0.45), 1.0)
	var corners = on_screen.call(_frame_corners())
	_draw_outline(corners, FRAME_COLOR, 2.0)
	# resize & turn handle: a ring with an arrow
	handles.draw_circle(corners[2], HANDLE_RADIUS, Color.WHITE)
	handles.draw_circle(corners[2], HANDLE_RADIUS, FRAME_COLOR, false, 2.0, true)
	handles.draw_arc(corners[2], HANDLE_RADIUS * 0.5, -PI * 0.25, PI * 1.25, 12, FRAME_COLOR, 2.0, true)
	# remove handle: a red circle with an x
	handles.draw_circle(corners[1], HANDLE_RADIUS, DELETE_COLOR)
	var arm = HANDLE_RADIUS * 0.4
	handles.draw_line(corners[1] + Vector2(-arm, -arm), corners[1] + Vector2(arm, arm), Color.WHITE, 2.0, true)
	handles.draw_line(corners[1] + Vector2(-arm, arm), corners[1] + Vector2(arm, -arm), Color.WHITE, 2.0, true)
	# copy handle: a green circle with a +
	handles.draw_circle(corners[0], HANDLE_RADIUS, COPY_COLOR)
	handles.draw_line(corners[0] + Vector2(-arm * 1.3, 0), corners[0] + Vector2(arm * 1.3, 0), Color.WHITE, 2.0, true)
	handles.draw_line(corners[0] + Vector2(0, -arm * 1.3), corners[0] + Vector2(0, arm * 1.3), Color.WHITE, 2.0, true)
	# mirror handle: a ring with two arrows pointing apart
	handles.draw_circle(corners[3], HANDLE_RADIUS, Color.WHITE)
	handles.draw_circle(corners[3], HANDLE_RADIUS, FRAME_COLOR, false, 2.0, true)
	var reach = HANDLE_RADIUS * 0.55
	handles.draw_line(corners[3] + Vector2(-reach, 0), corners[3] + Vector2(reach, 0), FRAME_COLOR, 2.0, true)
	for side in [-1, 1]:
		var tip = corners[3] + Vector2(reach * side, 0)
		handles.draw_line(tip, tip + Vector2(-3 * side, -3), FRAME_COLOR, 2.0, true)
		handles.draw_line(tip, tip + Vector2(-3 * side, 3), FRAME_COLOR, 2.0, true)
	# stretch handles: white squares with a line along the way they stretch
	if len(selection) == 1:
		var angle = _frame().angle
		for axis in 2:
			var middle = _stretch_handle(corners, axis)
			var half = HANDLE_RADIUS * 0.75
			var square = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)].map(
				func(corner): return middle + (corner * half).rotated(angle))
			handles.draw_colored_polygon(PackedVector2Array(square), Color.WHITE)
			_draw_outline(square, FRAME_COLOR, 2.0)
			var along = (Vector2.RIGHT if axis == 0 else Vector2.DOWN).rotated(angle) * half * 0.55
			handles.draw_line(middle - along, middle + along, FRAME_COLOR, 2.0, true)
	# eraser handle: a ring with a tilted eraser in it
	if len(selection) == 1:
		var middle = _eraser_handle(corners)
		handles.draw_circle(middle, HANDLE_RADIUS, Color.WHITE)
		handles.draw_circle(middle, HANDLE_RADIUS, FRAME_COLOR, false, 2.0, true)
		var along = Vector2(1, -1).normalized() * HANDLE_RADIUS * 0.55
		var across = along.orthogonal() * 0.55
		var body = [-along - across, along - across, along + across, -along + across]
		var tip = [-along - across, -along * 0.2 - across, -along * 0.2 + across, -along + across]
		handles.draw_colored_polygon(PackedVector2Array(body.map(func(v): return middle + v)), FRAME_COLOR)
		handles.draw_colored_polygon(PackedVector2Array(tip.map(func(v): return middle + v)), ERASER_COLOR)

func _draw_outline(corners:Array, color:Color, width:float) -> void:
	handles.draw_polyline(corners + [corners[0]], color, width, true)
