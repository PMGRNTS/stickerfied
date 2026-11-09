# The doll's skeleton: bones (body_bone.gd) that turn parts of the doll at their joints,
# like an arm at the shoulder or a leg at the hip. Put this node under BodyShaper,
# and the bones under it.
#
# Each part of the doll goes with the bone it belongs to. That is worked out from the
# body picture (the first layer after the backgrounds): a part belongs to the bone it is
# nearest to going through the doll, not across empty space, so a hand held next to the
# head still goes with its arm. Where two parts meet (at the shoulder), they bend
# smoothly from one bone's turn to the other's. What is outside the body picture
# (hair, a wide skirt, stickers) goes with the nearest part of the body.
#
# The body shaper (body_shaper.gd) turns the bones after the Body menu's other sliders,
# so the bones turn the reshaped doll: a longer arm still turns at its shoulder.
# All layers and stickers bend along, like with the other sliders.

extends Node2D

const BodyBone = preload("res://script/body_bone.gd")

# Pixels of the doll's images per square of the map of which bone each part goes with
const CELL := 4.0
# How far (in pixels) from where two parts meet they bend from one bone's turn to the other's
const BLEND := 14.0
# Going across empty space counts as this much further than going through the doll
const OUTSIDE_COST := 6
# How far (in pixels) from a bone that turns its parts are looked for
const REACH := 150.0
# Distances are counted in tenths of a square, so diagonal steps (14) can be told apart
const STEP := 10
const DIAGONAL_STEP := 14

# The body shaper looks at each step's slider for blinking; the skeleton doesn't blink
var slider := ""

var bones := [] # every bone, each one after the bone it hangs from
var parents := PackedInt32Array() # for each bone, the index of the bone it hangs from, or -1

var columns := 0
var rows := 0
var corner := Vector2.ZERO # the map's top-left corner, in a doll layer's coordinates
var from_screen := Transform2D()
# For each square of the map, up to 3 bones (-1 for none) and how much it goes with each
var square_bones := PackedInt32Array()
var square_weights := PackedFloat32Array()
var built_for := "" # what the map was made for, so it isn't made again for nothing
# The bones that turn each point (on the doll as drawn) and how much, worked out from the map
# as points are asked about: point -> [PackedInt32Array bones, PackedFloat32Array weights].
# Bones that never turn are left out, so most of the doll (the head, the body) has none.
var mixes := {}
# Mixes kept at most, so points asked about only once don't pile up
const MAX_MIXES := 20000


# Finds the bones under this node
func collect() -> void:
	bones = []
	parents = PackedInt32Array()
	_collect(self, -1)

func _collect(node:Node, parent:int) -> void:
	for child in node.get_children():
		if child is BodyBone:
			bones.append(child)
			parents.append(parent)
			_collect(child, len(bones) - 1)

func has_turning_bones() -> bool:
	return bones.any(func(bone): return bone.slider != "")


# Makes the map of which bone each part of the doll goes with, from the body picture.
# image_corner and image_size are where the doll's images are in a layer's coordinates.
func build(picture:Texture2D, image_corner:Vector2, image_size:Vector2, layer_to_screen:Transform2D) -> void:
	collect()
	var key = "%s %s %s" % [picture.get_rid() if picture else "", layer_to_screen,
		bones.map(func(bone): return [bone.global_position, bone.tip()])]
	if key == built_for:
		return
	built_for = key
	mixes.clear()
	from_screen = layer_to_screen.affine_inverse()
	corner = image_corner
	columns = ceili(image_size.x / CELL)
	rows = ceili(image_size.y / CELL)
	square_bones = PackedInt32Array()
	square_bones.resize(columns * rows * 3)
	square_bones.fill(-1)
	square_weights = PackedFloat32Array()
	square_weights.resize(columns * rows * 3)
	if bones.is_empty() or picture == null:
		return
	var inside = _inside(picture)
	if inside.is_empty():
		return

	# how far each square is from each bone, going through the doll
	var distances := []
	for bone in bones:
		var limit = -1 if bone.slider == "" else roundi(REACH / CELL * STEP)
		distances.append(_distances(_squares_on(bone), inside, limit))

	var blend = BLEND / CELL * STEP
	for square in columns * rows:
		var nearest = -1
		for b in len(bones):
			var distance = distances[b][square]
			if distance >= 0 and (nearest < 0 or distance < nearest):
				nearest = distance
		if nearest < 0:
			continue
		# bones about as near as the nearest share the square, fading out with distance
		var found := []
		for b in len(bones):
			var distance = distances[b][square]
			if distance < 0:
				continue
			var weight = smoothstep(0.0, 1.0, 1.0 - (distance - nearest) / blend)
			if weight > 0.0:
				found.append([weight, b])
		found.sort_custom(func(a, b): return a[0] > b[0])
		found = found.slice(0, 3)
		var total = found.reduce(func(sum, entry): return sum + entry[0], 0.0)
		for k in len(found):
			square_bones[square * 3 + k] = found[k][1]
			square_weights[square * 3 + k] = found[k][0] / total

# For each square of the map, whether it is on the body picture
func _inside(picture:Texture2D) -> PackedByteArray:
	var image = picture.get_image()
	if image == null:
		return PackedByteArray()
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(columns, rows, Image.INTERPOLATE_BILINEAR)
	var inside := PackedByteArray()
	inside.resize(columns * rows)
	for y in rows:
		for x in columns:
			inside[y * columns + x] = 1 if image.get_pixel(x, y).a > 0.25 else 0
	return inside

