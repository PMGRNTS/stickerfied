# Reshapes the doll with the sliders in the Body menu: taller, wider shoulders, bigger eyes...
# Every layer of the doll (doll_layer.gd) is drawn on the same grid of points,
# and the controls under this node (body_control.gd) move those points.
# All layers bend the same way, so clothes still fit the reshaped body.
#
# Areas are applied first, from the top of the list down, then turns, then strips.
# Each area and turn moves along with the parts the ones above it moved, so list
# bigger parts first: the head before the eyes on it (the eyes' areas follow the eyes
# when the head grows), and the head's turn before the whole body leaning.
# Strips come last, so a taller doll still has its head on its neck.
#
# The doll blinks now and then: the Blink Slider's controls (squinting, in the sample doll)
# close the eyes for a moment. The slider itself stays where the player left it.

extends Node2D

# Sent whenever the doll's shape changes, so the stickers can follow it
signal shape_changed

const BodyControl = preload("res://script/body_control.gd")

# How many squares the grid has across and down. More squares bend the doll more smoothly,
# but take longer to move. Small areas (such as eyes) get extra points of their own.
@export var grid_size := Vector2i(30, 60)
# The slider that blinking moves all the way right for a moment, or "" for no blinking
@export var blink_slider := "Squint"
# Shortest and longest time between blinks, in seconds
@export var blink_every := Vector2(2.0, 6.0)
# How long a blink takes, in seconds
@export var blink_time := 0.16

# Areas smaller than this many grid squares get extra points, this many per square
const SMALL_AREA := 3.0
const SMALL_AREA_POINTS := 4

var layers := [] # the doll's layers (doll_layer.gd)
var to_screen := Transform2D() # from a layer's own coordinates to the screen
var rest := PackedVector2Array() # the grid points before any reshaping, in a layer's coordinates
var shaped_points := PackedVector2Array() # the grid points on the reshaped doll, without blinking
var blinking := PackedInt32Array() # the grid points that blinking moves
var values := {} # slider name -> -1..1, what the doll shows now
var neutral := false # while true the doll is shown as drawn (see hold_neutral)
var can_blink := false # true when a control has the blink slider
var blink := 0.0 # how closed the eyes are by blinking, 0 to 1
var blink_wait := 3.0 # seconds until the next blink
var blink_clock := -1.0 # seconds into the blink, or -1 between blinks

# Builds the grid over the doll's images. placeholder is the SpritePlaceholder
# that marks where the doll is, and has one of its images.
func setup(doll_layers:Array, placeholder:Sprite2D) -> void:
	layers = doll_layers
	to_screen = placeholder.get_global_transform()
	var image_size = placeholder.texture.get_size() if placeholder.texture else Vector2(300, 600)
	var middle = placeholder.offset + (Vector2.ZERO if placeholder.centered else image_size / 2)
	var corner = middle - image_size / 2
	var square = image_size / Vector2(grid_size)

	# grid points, kept by their place on a fine lattice so none are added twice
	var lattice = square / SMALL_AREA_POINTS
	var spots := {}
	for row in grid_size.y + 1:
		for column in grid_size.x + 1:
			spots[Vector2i(column, row) * SMALL_AREA_POINTS] = true
	# extra points inside small areas, so they bend smoothly
	var from_screen = to_screen.affine_inverse()
	for control in controls():
		var reach = control.reach * control.global_scale.abs() / to_screen.get_scale().abs()
		if control.shape != BodyControl.Shape.AREA or minf(reach.x / square.x, reach.y / square.y) >= SMALL_AREA:
			continue
		var center = from_screen * control.global_position
		var first = Vector2i(((center - reach - corner) / lattice).floor()).max(Vector2i.ZERO)
		var last = Vector2i(((center + reach - corner) / lattice).ceil()).min(grid_size * SMALL_AREA_POINTS)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				spots[Vector2i(x, y)] = true

	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for spot in spots:
		var uv = Vector2(spot) / Vector2(grid_size * SMALL_AREA_POINTS)
		uvs.append(uv)
		rest.append(corner + uv * image_size)
		colors.append(Color.WHITE)
	var triangles = Geometry2D.triangulate_delaunay(rest)

	for layer in layers:
		layer.offset = middle
		layer.uvs = uvs
		layer.colors = colors
		layer.triangles = triangles
	can_blink = blink_slider != "" and blink_slider in slider_names()
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
# Blinking is left out, so stickers on the eyes don't twitch.
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

func _process(delta:float) -> void:
	if not can_blink or rest.is_empty():
		return
	if blink_clock < 0.0:
		blink_wait -= delta
		if blink_wait <= 0.0:
			blink_clock = 0.0
		return
	blink_clock += delta
	blink = sin(PI * clampf(blink_clock / blink_time, 0.0, 1.0))
	if blink_clock >= blink_time:
		blink = 0.0
		blink_clock = -1.0
		blink_wait = randf_range(blink_every.x, blink_every.y)
	_update(false)

# The controls whose slider isn't in the middle, in the order they are applied:
# [control, value, where its middle is after the controls before it moved it].
# closed is how far blinking closes the eyes (0 leaves them as the slider says).
func _active(closed := 0.0) -> Array:
	var active := []
	if neutral:
		return active
	var shown = values.duplicate()
	if closed > 0.0:
		shown[blink_slider] = lerpf(clampf(float(shown.get(blink_slider, 0.0)), -1.0, 1.0), 1.0, closed)
	for shape in [BodyControl.Shape.AREA, BodyControl.Shape.TURN, BodyControl.Shape.STRIP]:
		for control in controls():
			var value = clampf(float(shown.get(control.slider, 0.0)), -1.0, 1.0)
			if control.shape != shape or value == 0.0:
				continue
			# strips work across the whole doll, so they stay where they are
			var middle = control.global_position
			if shape != BodyControl.Shape.STRIP:
				middle = _shaped(middle, active)
			active.append([control, value, middle])
	return active

func _shaped(point:Vector2, active:Array) -> Vector2:
	var moved = point
	for entry in active:
		moved = entry[0].shaped(moved, entry[1], entry[2])
	return moved

# Moves the grid's points to the doll's shape. follow is false while blinking:
# then only the points around the eyes move, and the stickers stay as they are.
func _update(follow := true) -> void:
	if rest.is_empty():
		return
	var from_screen = to_screen.affine_inverse()
	if follow:
		var active = _active()
		shaped_points = rest
		if not active.is_empty():
			shaped_points = PackedVector2Array()
			shaped_points.resize(len(rest))
			for i in len(rest):
				shaped_points[i] = from_screen * _shaped(to_screen * rest[i], active)
		_find_blinking()
	var points = shaped_points
	if blink > 0.0 and not blinking.is_empty():
		var active = _active(blink)
		points = shaped_points.duplicate()
		for i in blinking:
			points[i] = from_screen * _shaped(to_screen * rest[i], active)
	for layer in layers:
		layer.set_points(points)
	if follow:
		shape_changed.emit()

# Finds the grid points that blinking moves: those inside a blink control's area
# with the eyes closed
func _find_blinking() -> void:
	blinking = PackedInt32Array()
	if not can_blink:
		return
	var active = _active(1.0)
	for i in len(rest):
		var moved = to_screen * rest[i]
		for entry in active:
			if entry[0].slider == blink_slider and entry[0].reaches(moved, entry[2]):
				blinking.append(i)
				break
			moved = entry[0].shaped(moved, entry[1], entry[2])
