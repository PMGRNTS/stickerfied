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
# Parts drawn close together, such as an arm held a pixel or two from the hips, are told
# apart by looking at the body picture itself, not just the coarser map: the map never
# reaches across a gap in the picture, and the grid gets points along narrow gaps
# (gap_points()) so it can tear there.
#
# The doll is one flat picture, so a turned part can only stretch what is around it.
# Where the grid reaches across empty space between parts that turn differently (between
# the legs, or an arm drawn apart from the body), it tears instead (see tear()): each side
# goes with its own part, and the gap opens rather than smearing. Nothing was drawn under
# an arm held against the body, so keep the bones' turns small (see body_bone.gd).
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
# A grid triangle tears when it reaches out of the body and its points go with parts
# this different (0 to 2: 1 is one point going fully with a bone that another doesn't)
const TEAR := 0.6
# Distances are counted in tenths of a square, so diagonal steps (14) can be told apart
const STEP := 10
const DIAGONAL_STEP := 14
# Gaps in the body picture up to this many pixels wide get grid points along them
const NARROW_GAP := 8
# Steps to the neighboring squares: [x, y, length, which wall bit, whether that bit is kept
# on the neighbor rather than this square] (walls says which steps cross a gap)
const NEIGHBORS := [[1, 0, STEP, 1, false], [-1, 0, STEP, 1, true], [0, 1, STEP, 2, false], [0, -1, STEP, 2, true],
	[1, 1, DIAGONAL_STEP, 4, false], [-1, -1, DIAGONAL_STEP, 4, true], [-1, 1, DIAGONAL_STEP, 8, false], [1, -1, DIAGONAL_STEP, 8, true]]

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
var inside := PackedByteArray() # for each square of the map, 1 when its middle is on the body picture
# For each square, bits for its steps right (1), down (2), down right (4) and down left (8):
# set when the step crosses a gap in the body picture, from the body to the body
var walls := PackedByteArray()
var solid := PackedByteArray() # for each pixel of the body picture, 1 when it isn't see-through
var whole := PackedByteArray() # for each square of the map, 1 when no pixel of it is see-through
var solid_size := Vector2i.ZERO
var body_picture: Texture2D # the body picture the map was made from
var picture_size := Vector2.ONE # the size of the doll's images
# The bones that turn each point (on the doll as drawn) and how much, worked out from the map
# as points are asked about: point -> [PackedInt32Array bones, PackedFloat32Array weights].
# Bones that never turn are left out, so most of the doll (the head, the body) has none.
var mixes := {}
# Mixes kept at most, so points asked about only once don't pile up
const MAX_MIXES := 20000
# The mixes of the grid points off the body and those added where the grid tears
# (see tear()): grid point -> mix
var torn := {}


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
	body_picture = picture
	picture_size = image_size
	columns = ceili(image_size.x / CELL)
	rows = ceili(image_size.y / CELL)
	square_bones = PackedInt32Array()
	square_bones.resize(columns * rows * 3)
	square_bones.fill(-1)
	square_weights = PackedFloat32Array()
	square_weights.resize(columns * rows * 3)
	inside = PackedByteArray()
	walls = PackedByteArray()
	solid = PackedByteArray()
	if bones.is_empty() or picture == null:
		return
	_read_solid(picture)
	if solid.is_empty():
		return
	inside = _inside()
	whole = _whole()
	walls = _walls()

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

# Reads which pixels of the body picture aren't see-through
func _read_solid(picture:Texture2D) -> void:
	var image = picture.get_image()
	if image == null:
		return
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	solid_size = image.get_size()
	var data = image.get_data()
	solid.resize(solid_size.x * solid_size.y)
	for i in len(solid):
		solid[i] = 1 if data[i * 4 + 3] > 127 else 0

# Whether the body picture isn't see-through at spot (in a layer's coordinates)
func _solid_at(spot:Vector2) -> bool:
	var pixel = Vector2i(((spot - corner) / picture_size * Vector2(solid_size)).floor())
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= solid_size.x or pixel.y >= solid_size.y:
		return false
	return solid[pixel.y * solid_size.x + pixel.x] == 1

# Whether going straight from one spot to another (in a layer's coordinates) crosses a gap:
# from the body, over see-through pixels, and back onto the body
func _crosses_gap(from:Vector2, to:Vector2) -> bool:
	var pixel = picture_size / Vector2(solid_size)
	var samples = ceili(from.distance_to(to) / minf(pixel.x, pixel.y) * 2.0) + 1 # every half pixel, so no gap is stepped over
	var on_body = false
	var left_body = false
	for i in samples + 1:
		if _solid_at(from.lerp(to, float(i) / samples)):
			if left_body:
				return true
			on_body = true
		elif on_body:
			left_body = true
	return false

