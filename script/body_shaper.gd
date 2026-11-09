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
# Stickers bend with the doll's shape and breathe with it, but don't blink or swing.
#
# The doll also pulls faces and strikes poses (see doll_mood.gd): show_expression() adds
# slider values on top of the player's for a while, such as {"Smile": -0.6} for a pout.
# Moving every point through the controls each frame is too slow, so the new pose is
# worked out a little each frame, and then the doll slides from the old pose to it.
# Stickers move along with the pose (see sticker_stage.gd). Poses are never saved in outfits.
#
# The skeleton (body_skeleton.gd, the Skeleton node) turns arms and legs at their joints.
# Its bones' sliders are listed in the Body menu like the others, and it is applied last,
# so the bones turn the reshaped doll.
#
# Players can move the controls to fit their own doll (see body_fitter.gd), or have the
# game put the controls with a Landmark on the doll's parts (see body_finder.gd).
# Each body picture (the first layer after the backgrounds) keeps its own fit,
# saved on the player's device.

extends Node2D

# Sent whenever the doll's shape changes, so the stickers can follow it
signal shape_changed
# Sent when the doll starts moving to a new pose (see show_expression)
signal expression_started

const BodyControl = preload("res://script/body_control.gd")
const BodySculpt = preload("res://script/body_sculpt.gd")
const BodyFinder = preload("res://script/body_finder.gd")
const BodySkeleton = preload("res://script/body_skeleton.gd")
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
# How long each frame may spend working out a new pose, in microseconds
const POSE_BUDGET := 4000
# How far (in pixels) past their controls' ovals points are checked for blinking and breathing
const NEAR_MARGIN := 24.0

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
var shaped_points := PackedVector2Array() # the grid points on the reshaped doll in its pose now, standing still
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

var expression := {} # slider name -> -1..1 added to the player's sliders: the pose shown, or being moved to
var expression_from := {} # the pose being moved from (the same as expression when standing still)
var pose_from := PackedVector2Array() # shaped_points in that pose
var pose_to := PackedVector2Array() # shaped_points in the pose being moved to
var moving_after := PackedInt32Array() # the points blinking and breathing move in that pose
var pose_clock := 0.0 # seconds into the move
var pose_time := 0.0 # how long the move takes, or 0 when the doll isn't moving to a pose
var pose_snappy := false # snappy moves overshoot a little and settle, like a flick
var pose_weight := 1.0 # how far the doll has moved to the new pose, eased (a little past 1 when snappy)

# The pose being worked out a little each frame (see show_expression), or null
var next_face = null
var next_seconds := 0.0
var next_snappy := false
var next_active := [] # the controls, as _active() gives them, in that pose
var next_closed := [] # the same with the eyes closed and breathed in, to find the moving points
var next_points := PackedVector2Array() # the grid points in that pose, worked out so far
var next_checked := 0 # how many grid points have been checked for blinking and breathing
var next_moving := PackedInt32Array()
var next_hanging := [] # for each swing, where its points hang in that pose

# For each layer that swings: {"layer", "points" (grid point indexes), "looseness" (0 to 1 each),
# "anchors" (where each point hangs from, on the screen), "targets" (where each point hangs
# now), "last" (targets shown last), "offsets" (how far each lags behind), "speeds", "settled",
# and while moving to a pose "from" and "to" (the targets in the poses moved from and to)}
var swings := []

var defaults := {} # control name -> [position, reach] as placed in the scene
var fits := {} # body picture -> {control name: {"x", "y", "reach_x", "reach_y"}} (see save_fit)
var body_item := "" # the body picture worn now, whose fit the controls show
var pictures := {} # layer pictures (Texture2D -> Image), looked at by is_on_doll()
var skeleton: BodySkeleton # the Skeleton node, or null for none

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
	for child in get_children():
		if child is BodySkeleton:
			skeleton = child
			skeleton.collect()
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

# The skeleton's bones (body_bone.gd)
func bones() -> Array:
	return skeleton.bones if skeleton else []

# The sliders for the Body menu, grouped by heading, in the order the controls are listed:
#   [{"group": "Body", "sliders": ["Height", "Waist"]}, {"group": "Face", ...}]
# Controls without a slider or a group (moved by the game itself) aren't listed.
func slider_groups() -> Array:
	var groups := []
	var seen := {}
	for control in controls() + bones():
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

