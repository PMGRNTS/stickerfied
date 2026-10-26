# Shows the stickers placed on the doll and lets the player arrange them:
#   - click a sticker to select it (it comes to the front), drag to move it
#   - drag the round handle at its corner to resize and turn it
#   - the red handle (or the Delete key) takes it off
#   - mouse wheel resizes the selected sticker, Shift + wheel turns it
# Changes are sent to interactivity.gd when the player lets go, so they can be undone.

extends Node2D

@export var interactivity: Node
# New stickers appear near this node (the SpritePlaceholder marks the middle of the doll)
@export var spawn_point: Node2D

const HANDLE_RADIUS := 11.0
const FRAME_COLOR := Color(0.2, 0.33, 0.85)
const DELETE_COLOR := Color(0.86, 0.25, 0.4)

enum Drag { NONE, MOVE, TRANSFORM }

var stickers := [] # the sticker data from the outfit
var sprites := [] # one Sprite2D per sticker
var selected := -1
var drag := Drag.NONE
var drag_offset := Vector2.ZERO
var drag_start_vector := Vector2.ZERO
var drag_start_scale := 1.0
var drag_start_rotation := 0.0
var changed_while_dragging := false

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


#####################################
############## SHOWING ##############
#####################################

# Called by interactivity.gd whenever the outfit changes
func show_stickers(new_stickers:Array) -> void:
	stickers = new_stickers.duplicate(true)
	while len(sprites) < len(stickers):
		var sprite = Sprite2D.new()
		add_child(sprite)
		sprites.append(sprite)
	while len(sprites) > len(stickers):
		sprites.pop_back().queue_free()
	for i in len(stickers):
		var button = interactivity.sticker_tab.get_item_button(stickers[i].id)
		sprites[i].texture = button.image if button else null
		_place_sprite(i)
	move_child(handles, -1)
	if selected >= len(stickers):
		selected = -1
	handles.queue_redraw()

func _place_sprite(i:int) -> void:
	sprites[i].position = Vector2(stickers[i].x, stickers[i].y)
	sprites[i].scale = Vector2.ONE * stickers[i].scale
	sprites[i].rotation = stickers[i].rot

func new_sticker_position() -> Vector2:
	var center = spawn_point.position if spawn_point else get_viewport_rect().size / 2
	return center + Vector2(randf_range(-50, 50), randf_range(-140, 0))

func select(index:int) -> void:
	selected = index
	handles.queue_redraw()

func deselect() -> void:
	select(-1)