# The squares a bone covers: those within its Width of the line from its joint to its end.
# Everything there goes fully with the bone, so a wide torso holds the body still
# right up to the shoulders, instead of the arms pulling at it.
func _squares_on(bone:Node2D) -> PackedInt32Array:
	var start = (from_screen * bone.global_position - corner) / CELL
	var finish = (from_screen * bone.tip() - corner) / CELL
	var width = bone.width * bone.global_scale.x / from_screen.affine_inverse().get_scale().x / CELL
	var first = Vector2i((start.min(finish) - Vector2.ONE * width).floor()).max(Vector2i.ZERO)
	var last = Vector2i((start.max(finish) + Vector2.ONE * width).ceil()).min(Vector2i(columns - 1, rows - 1))
	var squares := PackedInt32Array()
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var middle = Vector2(x, y) + Vector2(0.5, 0.5)
			if middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, start, finish)) <= maxf(width, 0.5):
				squares.append(y * columns + x)
	if squares.is_empty():
		var spot = Vector2i(start.floor()).clamp(Vector2i.ZERO, Vector2i(columns - 1, rows - 1))
		squares.append(spot.y * columns + spot.x)
	return squares

# How far every square is from the sources, going through the doll (across empty space
# costs more), or -1 for squares further than limit (-1 for no limit).
# Dijkstra's shortest paths, with the squares waiting in a ring of buckets by distance.
func _distances(sources:PackedInt32Array, inside:PackedByteArray, limit:int) -> PackedInt32Array:
	var distance := PackedInt32Array()
	distance.resize(columns * rows)
	distance.fill(-1)
	var ring = DIAGONAL_STEP * OUTSIDE_COST + 1
	var buckets := []
	for i in ring:
		buckets.append([])
	for source in sources:
		distance[source] = 0
		buckets[0].append(source)
	var waiting = len(sources)
	var reached = 0
	var neighbors = [Vector3i(1, 0, STEP), Vector3i(-1, 0, STEP), Vector3i(0, 1, STEP), Vector3i(0, -1, STEP),
		Vector3i(1, 1, DIAGONAL_STEP), Vector3i(-1, 1, DIAGONAL_STEP), Vector3i(1, -1, DIAGONAL_STEP), Vector3i(-1, -1, DIAGONAL_STEP)]
	while waiting > 0:
		var bucket: Array = buckets[reached % ring]
		buckets[reached % ring] = []
		for square in bucket:
			waiting -= 1
			if distance[square] != reached:
				continue # reached sooner another way
			var x = square % columns
			var y = square / columns
			var here_inside = inside[square] == 1
			for neighbor in neighbors:
				var nx = x + neighbor.x
				var ny = y + neighbor.y
				if nx < 0 or ny < 0 or nx >= columns or ny >= rows:
					continue
				var next = ny * columns + nx
				var cost = neighbor.z if here_inside and inside[next] == 1 else neighbor.z * OUTSIDE_COST
				var further = reached + cost
				if (limit >= 0 and further > limit) or (distance[next] >= 0 and distance[next] <= further):
					continue
				distance[next] = further
				buckets[further % ring].append(next)
				waiting += 1
		reached += 1
	return distance


# Where each bone's turn moves points: one Transform2D for each bone, turning at its joint
# by its slider in shown (slider name -> -1..1), after the bones it hangs from.
# joints are where the joints are now, after the other sliders reshaped the doll.
# Returns [] when no bone is turned.
func pose(shown:Dictionary, joints:Array) -> Array:
	var turned = false
	var moves := []
	for i in len(bones):
		var angle = bones[i].angle_for(float(shown.get(bones[i].slider, 0.0))) if bones[i].slider != "" else 0.0
		turned = turned or angle != 0.0
		var base = moves[parents[i]] if parents[i] >= 0 else Transform2D.IDENTITY
		var around_joint = Transform2D(angle, joints[i]) * Transform2D(0.0, -joints[i])
		moves.append(base * around_joint)
	return moves if turned else []

# Where point goes when the bones turn by moves (from pose()). drawn is where the point
# is on the doll as drawn, which says which bones it goes with; point is where the other
# sliders moved it.
func posed(point:Vector2, drawn:Vector2, moves:Array) -> Vector2:
	var mix = mixes.get(drawn)
	if mix == null:
		mix = _mix(drawn)
		if len(mixes) >= MAX_MIXES:
			mixes.clear()
		mixes[drawn] = mix
	var turning: PackedInt32Array = mix[0]
	if turning.is_empty():
		return point
	var weights: PackedFloat32Array = mix[1]
	var result = point
	for k in len(turning):
		result += weights[k] * (moves[turning[k]] * point - point)
	return result

# Which turning bones a point on the doll as drawn goes with, and how much:
# blended from the four squares of the map around it, so the turn changes smoothly
func _mix(drawn:Vector2) -> Array:
	var found := {}
	if not square_bones.is_empty():
		var spot = (from_screen * drawn - corner) / CELL - Vector2(0.5, 0.5)
		var first = Vector2i(spot.floor())
		var part = spot - Vector2(first)
		for step in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var at = (first + step).clamp(Vector2i.ZERO, Vector2i(columns - 1, rows - 1))
			var share = (part.x if step.x == 1 else 1.0 - part.x) * (part.y if step.y == 1 else 1.0 - part.y)
			if share <= 0.0:
				continue
			var square = (at.y * columns + at.x) * 3
			for k in 3:
				var bone = square_bones[square + k]
				if bone < 0:
					break
				if bones[bone].slider != "":
					found[bone] = found.get(bone, 0.0) + share * square_weights[square + k]
	return [PackedInt32Array(found.keys()), PackedFloat32Array(found.values())]