# Moves the doll to a pose over seconds: face is slider values added to the player's,
# such as {"Smile": -0.6, "Cheeks": 0.4}, or {} for none. Snappy moves overshoot a little
# and settle, the others ease in and out. It starts after a few frames, once worked out.
func show_expression(face:Dictionary, seconds := 0.3, snappy := false) -> void:
	if neutral or rest.is_empty():
		expression = face.duplicate()
		return # shown when the doll is let go (see hold_neutral)
	if next_face == null and pose_time <= 0.0 and face == expression:
		return
	next_face = face.duplicate()
	next_seconds = seconds
	next_snappy = snappy
	next_active = _active(0.0, 0.0, next_face)
	next_closed = _active(1.0, 1.0, next_face)
	next_points = PackedVector2Array()
	next_checked = 0
	next_moving = PackedInt32Array()
	next_hanging = []

# True while a pose is being worked out or moved to
func is_posing() -> bool:
	return next_face != null or pose_time > 0.0

# How the pose face moves a small thing at point (on the doll as drawn): from where it is
# on the reshaped doll to where it is in that pose. Stickers move along with poses this way.
func posed(point:Vector2, face:Dictionary) -> Transform2D:
	if face.is_empty() or neutral:
		return Transform2D.IDENTITY
	var plain = _pose(point, _active())
	var with_face = _pose(point, _active(0.0, 0.0, face))
	var before = Transform2D(plain.angle, Vector2.ONE * plain.scale, 0.0, plain.position)
	var after = Transform2D(with_face.angle, Vector2.ONE * with_face.scale, 0.0, with_face.position)
	return after * before.affine_inverse()

# Where a point on the screen moves to on the reshaped doll
func shaped(point:Vector2) -> Vector2:
	return _shaped(point, _active())

# How the doll's shape moves a point: where it goes ("position"),
# and how much the doll turns ("angle", in radians) and grows ("scale") there.
# Stickers use this for their frame and handles, which move, turn and grow with the part
# of the doll they are on. Blinking, breathing and poses are left out, so the handles hold still.
func pose_at(point:Vector2) -> Dictionary:
	return _pose(point, _active())

func _pose(point:Vector2, active:Array) -> Dictionary:
	if active.is_empty():
		return {"position": point, "angle": 0.0, "scale": 1.0}
	var position = _shaped(point, active)
	var across = _shaped(point + Vector2.RIGHT, active) - position
	var down = _shaped(point + Vector2.DOWN, active) - position
	return {"position": position, "angle": atan2(across.y - down.x, across.x + down.y),
		"scale": sqrt(absf(across.cross(down)))}

# Where points on the screen move to on the reshaped doll, breathed in by inhaled (0 to 1).
# Stickers are bent along with the doll this way. Blinking is left out, so stickers
# such as sunglasses don't squash shut.
func bent(points:PackedVector2Array, inhaled := 0.0) -> PackedVector2Array:
	var active = _active(0.0, inhaled)
	if active.is_empty():
		return points
	var moved := PackedVector2Array()
	moved.resize(len(points))
	for k in len(points):
		moved[k] = _shaped(points[k], active)
	return moved

# Whether point (on the screen) is on the doll: on a part of one of its layers' pictures
# that isn't see-through. The pose is left out, which is close enough for a click.
func is_on_doll(point:Vector2) -> bool:
	if rest.is_empty():
		return false
	var drawn = _unshape(point)
	return drawn != null and _on_pictures(drawn)

# Whether point (on the doll as drawn) is on a part of a layer's picture that isn't see-through
func _on_pictures(drawn:Vector2) -> bool:
	var uv = (to_screen.affine_inverse() * drawn - (middle - image_size / 2)) / image_size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return false
	for layer in layers:
		if not layer.visible or layer.texture == null:
			continue
		if not pictures.has(layer.texture):
			if len(pictures) > 8:
				pictures.clear() # only keep the pictures worn lately
			var image = layer.texture.get_image()
			if image and image.is_compressed():
				image.decompress()
			pictures[layer.texture] = image
		var picture: Image = pictures[layer.texture]
		if picture and picture.get_pixelv(Vector2i(uv * Vector2(picture.get_size()))).a > 0.3:
			return true
	return false

# The point on the doll as drawn that the shape moves to point (the opposite of shaped()).
# A turned arm can cover empty space, so two points can move to the same place:
# then the one on the doll (the arm) is the answer.
func unshaped(point:Vector2) -> Vector2:
	var drawn = _unshape(point)
	return drawn if drawn != null else point

