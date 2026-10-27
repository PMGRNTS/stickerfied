# Reshapes the doll with the sliders in the Body menu: taller, wider shoulders, bigger eyes...
# Every layer of the doll (doll_layer.gd) is drawn on the same grid of points,
# and the controls under this node (body_control.gd) move those points.
# All layers bend the same way, so clothes still fit the reshaped body.
#
# The sculpt brush's pushes come first (see body_sculpt.gd), so the sliders work on the
# sculpted doll. Then areas, from the top of the list down, then turns, then strips.
# Each area and turn moves along with the parts the ones above it moved, so list
# bigger parts first: the head before the eyes on it (the eyes' areas follow the eyes
# when the head grows), and the head's turn before the whole body leaning.
# Strips come last, so a taller doll still has its head on its neck.
#
# The doll moves by itself a little: it blinks now and then (the Blink Slider's controls,
# squinting in the sample doll, close the eyes for a moment) and breathes (the Breathe
# Slider's controls, which have no place in the Body menu, go back and forth slowly).
# Areas with Swing make layers such as hair hang loose from the top of the area: they move
# with whatever is above them (long hair follows the head as it tilts, and doesn't widen
# with the hips under it), lag behind and swing back.
# Stickers follow the doll's shape, but not these small movements.
#
# Players can move the controls to fit their own doll (see body_fitter.gd).
# Each body picture (the first layer after the backgrounds) keeps its own fit,
# saved on the player's device.

extends Node2D

# Sent whenever the doll's shape changes, so the stickers can follow it
signal shape_changed

const BodyControl = preload("res://script/body_control.gd")
const BodySculpt = preload("res://script/body_sculpt.gd")
# Where outfits keep the sculpt brush's pushes, among the sliders' values
const SCULPT := "_sculpt"
const FIT_FILE := "user://body_fit.json"
# Areas smaller than this many grid squares get extra points, this many per square
const SMALL_AREA := 3.0
const SMALL_AREA_POINTS := 4
# How hard swinging parts are pulled back, how quickly they settle,
# and how far (in pixels) they can lag behind
const SWING_STIFFNESS := 90.0
const SWING_DAMPING := 7.0
const SWING_LIMIT := 30.0

# How many squares the grid has across and down. More squares bend the doll more smoothly,
# but take longer to move. Small areas (such as eyes) get extra points of their own.
@export var grid_size := Vector2i(30, 60)
# The slider that blinking moves all the way right for a moment, or "" for no blinking
@export var blink_slider := "Squint"
# Shortest and longest time between blinks, in seconds
@export var blink_every := Vector2(2.0, 6.0)
# How long a blink takes, in seconds
@export var blink_time := 0.16
# The slider that breathing moves from the middle to all the way right and back,
# or "" for no breathing. Give its controls an empty Group, so it isn't in the Body menu.
@export var breathe_slider := "Breathing"
# How long one breath takes, in seconds
@export var breath_time := 4.0

var layers := [] # the doll's layers (doll_layer.gd)
var to_screen := Transform2D() # from a layer's own coordinates to the screen
var image_size := Vector2.ONE # the size of the doll's images
var middle := Vector2.ZERO # the middle of the doll's images, in a layer's coordinates
var rest := PackedVector2Array() # the grid points before any reshaping, in a layer's coordinates
var uvs := PackedVector2Array() # where each grid point is in the doll's images (0 to 1)
var shaped_points := PackedVector2Array() # the grid points on the reshaped doll, standing still
var moving := PackedInt32Array() # the grid points that blinking and breathing move
var values := {} # slider name -> -1..1, what the doll shows now, and the sculpt as "_sculpt"
var sculpt: BodySculpt # the sculpt brush's pushes shown now
var sculpted := false # true when the sculpt has any pushes
var neutral := false # while true the doll is shown as drawn (see hold_neutral)

var can_blink := false # true when a control has the blink slider
var blink := 0.0 # how closed the eyes are by blinking, 0 to 1
var blink_wait := 3.0 # seconds until the next blink
var blink_clock := -1.0 # seconds into the blink, or -1 between blinks
var can_breathe := false # true when a control has the breathe slider
var breath := 0.0 # how far the doll has breathed in, 0 to 1
var breath_clock := 0.0

# For each layer that swings: {"layer", "points" (grid point indexes), "looseness" (0 to 1 each),
# "anchors" (where each point hangs from, on the screen), "targets" (where each point hangs
# now), "last" (targets shown last), "offsets" (how far each lags behind), "speeds", "settled"}
var swings := []

