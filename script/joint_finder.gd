# Finds the joints of the doll's skeleton (body_bone.gd) on a body picture, for bodies
# that aren't shaped like the one the bones were placed on (see body_shaper.gd):
#   find(): looks at the body's outline. Going through the body from the middle of its
#     trunk, the parts that stick out furthest are the head, the arms and the legs.
#     The feet are the two lowest, the head the one with a big round end, and the arms
#     the two longest others. Along each limb, the shoulder or hip is where the limb
#     gets as wide as the trunk, and the elbow or knee about halfway to the hand or foot.
#     The neck is the narrowest place between the head and the trunk.
#   standard(): where the joints usually are on a doll standing straight and facing forward,
#     sized to the doll.
# Both return {BodyBone.Joint: {"at": Vector2, "width": float}}, in pixels of the picture
# (width is about half as wide as the part is there). Joints that can't be found
# are where standard() puts them; {} when the picture has nothing on it.

extends RefCounted

const BodyBone = preload("res://script/body_bone.gd")
const J = BodyBone.Joint

# The picture is looked at this many squares tall
const ROWS := 200
# Distances are counted in tenths of a square, so diagonal steps (14) can be told apart
const STEP := 10
const DIAGONAL_STEP := 14
# Paths are pulled towards the middle of the body: a step next to the edge costs this much
# more (in thirds of a square of distance from the edge), so they run down the middle of each limb
const PULL := 12
# A part sticking out at least this much of the figure's height counts as a limb or the head
const SHORTEST_LIMB := 0.12
# Where the elbow and knee are, from the shoulder or hip (0) to the hand or foot (1)
const ELBOW := 0.45
const KNEE := 0.5
# Hips are no lower than this far down the figure, for legs drawn touching down to the knees
const LOWEST_HIPS := 0.64
# A limb meets the trunk where it gets this wide, compared to the widest part of the trunk
const TRUNK_WIDTH := 0.6

static func find(picture:Image) -> Dictionary:
	var look = _look(picture)
	if look.is_empty():
		return {}
	var result = _standard(look)
	var columns: int = look.columns
	var inside: PackedByteArray = look.inside
	var edge = _edge_distances(look)
	var height: float = look.bottom - look.top + 1

	# the middle of the trunk: its widest place, a third to two thirds of the way down
	var root = -1
	for y in range(look.top + int(height * 0.3), look.top + int(height * 0.62) + 1):
		for x in columns:
			var square = y * columns + x
			if inside[square] == 1 and (root < 0 or edge[square] > edge[root]):
				root = square
	if root < 0:
		return result
	var reached = _paths(look, root, edge)
	var parent: PackedInt32Array = reached[1]
	var distance: PackedInt32Array = reached[2] # how far along its path each square is, in tenths of a square

	# the parts that stick out: the ends of the longest paths from the trunk
	var ends = _ends(look, distance, parent, root, height * SHORTEST_LIMB * STEP)
	var root_spot = _spot(look, root)
	var trunk_edge = float(edge[root])

	# feet: the two lowest ends, below the middle of the trunk
	var low = ends.filter(func(end): return _spot(look, end.tip).y > root_spot.y + height * 0.2)
	low.sort_custom(func(a, b): return _spot(look, a.tip).y > _spot(look, b.tip).y)
	var feet = low.slice(0, 2)
	var others = ends.filter(func(end): return not end in feet)

	# head: the end with the biggest round part near it
	var head = null
	var head_middle = -1
	for end in others:
		var path = _path(end.tip, parent)
		var biggest = -1
		for square in path:
			if distance[square] >= distance[end.tip] - end.length * 0.4 and (biggest < 0 or edge[square] > edge[biggest]):
				biggest = square
		if head == null or edge[biggest] > edge[head_middle]:
			head = end
			head_middle = biggest
	if head != null:
		others.erase(head)
		var head_spot = _spot(look, head_middle)
		var head_size = edge[head_middle] / 3.0
		# bumps on the head (such as hair) aren't arms
		others = others.filter(func(end): return _spot(look, end.tip).distance_to(head_spot) > head_size * 1.3)
		# the neck: the narrowest place between the trunk and the middle of the head
		var path = _path(head_middle, parent)
		var neck = -1
		for square in path:
			var along = float(distance[square]) / maxf(distance[head_middle], 1)
			if along > 0.25 and along < 1.0 and (neck < 0 or edge[square] < edge[neck]):
				neck = square
		if neck >= 0:
			result[J.NECK].at = _spot(look, neck) * look.scale

	# arms: the two longest other ends
	others.sort_custom(func(a, b): return a.length > b.length)
	var arms = []
	for end in others.slice(0, 2):
		arms.append(_limb(look, end, distance, parent, edge, trunk_edge, ELBOW))
	if len(arms) == 2 and arms[0].base.x > arms[1].base.x:
		arms.reverse()
	if len(arms) == 1 and arms[0].base.x > root_spot.x:
		arms.push_front(null) # only the right arm was found
	_put(result, arms, [[J.LEFT_SHOULDER, J.LEFT_ELBOW, J.LEFT_HAND], [J.RIGHT_SHOULDER, J.RIGHT_ELBOW, J.RIGHT_HAND]], look)

	var legs = feet.map(func(end): return _limb(look, end, distance, parent, edge, trunk_edge, KNEE))
	if len(legs) == 2 and legs[0].tip.x > legs[1].tip.x:
		legs.reverse()
	if len(legs) == 2:
		_find_hips(look, legs)
		for leg in legs:
			leg.base.y = minf(leg.base.y, look.top + height * LOWEST_HIPS)
			leg.middle = _between(leg, KNEE)
		_put(result, legs, [[J.LEFT_HIP, J.LEFT_KNEE, J.LEFT_FOOT], [J.RIGHT_HIP, J.RIGHT_KNEE, J.RIGHT_FOOT]], look)
		# the torso starts a little above between the hips
		var hips = (legs[0].base + legs[1].base) / 2.0 * look.scale
		result[J.PELVIS].at = hips.lerp(result[J.NECK].at, 0.2)
	result[J.PELVIS].width = trunk_edge / 3.0 * 0.75 * look.scale.x
	result[J.NECK].width = result[J.PELVIS].width
	return result