# Like unshaped(), but null when nothing on the doll moves to point
# (such as where a turned arm used to be)
func _unshape(point:Vector2):
	var active = _active()
	if active.is_empty():
		return point
	var starts = [point]
	for entry in active:
		if entry[0] == skeleton:
			for move in entry[2]:
				if move != Transform2D.IDENTITY:
					starts.append(move.affine_inverse() * point)
	var first_found = null
	for start in starts:
		var found = _unshaped_from(point, start, active)
		if found == null:
			continue
		if len(starts) == 1 or _on_pictures(found):
			return found
		if first_found == null:
			first_found = found
	return first_found

# Looks for the point that the shape moves to point, starting at guess
# (Newton's method), or null when it isn't found
func _unshaped_from(point:Vector2, guess:Vector2, active:Array):
	for i in 12:
		var miss = _shaped(guess, active) - point
		if miss.length() < 0.05:
			return guess
		# step back along the shape's slope at the guess
		var across = _shaped(guess + Vector2.RIGHT, active) - _shaped(guess, active)
		var down = _shaped(guess + Vector2.DOWN, active) - _shaped(guess, active)
		var slope = across.cross(down)
		if absf(slope) < 0.000001:
			guess -= miss
		else:
			guess -= Vector2(down.y * miss.x - down.x * miss.y, across.x * miss.y - across.y * miss.x) / slope
	return guess if (_shaped(guess, active) - point).length() < 1.0 else null


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
		elif fit is Dictionary:
			_place_like_neighbor(control, fit)

# A control the fit doesn't have (such as one added to the game after the player fitted
# their doll) moves and grows along with one on the same landmark that the fit has,
# preferably of the same shape
func _place_like_neighbor(control:Node2D, fit:Dictionary) -> void:
	if control.landmark == BodyControl.Landmark.NONE:
		return
	var neighbors = controls().filter(func(other): return other != control \
		and other.landmark == control.landmark and fit.get(other.name) is Dictionary)
	if neighbors.is_empty():
		return
	neighbors.sort_custom(func(a, b): return a.shape == control.shape and b.shape != control.shape)
	var moved = fit[neighbors[0].name]
	var placed = default_of(neighbors[0])
	var grown = Vector2(float(moved.get("reach_x", 1)), float(moved.get("reach_y", 1))).max(Vector2.ONE) / placed[1]
	var spot = to_screen * Vector2(float(moved.get("x", 0)), float(moved.get("y", 0)))
	control.global_position = spot + (control.global_position - placed[0]) * grown
	control.reach = (control.reach * grown).max(Vector2.ONE)

# Puts the controls that have a landmark on that part of the body picture worn now
# (see body_finder.gd): where it usually is on a doll standing straight and facing forward,
# or, with find, where it is found in the doll's pictures. Controls on the same landmark
# and of the same shape keep their sizes compared to each other.
# Returns false when the body picture can't be looked at.
func place_on_parts(find:bool) -> bool:
	if layers.is_empty() or layers[0].texture == null:
		return false
	var picture = layers[0].texture.get_image()
	if picture == null:
		return false
	var others := []
	if find:
		for layer in layers.slice(1):
			var image = layer.texture.get_image() if layer.visible and layer.texture else null
			if image:
				others.append(image)
	var landmarks = BodyFinder.find(picture, others) if find else BodyFinder.standard(picture)
	if landmarks.is_empty():
		return false
	var pixel = image_size / Vector2(picture.get_size()) # from the picture's pixels to a layer's
	var corner = middle - image_size / 2
	var biggest := {}
	for control in controls():
		var key = Vector2i(control.landmark, control.shape)
		biggest[key] = biggest.get(key, Vector2.ONE).max(default_of(control)[1])
	for control in controls():
		var found = landmarks.get(control.landmark)
		if found == null:
			continue
		var size = found.get("turn", found.size) if control.shape == BodyControl.Shape.TURN else found.size
		size *= pixel * to_screen.get_scale().abs() / control.global_scale.abs()
		var share = default_of(control)[1] / biggest[Vector2i(control.landmark, control.shape)]
		control.global_position = to_screen * (corner + found.at * pixel)
		control.reach = (size * share).max(Vector2.ONE * 2.0)
	return true


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
	# extra points along the bones that turn, so arms and legs bend smoothly at their edges
	var fine = SMALL_AREA_POINTS / 2
	for bone in bones():
		if bone.slider == "":
			continue
		var start = from_screen * bone.global_position - corner
		var finish = from_screen * bone.tip() - corner
		var width = bone.width * bone.global_scale.x / to_screen.get_scale().x + square.x / 2
		var first = Vector2i(((start.min(finish) - Vector2.ONE * width) / lattice).floor()).max(Vector2i.ZERO)
		var last = Vector2i(((start.max(finish) + Vector2.ONE * width) / lattice).ceil()).min(grid_size * SMALL_AREA_POINTS)
		first = first / fine * fine
		for y in range(first.y, last.y + 1, fine):
			for x in range(first.x, last.x + 1, fine):
				var spot = Vector2(x, y) * lattice
				if spot.distance_to(Geometry2D.get_closest_point_to_segment(spot, start, finish)) <= width:
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
	if skeleton:
		var body_picture = layers[0].texture if not layers.is_empty() else null
		skeleton.build(body_picture, corner, image_size, to_screen)
	_find_swings()


