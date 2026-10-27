# Reshapes the doll with the sliders in the Body menu: taller, wider shoulders, bigger eyes...
# Every layer of the doll (doll_layer.gd) is drawn on the same grid of points,
# and the controls under this node (body_control.gd) move those points.
# All layers bend the same way, so clothes still fit the reshaped body.
#
# Areas all work on the doll as it is drawn, so their order doesn't matter.
# Turns are applied after them, from the top of the list down (put the head
# before the body leaning, so the head turns on the neck and then leans with the body).
# Strips come last, so a taller doll still has its head on its neck.

extends Node2D

# Sent whenever the doll's shape changes, so the stickers can follow it
signal shape_changed

const BodyControl = preload("res://script/body_control.gd")

# How many squares the grid has across and down. More squares bend small parts,
# such as eyes, more smoothly.
@export var grid_size := Vector2i(30, 60)

var layers := [] # the doll's layers (doll_layer.gd)
var to_screen := Transform2D() # from a layer's own coordinates to the screen
var rest := PackedVector2Array() # the grid points before any reshaping, in a layer's coordinates
var values := {} # slider name -> -1..1, what the doll shows now
var neutral := false # while true the doll is shown as drawn (see hold_neutral)

# Builds the grid over the doll's images. placeholder is the SpritePlaceholder
# that marks where the doll is, and has one of its images.
func setup(doll_layers:Array, placeholder:Sprite2D) -> void:
	layers = doll_layers
	to_screen = placeholder.get_global_transform()
	var image_size = placeholder.texture.get_size() if placeholder.texture else Vector2(300, 600)
	var middle = placeholder.offset + (Vector2.ZERO if placeholder.centered else image_size / 2)

	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for row in grid_size.y + 1:
		for column in grid_size.x + 1:
			var uv = Vector2(column, row) / Vector2(grid_size)
			uvs.append(uv)
			rest.append(middle + (uv - Vector2(0.5, 0.5)) * image_size)
			colors.append(Color.WHITE)
	var triangles := PackedInt32Array()
	var across = grid_size.x + 1
	for row in grid_size.y:
		for column in grid_size.x:
			var corner = row * across + column
			triangles.append_array([corner, corner + 1, corner + across,
				corner + 1, corner + across + 1, corner + across])

	for layer in layers:
		layer.offset = middle
		layer.uvs = uvs
		layer.colors = colors
		layer.triangles = triangles
	_update()

func controls() -> Array:
	return get_children().filter(func(child): return child is BodyControl)

# The sliders for the Body menu, grouped by heading, in the order the controls are listed:
#   [{"group": "Body", "sliders": ["Height", "Waist"]}, {"group": "Face", ...}]
func slider_groups() -> Array:
	var groups := []
	var seen := {}
	for control in controls():
		if control.slider == "" or seen.has(control.slider):
			continue
		seen[control.slider] = true
		var found = groups.filter(func(entry): return entry.group == control.group)
		if found.is_empty():
			found = [{"group": control.group, "sliders": []}]
			groups.append(found[0])
		found[0].sliders.append(control.slider)
	return groups

func slider_names() -> Array:
	var names := []
	for entry in slider_groups():
		names.append_array(entry.sliders)
	return names

# Shows the doll with these slider values (slider name -> -1..1, missing ones are 0)
func show_values(new_values:Dictionary) -> void:
	values = new_values.duplicate()
	_update()

# Shows the doll as drawn while on is true, for example while the player places a picture
# on it: pictures are added to the doll's images as drawn, so they must line up with that.
func hold_neutral(on:bool) -> void:
	neutral = on
	_update()

# Where a point on the screen moves to on the reshaped doll
func shaped(point:Vector2) -> Vector2:
	return _shaped(point, _active())

# How the doll's shape moves a point: where it goes ("position"),
# and how much the doll turns ("angle", in radians) and grows ("scale") there.
# Stickers use this to move, turn and grow with the part of the doll they are on.
func pose_at(point:Vector2) -> Dictionary:
	var active = _active()
	if active.is_empty():
		return {"position": point, "angle": 0.0, "scale": 1.0}
	var position = _shaped(point, active)
	var across = _shaped(point + Vector2.RIGHT, active) - position
	var down = _shaped(point + Vector2.DOWN, active) - position
	return {"position": position, "angle": atan2(across.y - down.x, across.x + down.y),
		"scale": sqrt(absf(across.cross(down)))}

# The point on the doll as drawn that the shape moves to point (the opposite of shaped())
func unshaped(point:Vector2) -> Vector2:
	var active = _active()
	if active.is_empty():
		return point
	var guess = point
	for i in 10:
		var miss = _shaped(guess, active) - point
		if miss.length() < 0.01:
			break
		# step back along the shape's slope at the guess (Newton's method)
		var across = _shaped(guess + Vector2.RIGHT, active) - _shaped(guess, active)
		var down = _shaped(guess + Vector2.DOWN, active) - _shaped(guess, active)
		var slope = across.cross(down)
		if absf(slope) < 0.000001:
			guess -= miss
		else:
			guess -= Vector2(down.y * miss.x - down.x * miss.y, across.x * miss.y - across.y * miss.x) / slope
	return guess

# The controls whose slider isn't in the middle, with their values
func _active() -> Array:
	var active := []
	if neutral:
		return active
	for control in controls():
		var value = clampf(float(values.get(control.slider, 0.0)), -1.0, 1.0)
		if value != 0.0:
			active.append([control, value])
	return active

func _shaped(point:Vector2, active:Array) -> Vector2:
	var moved = point
	for entry in active:
		if entry[0].shape == BodyControl.Shape.AREA:
			moved += entry[0].shaped(point, entry[1]) - point
	for shape in [BodyControl.Shape.TURN, BodyControl.Shape.STRIP]:
		for entry in active:
			if entry[0].shape == shape:
				moved = entry[0].shaped(moved, entry[1])
	return moved

func _update() -> void:
	if rest.is_empty():
		return
	var active = _active()
	var points = rest
	if not active.is_empty():
		var from_screen = to_screen.affine_inverse()
		points = PackedVector2Array()
		points.resize(len(rest))
		for i in len(rest):
			points[i] = from_screen * _shaped(to_screen * rest[i], active)
	for layer in layers:
		layer.set_points(points)
	shape_changed.emit()