# The middle of a square, in a layer's coordinates
func _middle_of(square:int) -> Vector2:
	return corner + (Vector2(square % columns, square / columns) + Vector2(0.5, 0.5)) * CELL

# For each square of the map, whether its middle is on the body picture
func _inside() -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(columns * rows)
	for square in columns * rows:
		result[square] = 1 if _solid_at(_middle_of(square)) else 0
	return result

# For each square of the map, whether none of its pixels are see-through (no gap can cross it)
func _whole() -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(columns * rows)
	var pixel = Vector2(solid_size) / picture_size * CELL # the square's size in pixels
	for square in columns * rows:
		var first = Vector2i((Vector2(square % columns, square / columns) * pixel).floor())
		var last = Vector2i((Vector2(square % columns + 1, square / columns + 1) * pixel).ceil()).min(solid_size)
		var all_solid = first.x < last.x and first.y < last.y
		for y in range(first.y, last.y):
			for x in range(first.x, last.x):
				if solid[y * solid_size.x + x] == 0:
					all_solid = false
					break
			if not all_solid:
				break
		result[square] = 1 if all_solid else 0
	return result

# Whether the map squares around spot (in a layer's coordinates) are all whole, so nothing
# near it can cross a gap
func _whole_around(spot:Vector2) -> bool:
	var at = Vector2i(((spot - corner) / CELL - Vector2(0.5, 0.5)).floor())
	for step in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var x = at.x + step.x
		var y = at.y + step.y
		if x < 0 or y < 0 or x >= columns or y >= rows or whole[y * columns + x] == 0:
			return false
	return true

# For each square of the map, which of its steps cross a gap in the body picture (see walls)
func _walls() -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(columns * rows)
	for square in columns * rows:
		if inside[square] == 0:
			continue
		var x = square % columns
		var y = square / columns
		var bits = 0
		for neighbor in NEIGHBORS:
			var nx = x + neighbor[0]
			var ny = y + neighbor[1]
			if neighbor[4] or nx < 0 or ny >= rows or nx >= columns:
				continue
			var next = ny * columns + nx
			# a step only crosses the squares it goes between (and, going diagonally, the corner
			# of the two others), so between whole squares there's no gap to cross
			if inside[next] == 0 or _whole_around((_middle_of(square) + _middle_of(next)) / 2.0):
				continue
			if _crosses_gap(_middle_of(square), _middle_of(next)):
				bits |= neighbor[3]
		result[square] = bits
	return result

# Whether the step from square to its neighbor next crosses a gap (neighbor is from NEIGHBORS)
func _walled(square:int, next:int, neighbor:Array) -> bool:
	return walls[next if neighbor[4] else square] & neighbor[3] != 0

# Spots along the narrow gaps in the body picture, such as between an arm and the hips
# (in a layer's coordinates): along the middle of each gap and its edges on both sides,
# for the grid to have points there, so it tears along the gap
func gap_points() -> PackedVector2Array:
	var spots := PackedVector2Array()
	if solid.is_empty():
		return spots
	var pixel = picture_size / Vector2(solid_size)
	var widest = ceili(NARROW_GAP / minf(pixel.x, pixel.y))
	var every = maxi(1, roundi(2.0 / pixel.y))
	# across each row, and down each column
	for across in [true, false]:
		var lines = solid_size.y if across else solid_size.x
		var length = solid_size.x if across else solid_size.y
		for line in range(0, lines, every):
			var gap_from = -1
			var was_solid = false
			for i in length:
				var here = solid[line * solid_size.x + i] if across else solid[i * solid_size.x + line]
				if here == 1:
					if was_solid == false and gap_from >= 0 and i - gap_from <= widest:
						for along in [gap_from - 0.5, (gap_from + i) / 2.0, i + 0.5]:
							var at = Vector2(along, line + 0.5) if across else Vector2(line + 0.5, along)
							spots.append(corner + at * pixel)
					was_solid = true
					gap_from = -1
				else:
					if was_solid:
						gap_from = i
					was_solid = false
	return spots

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
	# only those on the body joined to the bone's line without crossing a gap, so an arm
	# held close to the body doesn't take the hips along
	var near := {}
	var joined := []
	for square in squares:
		if inside[square] == 0:
			continue
		near[square] = true
		var middle = Vector2(square % columns, square / columns) + Vector2(0.5, 0.5)
		if middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, start, finish)) <= 0.75:
			joined.append(square)
	if joined.is_empty():
		return squares
	var reached := {}
	for square in joined:
		reached[square] = true
	while not joined.is_empty():
		var square = joined.pop_back()
		for neighbor in NEIGHBORS:
			var nx = square % columns + neighbor[0]
			var ny = square / columns + neighbor[1]
			var next = ny * columns + nx
			if nx < 0 or ny < 0 or nx >= columns or ny >= rows or reached.has(next) or not near.has(next):
				continue
			if _walled(square, next, neighbor):
				continue
			reached[next] = true
			joined.append(next)
	return PackedInt32Array(reached.keys())

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
			for neighbor in NEIGHBORS:
				var nx = x + neighbor[0]
				var ny = y + neighbor[1]
				if nx < 0 or ny < 0 or nx >= columns or ny >= rows:
					continue
				var next = ny * columns + nx
				# across empty space, or across a gap between two parts, costs more
				var through = here_inside and inside[next] == 1 and not _walled(square, next, neighbor)
				var cost = neighbor[2] if through else neighbor[2] * OUTSIDE_COST
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
# sliders moved it. index is the grid point it is, if any: points added where the grid
# tears go with their own part.
func posed(point:Vector2, drawn:Vector2, moves:Array, index := -1) -> Vector2:
	var mix = torn.get(index)
	if mix == null:
		mix = _kept_mix(drawn)
	var turning: PackedInt32Array = mix[0]
	if turning.is_empty():
		return point
	var weights: PackedFloat32Array = mix[1]
	var result = point
	for k in len(turning):
		result += weights[k] * (moves[turning[k]] * point - point)
	return result