var defaults := {} # control name -> [position, reach] as placed in the scene
var fits := {} # body picture -> {control name: {"x", "y", "reach_x", "reach_y"}} (see save_fit)
var body_item := "" # the body picture worn now, whose fit the controls show

# Builds the grid over the doll's images. placeholder is the SpritePlaceholder
# that marks where the doll is, and has one of its images.
func setup(doll_layers:Array, placeholder:Sprite2D) -> void:
	layers = doll_layers
	to_screen = placeholder.get_global_transform()
	image_size = placeholder.texture.get_size() if placeholder.texture else Vector2(300, 600)
	middle = placeholder.offset + (Vector2.ZERO if placeholder.centered else image_size / 2)
	for layer in layers:
		layer.offset = middle
	sculpt = BodySculpt.new(middle - image_size / 2, image_size, to_screen)
	for control in controls():
		defaults[control.name] = [control.global_position, control.reach]
	if FileAccess.file_exists(FIT_FILE):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(FIT_FILE))
		fits = saved if saved is Dictionary else {}
	can_blink = blink_slider != "" and controls().any(func(control): return control.slider == blink_slider)
	can_breathe = breathe_slider != "" and controls().any(func(control): return control.slider == breathe_slider)
	_build_grid()
	_update()

func controls() -> Array:
	return get_children().filter(func(child): return child is BodyControl)

# The sliders for the Body menu, grouped by heading, in the order the controls are listed:
#   [{"group": "Body", "sliders": ["Height", "Waist"]}, {"group": "Face", ...}]
# Controls without a slider or a group (moved by the game itself) aren't listed.
func slider_groups() -> Array:
	var groups := []
	var seen := {}
	for control in controls():
		if control.slider == "" or control.group == "" or seen.has(control.slider):
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
# and sculpt (under "_sculpt")
func show_values(new_values:Dictionary) -> void:
	values = new_values.duplicate()
	if sculpt:
		sculpt.load_saved(values.get(SCULPT))
		sculpted = not sculpt.is_empty()
	_update()

# Shows the sculpt after the sculpt brush changed it (see body_sculptor.gd)
func show_sculpt() -> void:
	sculpted = not sculpt.is_empty()
	_update()

# An outfit's "_sculpt" with only the pushes this game can show, or {} for none
func cleaned_sculpt(saved) -> Dictionary:
	if sculpt == null:
		return {}
	var check = BodySculpt.new(sculpt.corner, image_size, to_screen)
	check.load_saved(saved)
	return check.to_saved()

# Shows the doll as drawn while on is true, for example while the player places a picture
# on it: pictures are added to the doll's images as drawn, so they must line up with that.
func hold_neutral(on:bool) -> void:
	neutral = on
	_stop_swinging()
	_update()

# Where a point on the screen moves to on the reshaped doll
func shaped(point:Vector2) -> Vector2:
	return _shaped(point, _active())

# How the doll's shape moves a point: where it goes ("position"),
# and how much the doll turns ("angle", in radians) and grows ("scale") there.
# Stickers use this to move, turn and grow with the part of the doll they are on.
# Blinking and breathing are left out, so stickers don't twitch.
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


#####################################
############## FITTING ##############
#####################################

# Puts the controls where they fit this body picture (item_id of the first layer
# after the backgrounds). Called whenever the outfit is shown.
func use_body(item_id:String) -> void:
	if item_id == body_item:
		return
	body_item = item_id
	_place_controls()
	_build_grid()
	_update()

# Where the control goes as placed in the scene: [position, reach]
func default_of(control:Node2D) -> Array:
	return defaults.get(control.name, [control.global_position, control.reach])

# Keeps where the controls are now as the fit for the body picture worn now
# (only the ones moved from where they are placed in the scene), and reshapes the doll.
func save_fit() -> void:
	var fit := {}
	var from_screen = to_screen.affine_inverse()
	for control in controls():
		var placed = default_of(control)
		if control.global_position.is_equal_approx(placed[0]) and control.reach.is_equal_approx(placed[1]):
			continue
		var spot = from_screen * control.global_position
		fit[control.name] = {"x": snappedf(spot.x, 0.1), "y": snappedf(spot.y, 0.1),
			"reach_x": snappedf(control.reach.x, 0.1), "reach_y": snappedf(control.reach.y, 0.1)}
	if fit.is_empty():
		fits.erase(body_item)
	else:
		fits[body_item] = fit
	var file = FileAccess.open(FIT_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(fits))
	_build_grid()
	_update()