#####################################
############## INPUT ################
#####################################

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		var point = _to_stage(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_press(point)
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and drag != Drag.NONE:
			drag = Drag.NONE
			if changed_while_dragging:
				_commit()
			get_viewport().set_input_as_handled()
		elif event.pressed and selected >= 0 and _sticker_at(point) == selected:
			var step = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0
			if step != 0:
				if event.shift_pressed:
					_set_rotation(selected, stickers[selected].rot + step * deg_to_rad(15))
				else:
					_set_scale(selected, stickers[selected].scale * pow(1.1, step))
				commit_timer.start()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and drag != Drag.NONE:
		_on_drag(_to_stage(event.position))
		get_viewport().set_input_as_handled()

	# pinch on a trackpad
	elif event is InputEventMagnifyGesture and selected >= 0:
		_set_scale(selected, stickers[selected].scale * event.factor)
		commit_timer.start()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and selected >= 0 \
			and event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
		_remove(selected)
		get_viewport().set_input_as_handled()

# Mouse positions are in window pixels; the stage may be scaled to fit the window
func _to_stage(window_position:Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * window_position

func _on_press(point:Vector2) -> void:
	if selected >= 0:
		var corners = _corners(selected)
		if point.distance_to(corners[1]) <= HANDLE_RADIUS + 3:
			_remove(selected)
			get_viewport().set_input_as_handled()
			return
		if point.distance_to(corners[2]) <= HANDLE_RADIUS + 3:
			drag = Drag.TRANSFORM
			drag_start_vector = point - sprites[selected].position
			drag_start_scale = stickers[selected].scale
			drag_start_rotation = stickers[selected].rot
			changed_while_dragging = false
			get_viewport().set_input_as_handled()
			return

	var index = _sticker_at(point)
	if index < 0:
		if selected >= 0:
			deselect()
		return
	# the picked sticker comes to the front
	if index != len(stickers) - 1:
		var sticker = stickers.pop_at(index)
		stickers.append(sticker)
		var sprite = sprites.pop_at(index)
		sprites.append(sprite)
		move_child(sprite, -1)
		move_child(handles, -1)
		index = len(stickers) - 1
		changed_while_dragging = true
	else:
		changed_while_dragging = false
	select(index)
	drag = Drag.MOVE
	drag_offset = sprites[index].position - point
	get_viewport().set_input_as_handled()

func _on_drag(point:Vector2) -> void:
	changed_while_dragging = true
	if drag == Drag.MOVE:
		var area = get_viewport_rect()
		var target = (point + drag_offset).clamp(area.position, area.end)
		stickers[selected].x = target.x
		stickers[selected].y = target.y
		_place_sprite(selected)
	elif drag == Drag.TRANSFORM:
		var vector = point - sprites[selected].position
		if drag_start_vector.length() > 1:
			_set_scale(selected, drag_start_scale * vector.length() / drag_start_vector.length())
		_set_rotation(selected, drag_start_rotation + drag_start_vector.angle_to(vector))
	handles.queue_redraw()

func _set_scale(i:int, value:float) -> void:
	stickers[i].scale = clampf(value, interactivity.STICKER_SCALE_LIMITS.x, interactivity.STICKER_SCALE_LIMITS.y)
	_place_sprite(i)
	handles.queue_redraw()

func _set_rotation(i:int, value:float) -> void:
	stickers[i].rot = wrapf(value, -PI, PI)
	_place_sprite(i)
	handles.queue_redraw()

func _remove(i:int) -> void:
	stickers.remove_at(i)
	selected = -1
	drag = Drag.NONE
	_commit()
	Sfx.play("click")

func _commit() -> void:
	commit_timer.stop()
	var keep_selected = selected
	interactivity.set_stickers(stickers.duplicate(true))
	select(keep_selected if keep_selected < len(stickers) else -1)


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
		if sprite.get_rect().has_point(local) and (i == selected or sprite.is_pixel_opaque(local)):
			return i
	return -1

# The sticker's corners on screen: top-left, top-right, bottom-right, bottom-left
func _corners(i:int) -> Array:
	var half = sprites[i].texture.get_size() / 2 if sprites[i].texture else Vector2.ZERO
	var t = sprites[i].transform
	return [t * Vector2(-half.x, -half.y), t * Vector2(half.x, -half.y),
		t * Vector2(half.x, half.y), t * Vector2(-half.x, half.y)]


#####################################
############## HANDLES ##############
#####################################

func _draw_handles() -> void:
	if selected < 0 or selected >= len(sprites):
		return
	var corners = _corners(selected)
	handles.draw_polyline(corners + [corners[0]], FRAME_COLOR, 2.0, true)
	# resize & turn handle: a ring with an arrow
	handles.draw_circle(corners[2], HANDLE_RADIUS, Color.WHITE)
	handles.draw_circle(corners[2], HANDLE_RADIUS, FRAME_COLOR, false, 2.0, true)
	handles.draw_arc(corners[2], HANDLE_RADIUS * 0.5, -PI * 0.25, PI * 1.25, 12, FRAME_COLOR, 2.0, true)
	# remove handle: a red circle with an x
	handles.draw_circle(corners[1], HANDLE_RADIUS, DELETE_COLOR)
	var arm = HANDLE_RADIUS * 0.4
	handles.draw_line(corners[1] + Vector2(-arm, -arm), corners[1] + Vector2(arm, arm), Color.WHITE, 2.0, true)
	handles.draw_line(corners[1] + Vector2(-arm, arm), corners[1] + Vector2(arm, -arm), Color.WHITE, 2.0, true)