static func standard(picture:Image) -> Dictionary:
	var look = _look(picture)
	return {} if look.is_empty() else _standard(look)

# Where the joints usually are on a doll standing straight and facing forward
static func _standard(look:Dictionary) -> Dictionary:
	var height = float(look.bottom - look.top + 1)
	var middle = float(look.middle)
	var spots = {
		J.NECK: [0.0, 0.13, 0.052], J.PELVIS: [0.0, 0.46, 0.052],
		J.LEFT_SHOULDER: [-0.075, 0.21, 0.02], J.LEFT_ELBOW: [-0.113, 0.37, 0.016], J.LEFT_HAND: [-0.157, 0.56, 0.016],
		J.RIGHT_SHOULDER: [0.075, 0.21, 0.02], J.RIGHT_ELBOW: [0.113, 0.37, 0.016], J.RIGHT_HAND: [0.157, 0.56, 0.016],
		J.LEFT_HIP: [-0.045, 0.5, 0.024], J.LEFT_KNEE: [-0.035, 0.68, 0.018], J.LEFT_FOOT: [-0.028, 0.99, 0.018],
		J.RIGHT_HIP: [0.045, 0.5, 0.024], J.RIGHT_KNEE: [0.035, 0.68, 0.018], J.RIGHT_FOOT: [0.028, 0.99, 0.018]}
	var result := {}
	for joint in spots:
		var spot = spots[joint]
		var at = Vector2(middle + spot[0] * height, look.top + spot[1] * height) + Vector2(0.5, 0.5)
		result[joint] = {"at": at * look.scale, "width": spot[2] * height * look.scale.x}
	return result

# Puts found limbs' joints in result: limbs (null for one not found) and their joints, left first
static func _put(result:Dictionary, limbs:Array, joints:Array, look:Dictionary) -> void:
	for i in mini(len(limbs), 2):
		if limbs[i] == null:
			continue
		var width = limbs[i].width * look.scale.x
		result[joints[i][0]] = {"at": limbs[i].base * look.scale, "width": width}
		result[joints[i][1]] = {"at": limbs[i].middle * look.scale, "width": width * 0.9}
		result[joints[i][2]] = {"at": limbs[i].tip * look.scale, "width": width * 0.9}

# A limb, from an end: where it meets the trunk (base), its middle joint (at middle_at of
# the way from the base to the tip), its tip, and its width, in squares
static func _limb(look:Dictionary, end:Dictionary, distance:PackedInt32Array, parent:PackedInt32Array,
		edge:PackedInt32Array, trunk_edge:float, middle_at:float) -> Dictionary:
	var path = _path(end.tip, parent) # from the tip to the middle of the trunk
	var outer := []
	for square in path:
		if distance[square] >= distance[end.tip] - end.length * 0.6:
			outer.append(edge[square])
	outer.sort()
	var width = outer[len(outer) / 2] if not outer.is_empty() else 3
	# the limb meets the trunk where it gets about as wide as the trunk
	var base = end.stop
	for square in path:
		if distance[end.tip] - distance[square] > end.length * 0.35 and edge[square] > maxf(trunk_edge * TRUNK_WIDTH, width * 1.5):
			base = square
			break
	var wanted = distance[base] + middle_at * (distance[end.tip] - distance[base])
	var middle = base
	for square in path:
		if distance[square] < distance[base]:
			break
		if absi(distance[square] - wanted) < absi(distance[middle] - wanted):
			middle = square
	return {"base": _spot(look, base), "middle": _spot(look, middle), "tip": _spot(look, end.tip),
		"width": width / 3.0, "path": path.map(func(square): return _spot(look, square)),
		"lengths": path.map(func(square): return distance[square])}