# _mix(drawn), kept for the next time it's asked about
func _kept_mix(drawn:Vector2) -> Array:
	var mix = mixes.get(drawn)
	if mix == null:
		mix = _mix(drawn)
		if len(mixes) >= MAX_MIXES:
			mixes.clear()
		mixes[drawn] = mix
	return mix

# Whether the squares all go with the same bones by the same amounts (nothing to leave out)
func _all_alike(squares:Array) -> bool:
	var first = squares[0] * 3
	for square in squares:
		for k in 3:
			if square_bones[square * 3 + k] != square_bones[first + k] \
					or absf(square_weights[square * 3 + k] - square_weights[first + k]) > 0.01:
				return false
	return true

# Which turning bones a point on the doll as drawn goes with, and how much:
# blended from the four squares of the map around it, so the turn changes smoothly,
# or with blend off, just from the square it is on. For a point on the body, squares off
# the body or across a gap in the body picture are left out, so the hips next to an arm
# stay with the hips.
func _mix(drawn:Vector2, blend := true) -> Array:
	var found := {}
	if not square_bones.is_empty():
		var here = from_screen * drawn
		var spot = (here - corner) / CELL - Vector2(0.5, 0.5)
		var first = Vector2i(spot.floor())
		var part = spot - Vector2(first)
		if not blend:
			first = Vector2i((spot + Vector2(0.5, 0.5)).floor())
			part = Vector2.ZERO
		var shares := {}
		for step in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var at = (first + step).clamp(Vector2i.ZERO, Vector2i(columns - 1, rows - 1))
			var share = (part.x if step.x == 1 else 1.0 - part.x) * (part.y if step.y == 1 else 1.0 - part.y)
			if share > 0.0:
				shares[at.y * columns + at.x] = shares.get(at.y * columns + at.x, 0.0) + share
		# a point on the body only takes after squares on the body on its own side of any gap
		var kept = shares.keys()
		if not _whole_around(here) and not _all_alike(kept):
			var on_body = _solid_at(here)
			kept = kept.filter(func(square):
				return not (on_body and inside[square] == 0) and not _crosses_gap(here, _middle_of(square)))
		if kept.is_empty():
			kept = shares.keys()
		var total = kept.reduce(func(sum, square): return sum + shares[square], 0.0)
		for square in kept:
			for k in 3:
				var bone = square_bones[square * 3 + k]
				if bone < 0:
					break
				if bones[bone].slider != "":
					found[bone] = found.get(bone, 0.0) + shares[square] / total * square_weights[square * 3 + k]
	return [PackedInt32Array(found.keys()), PackedFloat32Array(found.values())]