#####################################
############## SHAPING ##############
#####################################

# The controls whose slider isn't in the middle, in the order they are applied:
# [control, value, where its middle is after the controls before it moved it].
# closed is how far blinking closes the eyes (0 leaves them as the slider says),
# inhaled how far the doll has breathed in, and face a pose added to the sliders.
func _active(closed := 0.0, inhaled := 0.0, face := {}) -> Array:
	var active := []
	if neutral:
		return active
	var shown = values.duplicate()
	for slider in face:
		shown[slider] = float(shown.get(slider, 0.0)) + face[slider]
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
	# the bones turn last, at their joints on the reshaped doll
	if skeleton and skeleton.has_turning_bones():
		var joints = skeleton.bones.map(func(bone): return _shaped(bone.global_position, active))
		var moves = skeleton.pose(shown, joints)
		if not moves.is_empty():
			active.append([skeleton, 1.0, moves])
	return active

func _shaped(point:Vector2, active:Array) -> Vector2:
	var moved = point
	for entry in active:
		moved = _step(entry, moved, point)
	return moved

# Moves point (where the steps before moved drawn, a point on the doll as drawn)
# by one entry of _active()
func _step(entry:Array, point:Vector2, drawn:Vector2) -> Vector2:
	if entry[0] == skeleton:
		return skeleton.posed(point, drawn, entry[2])
	return entry[0].shaped(point, entry[1], entry[2])

# Moves the grid's points to the doll's shape, in its pose straight away
func _update() -> void:
	if rest.is_empty():
		return
	if next_face != null:
		expression = next_face
		next_face = null
	expression_from = expression
	pose_time = 0.0
	pose_weight = 1.0
	var active = _active(0.0, 0.0, expression)
	shaped_points = rest
	if not active.is_empty():
		var from_screen = to_screen.affine_inverse()
		shaped_points = PackedVector2Array()
		shaped_points.resize(len(rest))
		for i in len(rest):
			shaped_points[i] = from_screen * _shaped(to_screen * rest[i], active)
	pose_from = shaped_points
	pose_to = shaped_points
	for swing in swings:
		swing.targets = _hanging(swing, shaped_points, active)
	_find_moving()
	_show()
	shape_changed.emit()

# Where a swing's points hang, with the doll's points at points: moved along with the point
# they hang from, as loosely as they hang. Many points hang from the same anchor.
func _hanging(swing:Dictionary, points:PackedVector2Array, active:Array) -> PackedVector2Array:
	var from_screen = to_screen.affine_inverse()
	var anchored := {}
	var targets := PackedVector2Array()
	for k in len(swing.points):
		var i = swing.points[k]
		var anchor: Vector2 = swing.anchors[k]
		if not anchored.has(anchor):
			anchored[anchor] = from_screen.basis_xform(_shaped(anchor, active) - anchor)
		targets.append(points[i].lerp(rest[i] + anchored[anchor], swing.looseness[k]))
	return targets

# Shows the grid's points with blinking, breathing and swinging on top of the doll's shape
func _show() -> void:
	var points = shaped_points
	if not moving.is_empty() and (blink > 0.0 or breath > 0.0):
		var face = _face_now()
		var active = _active(blink, breath, face)
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
	var closed = _active(1.0, 1.0, expression)
	var near = _near_blinking(closed, _active(0.0, 0.0, expression))
	for i in len(rest):
		if _is_near(shaped_points[i], near) and _moves(i, closed):
			moving.append(i)

# Where blinking's and breathing's controls are on the doll in the pose of active,
# and how far around them to look for the points they move (in a layer's coordinates).
# closed is the same pose with the eyes closed and breathed in.
func _near_blinking(closed:Array, active:Array) -> Array:
	var from_screen = to_screen.affine_inverse()
	var near := []
	for entry in closed:
		if entry[0] is BodyControl and _blinks_or_breathes(entry[0]):
			var size = entry[0].reach * entry[0].global_scale.abs() * 1.5 + Vector2.ONE * NEAR_MARGIN
			near.append([from_screen * _shaped(entry[2], active), from_screen.basis_xform(size).abs()])
	return near