# The place on a limb's path middle_at of the way along it from its base to its tip
static func _between(limb:Dictionary, middle_at:float) -> Vector2:
	var nearest = 0
	for i in len(limb.path):
		if limb.path[i].distance_to(limb.base) < limb.path[nearest].distance_to(limb.base):
			nearest = i
	var wanted = lerpf(limb.lengths[nearest], limb.lengths[0], middle_at)
	var found = 0
	for i in len(limb.path):
		if absf(limb.lengths[i] - wanted) < absf(limb.lengths[found] - wanted):
			found = i
	return limb.path[found]

# Puts the hips of two legs (left first) at the crotch, where the legs part: the highest row
# with a gap between the middles of the two legs. Each hip is in the middle of its leg there,
# a little above.
static func _find_hips(look:Dictionary, legs:Array) -> void:
	var middles := [{}, {}] # for each leg, row -> where its middle is on that row
	for i in 2:
		for spot in legs[i].path:
			if not middles[i].has(int(spot.y)):
				middles[i][int(spot.y)] = spot.x
	var rows = middles[0].keys().filter(func(row): return middles[1].has(row))
	rows.sort()
	for row in rows:
		var from = int(minf(middles[0][row], middles[1][row]))
		var to = int(maxf(middles[0][row], middles[1][row]))
		for x in range(from, to + 1):
			if look.inside[row * look.columns + x] == 0:
				for i in 2:
					legs[i].base = Vector2(middles[i][row], row - legs[i].width * 0.5)
				return


# The picture as squares: which are on the body (only its biggest piece), and where it is
static func _look(picture:Image) -> Dictionary:
	if picture == null or picture.is_empty():
		return {}
	var image = picture.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var rows = mini(ROWS, image.get_height())
	var columns = maxi(1, roundi(image.get_width() * float(rows) / image.get_height()))
	var scale = Vector2(image.get_size()) / Vector2(columns, rows) # pixels per square
	image.resize(columns, rows, Image.INTERPOLATE_BILINEAR)
	var solid := PackedByteArray()
	solid.resize(columns * rows)
	for y in rows:
		for x in columns:
			solid[y * columns + x] = 1 if image.get_pixel(x, y).a > 0.3 else 0
	# keep only the biggest piece, so specks and loose bits don't count
	var inside := PackedByteArray()
	inside.resize(columns * rows)
	var seen := PackedByteArray()
	seen.resize(columns * rows)
	var biggest := PackedInt32Array()
	for start in columns * rows:
		if solid[start] == 0 or seen[start] == 1:
			continue
		var piece := PackedInt32Array([start])
		seen[start] = 1
		var k = 0
		while k < len(piece):
			var square = piece[k]
			k += 1
			var x = square % columns
			var y = square / columns
			for next in [square - 1 if x > 0 else -1, square + 1 if x < columns - 1 else -1,
					square - columns if y > 0 else -1, square + columns if y < rows - 1 else -1]:
				if next >= 0 and solid[next] == 1 and seen[next] == 0:
					seen[next] = 1
					piece.append(next)
		if len(piece) > len(biggest):
			biggest = piece
	if len(biggest) < 20:
		return {}
	var top = rows
	var bottom = 0
	var sum_x = 0.0
	for square in biggest:
		inside[square] = 1
		top = mini(top, square / columns)
		bottom = maxi(bottom, square / columns)
		sum_x += square % columns
	return {"columns": columns, "rows": rows, "inside": inside, "scale": scale,
		"top": top, "bottom": bottom, "middle": sum_x / len(biggest)}

static func _spot(look:Dictionary, square:int) -> Vector2:
	return Vector2(square % look.columns, square / look.columns) + Vector2(0.5, 0.5)