# Tears the grid where it reaches across empty space between parts that turn differently,
# such as between the legs, so the gap opens when they turn instead of stretching.
# points are the grid's points on the doll as drawn (on the screen), and triangles which
# points make each triangle. A triangle that reaches off the body to points going with
# another part gets copies of those points that go with its own part (that of its points
# on the body, or of its middle). A triangle reaching across a narrow gap from one part of
# the body to another (an arm held close to the hips) goes wholly with the part its middle
# is on, or, with its middle in the gap, the part its nearest point is on.
# Returns [copies, triangles, mends]: copies is the point each new grid point copies (the
# new points come after points), triangles the torn triangles, and mends, for each torn
# triangle whose middle is off the body picture, [where it is in triangles, its points before
# tearing, its middle on the screen]. A layer covering that middle, such as a skirt
# between the legs, draws it whole, so it bends like cloth instead of splitting.
func tear(points:PackedVector2Array, triangles:PackedInt32Array) -> Array:
	torn.clear()
	var copies := PackedInt32Array()
	var mends := []
	if inside.is_empty() or not has_turning_bones():
		return [copies, triangles, mends]
	var point_mixes := []
	var on_body := PackedByteArray()
	for i in len(points):
		on_body.append(1 if _on_body(points[i]) else 0)
		if on_body[i] == 1:
			point_mixes.append(_kept_mix(points[i]))
		else:
			# off the body, points go with just the part they're nearest, not a blend of the
			# parts on both sides of a narrow gap, so the grid tears there instead of stretching
			point_mixes.append(_rounded(_mix(points[i], false)))
			torn[i] = point_mixes[i]
	var image = body_picture.get_image() if body_picture else null
	if image and image.is_compressed():
		image.decompress()
	var made := {} # "point mix" -> its copy
	var result = triangles.duplicate()
	for t in range(0, len(triangles), 3):
		var corners = [triangles[t], triangles[t + 1], triangles[t + 2]]
		var apart = 0.0
		for k in 3:
			apart = maxf(apart, _difference(point_mixes[corners[k]], point_mixes[corners[(k + 1) % 3]]))
		if apart < TEAR:
			continue
		var middle = (points[corners[0]] + points[corners[1]] + points[corners[2]]) / 3.0
		var on = corners.filter(func(i): return on_body[i] == 1)
		var across = false # whether it reaches across a gap from one part of the body to another
		if len(on) == 3:
			for k in 3:
				across = across or _crosses_gap(from_screen * points[on[k]], from_screen * points[on[(k + 1) % 3]])
			if not across:
				continue
		var mix
		if across:
			var side = corners[0]
			for i in corners:
				if points[i].distance_to(middle) < points[side].distance_to(middle):
					side = i
			mix = _rounded(_mix(middle) if _on_body(middle) else point_mixes[side])
		else:
			mix = _rounded(_mix(middle) if on.is_empty() else _average(on.map(func(i): return point_mixes[i])))
		for k in 3:
			var i = corners[k]
			if _difference(point_mixes[i], mix) < 0.05:
				continue
			# points on the body keep their own blend, unless they're across a gap from the part
			if on_body[i] == 1 and not (across and _difference(point_mixes[i], mix) >= TEAR / 2.0):
				continue
			var key = "%d %s" % [i, mix]
			if not made.has(key):
				made[key] = len(points) + len(copies)
				torn[made[key]] = mix
				copies.append(i)
			result[t + k] = made[key]
		if image and not _opaque(image, middle):
			mends.append([t, PackedInt32Array(corners), middle])
	return [copies, result, mends]

# Whether point (on the screen) is on the body picture
func _on_body(point:Vector2) -> bool:
	return _solid_at(from_screen * point)

# Whether the body picture image isn't see-through at point (on the screen). The map is
# coarser, so this tells the body's own outline from a skirt between the legs (see tear()).
func _opaque(image:Image, point:Vector2) -> bool:
	var uv = (from_screen * point - corner) / picture_size
	return image.get_pixelv(Vector2i(uv * Vector2(image.get_size())).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)).a > 0.5

# How differently two mixes turn: the sum of how much more each bone turns one than the other
static func _difference(a:Array, b:Array) -> float:
	var shares := {}
	for k in len(a[0]):
		shares[a[0][k]] = a[1][k]
	for k in len(b[0]):
		shares[b[0][k]] = shares.get(b[0][k], 0.0) - b[1][k]
	return shares.values().reduce(func(sum, share): return sum + absf(share), 0.0)

static func _average(list:Array) -> Array:
	var shares := {}
	for mix in list:
		for k in len(mix[0]):
			shares[mix[0][k]] = shares.get(mix[0][k], 0.0) + mix[1][k] / len(list)
	return [PackedInt32Array(shares.keys()), PackedFloat32Array(shares.values())]

# The mix with its shares rounded, so triangles side by side on one part share their copies
static func _rounded(mix:Array) -> Array:
	var turning := PackedInt32Array()
	var weights := PackedFloat32Array()
	for k in len(mix[0]):
		var weight = snappedf(mix[1][k], 0.05)
		if weight > 0.0:
			turning.append(mix[0][k])
			weights.append(weight)
	return [turning, weights]