static func _is_near(spot:Vector2, near:Array) -> bool:
	for control in near:
		if ((spot - control[0]) / control[1]).length_squared() < 1.0:
			return true
	return false

# Whether blinking or breathing moves grid point i, with the controls active
# as _active() gives them with the eyes closed and breathed in
func _moves(i:int, active:Array) -> bool:
	var drawn = to_screen * rest[i]
	var moved = drawn
	for entry in active:
		if entry[0] == skeleton:
			break # the skeleton comes last and doesn't blink or breathe
		if _blinks_or_breathes(entry[0]) and entry[0].reaches(moved, entry[2]):
			return true
		moved = _step(entry, moved, drawn)
	return false

func _blinks_or_breathes(control) -> bool:
	return (can_blink and control.slider == blink_slider) or (can_breathe and control.slider == breathe_slider)

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
	_work_out_pose()
	var changed = _move_pose(delta)
	changed = _blink(delta) or changed
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

# Works out more of the pose asked for by show_expression(), for at most POSE_BUDGET
# each frame: where each grid point goes, which ones blinking and breathing move,
# and where swinging points hang. Then the doll starts moving to it.
func _work_out_pose() -> void:
	if next_face == null:
		return
	var from_screen = to_screen.affine_inverse()
	var stop_at = Time.get_ticks_usec() + POSE_BUDGET
	while len(next_points) < len(rest):
		next_points.append(from_screen * _shaped(to_screen * rest[len(next_points)], next_active))
		if len(next_points) % 32 == 0 and Time.get_ticks_usec() > stop_at:
			return
	# only points near blinking's and breathing's controls in the new pose can be moved by them
	var near = _near_blinking(next_closed, next_active)
	while next_checked < len(rest):
		if _is_near(next_points[next_checked], near) and _moves(next_checked, next_closed):
			next_moving.append(next_checked)
		next_checked += 1
		if next_checked % 32 == 0 and Time.get_ticks_usec() > stop_at:
			return
	while len(next_hanging) < len(swings):
		next_hanging.append(_hanging(swings[len(next_hanging)], next_points, next_active))
		if Time.get_ticks_usec() > stop_at:
			return
	_start_pose()

# Starts moving from the pose shown now (maybe part way through another move) to the new one
func _start_pose() -> void:
	expression_from = _face_now()
	expression = next_face
	next_face = null
	pose_from = shaped_points
	pose_to = next_points
	# both poses' moving points, until the move is done
	moving_after = next_moving
	var both := {}
	for i in moving:
		both[i] = true
	for i in next_moving:
		both[i] = true
	moving = PackedInt32Array(both.keys())
	for k in len(swings):
		swings[k].from = swings[k].targets
		swings[k].to = next_hanging[k]
	pose_clock = 0.0
	pose_time = maxf(next_seconds, 0.01)
	pose_snappy = next_snappy
	pose_weight = 0.0
	expression_started.emit()

# Moves the doll along towards its new pose. Returns true when it moved.
func _move_pose(delta:float) -> bool:
	if pose_time <= 0.0:
		return false
	pose_clock += delta
	if pose_clock >= pose_time:
		pose_time = 0.0
		pose_weight = 1.0
		expression_from = expression
		shaped_points = pose_to
		moving = moving_after
		for swing in swings:
			swing.targets = swing.to
		return true
	if pose_snappy:
		pose_weight = Tween.interpolate_value(0.0, 1.0, pose_clock, pose_time, Tween.TRANS_BACK, Tween.EASE_OUT)
	else:
		pose_weight = Tween.interpolate_value(0.0, 1.0, pose_clock, pose_time, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	shaped_points = _between(pose_from, pose_to, pose_weight)
	for swing in swings:
		swing.targets = _between(swing.from, swing.to, pose_weight)
	return true

static func _between(from:PackedVector2Array, to:PackedVector2Array, weight:float) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(len(to))
	for i in len(to):
		result[i] = from[i].lerp(to[i], weight)
	return result

# The pose shown now: part way from expression_from to expression while the doll moves
func _face_now() -> Dictionary:
	if pose_time <= 0.0:
		return expression
	var face := {}
	for slider in expression_from.keys() + expression.keys():
		face[slider] = lerpf(expression_from.get(slider, 0.0), expression.get(slider, 0.0), pose_weight)
	return face

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