# How far each square on the body is from its edge, in thirds of a square (3 across, 4 diagonally)
static func _edge_distances(look:Dictionary) -> PackedInt32Array:
	var columns: int = look.columns
	var rows: int = look.rows
	var inside: PackedByteArray = look.inside
	var far = columns * rows * 4
	var edge := PackedInt32Array()
	edge.resize(columns * rows)
	for square in columns * rows:
		edge[square] = far if inside[square] == 1 else 0
	for y in rows:
		for x in columns:
			var square = y * columns + x
			if edge[square] == 0:
				continue
			var best = edge[square]
			best = mini(best, (edge[square - 1] if x > 0 else 0) + 3)
			best = mini(best, (edge[square - columns] if y > 0 else 0) + 3)
			best = mini(best, (edge[square - columns - 1] if x > 0 and y > 0 else 0) + 4)
			best = mini(best, (edge[square - columns + 1] if x < columns - 1 and y > 0 else 0) + 4)
			edge[square] = best
	for y in range(rows - 1, -1, -1):
		for x in range(columns - 1, -1, -1):
			var square = y * columns + x
			if edge[square] == 0:
				continue
			var best = edge[square]
			best = mini(best, (edge[square + 1] if x < columns - 1 else 0) + 3)
			best = mini(best, (edge[square + columns] if y < rows - 1 else 0) + 3)
			best = mini(best, (edge[square + columns + 1] if x < columns - 1 and y < rows - 1 else 0) + 4)
			best = mini(best, (edge[square + columns - 1] if x > 0 and y < rows - 1 else 0) + 4)
			edge[square] = best
	return edge

# The shortest paths through the body from root to every square on it, pulled towards the
# middle of the body: [cost (-1 off the body), parent (the square before it on its path,
# -1 for root), length (how long its path is, in tenths of a square)]
static func _paths(look:Dictionary, root:int, edge:PackedInt32Array) -> Array:
	var columns: int = look.columns
	var rows: int = look.rows
	var inside: PackedByteArray = look.inside
	var distance := PackedInt32Array()
	distance.resize(columns * rows)
	distance.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(columns * rows)
	parent.fill(-1)
	var length := PackedInt32Array()
	length.resize(columns * rows)
	length.fill(-1)
	length[root] = 0
	var ring = DIAGONAL_STEP * (1 + PULL) + 1
	var buckets := []
	for i in ring:
		buckets.append([])
	distance[root] = 0
	buckets[0].append(root)
	var waiting = 1
	var reached = 0
	var neighbors = [Vector3i(1, 0, STEP), Vector3i(-1, 0, STEP), Vector3i(0, 1, STEP), Vector3i(0, -1, STEP),
		Vector3i(1, 1, DIAGONAL_STEP), Vector3i(-1, 1, DIAGONAL_STEP), Vector3i(1, -1, DIAGONAL_STEP), Vector3i(-1, -1, DIAGONAL_STEP)]
	while waiting > 0:
		var bucket: Array = buckets[reached % ring]
		buckets[reached % ring] = []
		for square in bucket:
			waiting -= 1
			if distance[square] != reached:
				continue
			var x = square % columns
			var y = square / columns
			for neighbor in neighbors:
				var nx = x + neighbor.x
				var ny = y + neighbor.y
				if nx < 0 or ny < 0 or nx >= columns or ny >= rows:
					continue
				var next = ny * columns + nx
				if inside[next] == 0:
					continue
				var further = reached + neighbor.z + neighbor.z * PULL / maxi(edge[next], 1)
				if distance[next] >= 0 and distance[next] <= further:
					continue
				distance[next] = further
				parent[next] = square
				length[next] = length[square] + neighbor.z
				buckets[further % ring].append(next)
				waiting += 1
		reached += 1
	return [distance, parent, length]

# The ends of the parts that stick out at least shortest (in tenths of a square):
# [{"tip": square, "stop": where its path joins a longer one, "length": from stop to tip}],
# longest paths first. Squares are taken furthest first; each one's path is followed
# back until it joins a path already taken, and it counts if that was far enough.
static func _ends(look:Dictionary, distance:PackedInt32Array, parent:PackedInt32Array, root:int, shortest:float) -> Array:
	var squares := []
	for square in len(distance):
		if distance[square] >= 0:
			squares.append(square)
	squares.sort_custom(func(a, b): return distance[a] > distance[b])
	var taken := PackedByteArray()
	taken.resize(len(distance))
	taken[root] = 1
	var ends := []
	for square in squares:
		if taken[square] == 1:
			continue
		var at = square
		while taken[at] == 0:
			taken[at] = 1
			at = parent[at]
		var length = distance[square] - distance[at]
		if length >= shortest:
			ends.append({"tip": square, "stop": at, "length": length})
	return ends

# The path from square back to the middle of the trunk
static func _path(square:int, parent:PackedInt32Array) -> Array:
	var path := []
	while square >= 0:
		path.append(square)
		square = parent[square]
	return path