func _place_controls() -> void:
	var fit = fits.get(body_item, {})
	for control in controls():
		var placed = default_of(control)
		control.global_position = placed[0]
		control.reach = placed[1]
		var moved = fit.get(control.name) if fit is Dictionary else null
		if moved is Dictionary:
			control.global_position = to_screen * Vector2(float(moved.get("x", 0)), float(moved.get("y", 0)))
			control.reach = Vector2(float(moved.get("reach_x", 1)), float(moved.get("reach_y", 1))).max(Vector2.ONE)


#####################################
############## THE GRID #############
#####################################

# Lays the grid over the doll's images, with extra points in small areas
func _build_grid() -> void:
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

	rest = PackedVector2Array()
	uvs = PackedVector2Array()
	var colors := PackedColorArray()
	for spot in spots:
		var uv = Vector2(spot) / Vector2(grid_size * SMALL_AREA_POINTS)
		uvs.append(uv)
		rest.append(corner + uv * image_size)
		colors.append(Color.WHITE)
	var triangles = Geometry2D.triangulate_delaunay(rest)
	for layer in layers:
		layer.uvs = uvs
		layer.colors = colors
		layer.triangles = triangles
	_find_swings()


#####################################
############## SHAPING ##############
#####################################

# The controls whose slider isn't in the middle, in the order they are applied:
# [control, value, where its middle is after the controls before it moved it].
# closed is how far blinking closes the eyes (0 leaves them as the slider says),
# and inhaled how far the doll has breathed in.
func _active(closed := 0.0, inhaled := 0.0) -> Array:
	var active := []
	if neutral:
		return active
	var shown = values.duplicate()
	if can_blink and closed > 0.0:
		shown[blink_slider] = lerpf(clampf(float(shown.get(blink_slider, 0.0)), -1.0, 1.0), 1.0, closed)
	if can_breathe:
		shown[breathe_slider] = inhaled
	if sculpted:
		active.append([sculpt, 1.0, Vector2.ZERO])
	for shape in [BodyControl.Shape.AREA, BodyControl.Shape.TURN, BodyControl.Shape.STRIP]:
		for control in controls():
			var value = clampf(float(shown.get(control.slider, 0.0)), -1.0, 1.0)
			if control.shape != shape or value == 0.0:
				continue
			# strips work across the whole doll, so they stay where they are
			var middle_now = control.global_position
			if shape != BodyControl.Shape.STRIP:
				middle_now = _shaped(middle_now, active)
			active.append([control, value, middle_now])
	return active

func _shaped(point:Vector2, active:Array) -> Vector2:
	var moved = point
	for entry in active:
		moved = entry[0].shaped(moved, entry[1], entry[2])
	return moved

# Moves the grid's points to the doll's shape
func _update() -> void:
	if rest.is_empty():
		return
	var active = _active()
	shaped_points = rest
	if not active.is_empty():
		var from_screen = to_screen.affine_inverse()
		shaped_points = PackedVector2Array()
		shaped_points.resize(len(rest))
		for i in len(rest):
			shaped_points[i] = from_screen * _shaped(to_screen * rest[i], active)
	_hang(active)
	_find_moving()
	_show()
	shape_changed.emit()

# Where swinging points hang: moved along with the point they hang from, as loosely as they hang
func _hang(active:Array) -> void:
	var from_screen = to_screen.affine_inverse()
	for swing in swings:
		var targets := PackedVector2Array()
		for k in len(swing.points):
			var i = swing.points[k]
			var anchor: Vector2 = swing.anchors[k]
			var hanging = rest[i] + from_screen.basis_xform(_shaped(anchor, active) - anchor)
			targets.append(shaped_points[i].lerp(hanging, swing.looseness[k]))
		swing.targets = targets

# Shows the grid's points with blinking, breathing and swinging on top of the doll's shape
func _show() -> void:
	var points = shaped_points
	if not moving.is_empty() and (blink > 0.0 or breath > 0.0):
		var active = _active(blink, breath)
		var from_screen = to_screen.affine_inverse()
		points = shaped_points.duplicate()
		for i in moving:
			points[i] = from_screen * _shaped(to_screen * rest[i], active)
	for layer in layers:
		layer.set_points(points)
	for swing in swings:
		# swinging points stay behind when what they hang from moves
		var offsets: PackedVector2Array = swing.offsets
		if len(swing.last) == len(swing.targets):
			for k in len(swing.points):
				var moved = swing.targets[k] - swing.last[k]
				if moved != Vector2.ZERO:
					offsets[k] = (offsets[k] - moved * swing.looseness[k]).limit_length(SWING_LIMIT)
					swing.settled = false
		swing.offsets = offsets
		swing.last = swing.targets
		var swung = points.duplicate()
		for k in len(swing.points):
			swung[swing.points[k]] = swing.targets[k] + offsets[k]
		swing.layer.set_points(swung)

# Finds the grid points that blinking and breathing move: those inside their controls'
# areas with the eyes closed and the doll breathed in
func _find_moving() -> void:
	moving = PackedInt32Array()
	var names := []
	if can_blink:
		names.append(blink_slider)
	if can_breathe:
		names.append(breathe_slider)
	if names.is_empty():
		return
	var active = _active(1.0, 1.0)
	for i in len(rest):
		var moved = to_screen * rest[i]
		for entry in active:
			if entry[0].slider in names and entry[0].reaches(moved, entry[2]):
				moving.append(i)
				break
			moved = entry[0].shaped(moved, entry[1], entry[2])

# Finds which grid points of which layers swing, and how loosely
func _find_swings() -> void:
	swings = []
	var swinging = controls().filter(func(control): return control.swing > 0.0)
	for layer in layers:
		var mine = swinging.filter(func(control): return control.swings_layer(layer.name))
		if mine.is_empty():
			continue
		var points := PackedInt32Array()
		var looseness := PackedFloat32Array()
		var anchors := PackedVector2Array()
		for i in len(rest):
			var spot = to_screen * rest[i]
			var loose = 0.0
			var loosest = null
			for control in mine:
				var amount = control.looseness(spot)
				if amount > 0.0 and (loosest == null or amount > loosest.looseness(spot)):
					loosest = control
				loose += amount
			if loose > 0.001:
				points.append(i)
				looseness.append(minf(loose, 1.0))
				# it hangs from the top of its area, straight above it
				anchors.append(Vector2(spot.x, loosest.global_position.y - loosest.reach.y * loosest.global_scale.y))
		var still := PackedVector2Array()
		still.resize(len(points))
		swings.append({"layer": layer, "points": points, "looseness": looseness, "anchors": anchors,
			"targets": PackedVector2Array(), "last": PackedVector2Array(),
			"offsets": still, "speeds": still.duplicate(), "settled": true})

func _stop_swinging() -> void:
	for swing in swings:
		var still := PackedVector2Array()
		still.resize(len(swing.points))
		swing.offsets = still
		swing.speeds = still.duplicate()
		swing.last = PackedVector2Array()


#####################################
############## MOVING BY ITSELF #####
#####################################

func _process(delta:float) -> void:
	if rest.is_empty():
		return
	delta = minf(delta, 1.0 / 30.0)
	var changed = _blink(delta)
	if can_breathe and not neutral:
		breath_clock = fmod(breath_clock + delta, breath_time)
		breath = (1.0 - cos(TAU * breath_clock / breath_time)) / 2.0
		changed = true
	for swing in swings:
		if not swing.settled:
			_swing(swing, delta)
			changed = true
	if changed:
		_show()

# Moves the blink along. Returns true when the eyes moved.
func _blink(delta:float) -> bool:
	if not can_blink:
		return false
	if blink_clock < 0.0:
		blink_wait -= delta
		if blink_wait <= 0.0:
			blink_clock = 0.0
		return false
	blink_clock += delta
	blink = sin(PI * clampf(blink_clock / blink_time, 0.0, 1.0))
	if blink_clock >= blink_time:
		blink = 0.0
		blink_clock = -1.0
		blink_wait = randf_range(blink_every.x, blink_every.y)
	return true

# Pulls swinging points back towards their place, a little past it, and back again
func _swing(swing:Dictionary, delta:float) -> void:
	var offsets: PackedVector2Array = swing.offsets
	var speeds: PackedVector2Array = swing.speeds
	var still = true
	for k in len(offsets):
		speeds[k] += (-SWING_STIFFNESS * offsets[k] - SWING_DAMPING * speeds[k]) * delta
		offsets[k] += speeds[k] * delta
		if offsets[k].length_squared() > 0.0025 or speeds[k].length_squared() > 0.01:
			still = false
	if still:
		offsets.fill(Vector2.ZERO)
		speeds.fill(Vector2.ZERO)
		swing.settled = true
	swing.offsets = offsets
	swing.speeds = speeds
