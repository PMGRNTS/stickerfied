# Finds the parts of a doll in its pictures, so Fit points can put the Body menu's controls
# on them (see body_fitter.gd). It expects a doll standing straight and facing forward.
#   - standard() only looks at how big the doll is, and puts each part where it usually is
#     on such a doll (see STANDARD)
#   - find() also follows the body picture's outline: the head goes down to the narrowest
#     place under it (the neck), the legs start where a gap opens between them, and the
#     waist is the narrowest place between the shoulders and the legs. Small marks near the
#     top of the doll (in the other layers, or dark ones drawn on the body) are the eyes (two
#     side by side) and the mouth (the widest one under them). When the outline's head doesn't
#     fit the eyes (long hair hides the neck), the head is worked out from the eyes instead.
#     Whatever it can't find stays where standard() puts it.
# Both give each landmark (body_control.gd's Landmark) as {"at": its middle, "size": half its
# size, "turn": half the size of a Turn control on it}, in the body picture's pixels.

extends RefCounted

const BodyControl = preload("res://script/body_control.gd")
const Landmark = BodyControl.Landmark

# Pictures are looked at this many pixels tall at most, so big ones don't take long
const LOOK_HEIGHT := 400
# Where each part usually is on a doll standing straight: how far down from the top of
# the doll (as a part of its height), and half its width (also as a part of its height)
const STANDARD := {
	"neck": 0.19, "shoulders": 0.25, "chest": 0.32, "waist": 0.42, "hips": 0.5, "crotch": 0.54,
	"head_width": 0.075, "shoulder_width": 0.13, "waist_width": 0.085, "hip_width": 0.11,
}

static func standard(body:Image) -> Dictionary:
	var look = _prepare(body)
	if look == null:
		return {}
	var parts = _standard(_runs(look))
	return _landmarks(parts, _scale(look, body)) if not parts.is_empty() else {}

# others are the doll's other pictures worn now (face, hair...), where the eyes and mouth may be
static func find(body:Image, others:Array) -> Dictionary:
	var look = _prepare(body)
	if look == null:
		return {}
	var rows = _runs(look)
	var parts = _standard(rows)
	if parts.is_empty():
		return {}
	var outlined = _find_head(rows, parts)
	var marks := []
	for other in others:
		var mark = _prepare(other)
		if mark:
			mark.resize(look.get_width(), look.get_height(), Image.INTERPOLATE_BILINEAR)
			marks.append(mark.get_data())
	_find_face(look, marks, parts, outlined)
	_find_body(rows, parts)
	return _landmarks(parts, _scale(look, body))

# A copy of the picture that can be read pixel by pixel, at most LOOK_HEIGHT tall
static func _prepare(picture:Image) -> Image:
	if picture == null or picture.is_empty():
		return null
	var look = picture.duplicate()
	if look.is_compressed() and look.decompress() != OK:
		return null
	look.convert(Image.FORMAT_RGBA8)
	if look.get_height() > LOOK_HEIGHT:
		var width = maxi(1, roundi(look.get_width() * float(LOOK_HEIGHT) / look.get_height()))
		look.resize(width, LOOK_HEIGHT, Image.INTERPOLATE_BILINEAR)
	return look

# From the looked-at copy's pixels to the picture's
static func _scale(look:Image, picture:Image) -> Vector2:
	return Vector2(picture.get_size()) / Vector2(look.get_size())

# The solid stretches on each row of the picture: rows[y] = [Vector2i(first x, last x), ...].
# Specks narrower than 2 pixels are left out.
static func _runs(look:Image) -> Array:
	var data = look.get_data()
	var width = look.get_width()
	var rows := []
	for y in look.get_height():
		var row := []
		var start = -1
		for x in width + 1:
			var solid = x < width and data[(y * width + x) * 4 + 3] >= 128
			if solid and start < 0:
				start = x
			elif not solid and start >= 0:
				if x - start >= 2:
					row.append(Vector2i(start, x - 1))
				start = -1
		rows.append(row)
	return rows

# The parts where they usually are, in the box around the doll:
# "top" and "bottom" of the doll, its "middle" (across) and half its "width",
# "head_at" and "head_size" (half), the heights of the "neck", "shoulders", "chest", "waist",
# "hips" and "crotch", and the half widths "shoulder_width", "waist_width" and "hip_width"
static func _standard(rows:Array) -> Dictionary:
	var top = -1
	var bottom = -1
	var left = INF
	var right = -INF
	var sum = 0.0
	var count = 0.0
	for y in len(rows):
		for run in rows[y]:
			if top < 0:
				top = y
			bottom = y
			left = minf(left, run.x)
			right = maxf(right, run.y)
			var length = run.y - run.x + 1
			sum += (run.x + run.y) / 2.0 * length
			count += length
	if count == 0 or bottom - top < 10:
		return {}
	var height = float(bottom - top)
	var parts = {"top": float(top), "bottom": float(bottom), "middle": sum / count}
	parts.width = maxf(parts.middle - left, right - parts.middle)
	for key in ["neck", "shoulders", "chest", "waist", "hips", "crotch"]:
		parts[key] = top + STANDARD[key] * height
	for key in ["shoulder_width", "waist_width", "hip_width"]:
		parts[key] = STANDARD[key] * height
	parts.head_at = Vector2(parts.middle, (top + parts.neck) / 2)
	parts.head_size = Vector2(STANDARD.head_width * height, (parts.neck - top) / 2)
	return parts

# Follows the outline down from the top of the head: it narrows at the neck and widens again
# at the shoulders. Returns true when it found them.
static func _find_head(rows:Array, parts:Dictionary) -> bool:
	var top = int(parts.top)
	var height = parts.bottom - parts.top
	var run = _widest(rows[top])
	var widest = run
	var narrowest = null
	var neck = -1
	var shoulders = false
	for y in range(top, int(parts.top + height * 0.5)):
		run = _following(rows[y], run)
		if run == null:
			return false
		var width = run.y - run.x
		if narrowest == null:
			if width > widest.y - widest.x:
				widest = run
			elif width < (widest.y - widest.x) * 0.8:
				narrowest = run
				neck = y
		elif width < narrowest.y - narrowest.x:
			narrowest = run
			neck = y
		elif width > maxi(narrowest.y - narrowest.x, 1) * 1.6:
			shoulders = true
			break
	if not shoulders or neck - top < height * 0.08 or neck - top > height * 0.45:
		return false
	_set_head(parts, Vector2((widest.x + widest.y) / 2.0, (top + neck) / 2.0),
		Vector2((widest.y - widest.x) / 2.0, (neck - top) / 2.0))
	return true

# Puts the head here (its middle and half its size), and moves the parts under it
# to fit a bigger or smaller head
static func _set_head(parts:Dictionary, at:Vector2, size:Vector2) -> void:
	var old_neck = parts.neck
	var neck = at.y + size.y
	parts.head_at = at
	parts.head_size = size
	parts.neck = neck
	for key in ["shoulders", "chest", "waist", "hips", "crotch"]:
		var down = (parts[key] - old_neck) / (parts.bottom - old_neck)
		parts[key] = neck + down * (parts.bottom - neck)

# Finds where the legs part, and the waist and hips above them
static func _find_body(rows:Array, parts:Dictionary) -> void:
	var height = parts.bottom - parts.top
	var x = int(parts.middle)
	parts.shoulder_width = _width_at(rows, parts.shoulders, x, parts.shoulder_width)
	# up the gap between the legs
	var y = int(parts.bottom - height * 0.08)
	if not _solid_in(rows[y], x):
		while y > parts.shoulders and not _solid_in(rows[y], x):
			y -= 1
		if y > parts.shoulders + height * 0.15:
			parts.crotch = float(y)
	# the narrowest place between the shoulders and the legs
	var span = parts.crotch - parts.shoulders
	var narrowest = INF
	for row in range(int(parts.shoulders + span * 0.3), int(parts.crotch - span * 0.15)):
		var run = _run_at(rows[row], x)
		if run != null and run.y - run.x < narrowest:
			narrowest = run.y - run.x
			parts.waist = float(row)
	if narrowest < INF:
		parts.waist_width = narrowest / 2.0
	parts.hips = lerpf(parts.waist, parts.crotch, 0.67)
	parts.hip_width = _width_at(rows, parts.hips, x, parts.hip_width)
	parts.chest = lerpf(parts.shoulders, parts.waist, 0.4)

# Finds the eyes and mouth: small marks near the top of the doll, in the other pictures (marks
# has their pixels, the same size as look) or dark ones drawn on the body. Big marks (such as
# hair or outlines) don't count. outlined is true when _find_head found the head; if that head
# doesn't fit the eyes, the head is worked out from the eyes.
static func _find_face(look:Image, marks:Array, parts:Dictionary, outlined:bool) -> void:
	var height = parts.bottom - parts.top
	var near = Rect2(parts.head_at.x - height * 0.25, parts.top, height * 0.5, height * 0.45)
	var box = Rect2i(near).intersection(Rect2i(Vector2i.ZERO, look.get_size()))
	if box.size.x < 4 or box.size.y < 4:
		return
	var data = look.get_data()
	var width = look.get_width()
	# how bright the doll usually is here: marks on the body are much darker than that
	var brightness := PackedByteArray()
	brightness.resize(box.size.x * box.size.y)
	var counts := PackedInt32Array()
	counts.resize(256)
	for y in box.size.y:
		for x in box.size.x:
			var i = ((y + box.position.y) * width + x + box.position.x) * 4
			brightness[y * box.size.x + x] = int(data[i] * 0.3 + data[i + 1] * 0.59 + data[i + 2] * 0.11)
			if data[i + 3] >= 128:
				counts[brightness[y * box.size.x + x]] += 1
	var half = _sum(counts) / 2
	var usual = 0
	var seen = 0
	while usual < 255 and seen + counts[usual] < half:
		seen += counts[usual]
		usual += 1
	var on := PackedByteArray()
	on.resize(box.size.x * box.size.y)
	for y in box.size.y:
		for x in box.size.x:
			var i = ((y + box.position.y) * width + x + box.position.x) * 4
			var mark = marks.any(func(other): return other[i + 3] >= 128)
			if not mark:
				mark = data[i + 3] >= 128 and brightness[y * box.size.x + x] < usual * 0.6
			on[y * box.size.x + x] = 1 if mark else 0
	# the marks: {"at": middle, "size": half size, "count": pixels}
	var found := []
	for start in len(on):
		if on[start] != 1:
			continue
		on[start] = 2
		var stack := [start]
		var corner_min = Vector2i(start % box.size.x, start / box.size.x)
		var corner_max = corner_min
		var count = 0
		var touches = false
		while not stack.is_empty():
			var i = stack.pop_back()
			var spot = Vector2i(i % box.size.x, i / box.size.x)
			corner_min = corner_min.min(spot)
			corner_max = corner_max.max(spot)
			count += 1
			touches = touches or spot.x == 0 or spot.y == 0 or spot.x == box.size.x - 1 or spot.y == box.size.y - 1
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next = spot + step
				if next.x >= 0 and next.y >= 0 and next.x < box.size.x and next.y < box.size.y:
					var j = next.y * box.size.x + next.x
					if on[j] == 1:
						on[j] = 2
						stack.append(j)
		var size = Vector2(corner_max - corner_min + Vector2i.ONE)
		if touches or count < 3 or size.x > height * 0.08 or size.y > height * 0.08:
			continue
		var at = Vector2(box.position + corner_min) + size / 2
		# the doll is all around a face's marks (bits of its outline are at its edge)
		var around = [Vector2(size.x / 2 + 3, 0), Vector2(-size.x / 2 - 3, 0), Vector2(0, size.y / 2 + 3), Vector2(0, -size.y / 2 - 3)]
		if not around.all(func(step): return _solid_at(look, at + step)):
			continue
		found.append({"at": at, "size": size / 2, "count": count})

	# the eyes: two marks side by side, of about the same size, either side of the head's middle.
	# Bigger marks win, so eyes beat eyebrows.
	var best = INF
	for a in found:
		for b in found:
			var apart = b.at - a.at
			if apart.x < height * 0.02 or apart.x > height * 0.15 or absf(apart.y) > apart.x * 0.3:
				continue
			var off_middle = absf((a.at.x + b.at.x) / 2 - parts.head_at.x)
			var sizes = maxf(a.size.x, b.size.x) / maxf(minf(a.size.x, b.size.x), 0.5)
			if off_middle > apart.x * 0.6 or sizes > 2.5:
				continue
			var score = absf(apart.y) + off_middle + sizes * 2 - sqrt(minf(a.count, b.count))
			if score < best:
				best = score
				parts.eyes = [a.at, b.at]
				parts.eye_size = a.size.max(b.size)
	if not parts.has("eyes"):
		if not outlined:
			return
		# no eyes: the mouth is still the widest mark in the bottom half of the head
		for mark in found:
			if mark.at.y > parts.head_at.y and absf(mark.at.x - parts.head_at.x) < parts.head_size.x * 0.5 \
					and mark.at.y < parts.neck and mark.size.x > parts.get("mouth_size", Vector2.ZERO).x:
				parts.mouth = mark.at
				parts.mouth_size = mark.size
		return
	var eyes_at = (parts.eyes[0] + parts.eyes[1]) / 2
	var spacing = parts.eyes[1].x - parts.eyes[0].x
	# the mouth: the widest mark under the eyes
	for mark in found:
		var under = mark.at - eyes_at
		if under.y > spacing * 0.25 and under.y < spacing * 1.1 and absf(under.x) < spacing * 0.7 \
				and mark.size.x > parts.get("mouth_size", Vector2.ZERO).x:
			parts.mouth = mark.at
			parts.mouth_size = mark.size
	# the head, as the eyes see it: about 2.4 eye spacings wide and 2.8 tall,
	# with the eyes a little under its middle
	var size = Vector2(1.2, 1.4) * spacing
	var at = Vector2(eyes_at.x, eyes_at.y - spacing * 0.28)
	var head = Rect2(parts.head_at - parts.head_size, parts.head_size * 2)
	var fits = outlined and head.has_point(eyes_at) and parts.head_size.y < size.y * 1.4 and parts.head_size.y > size.y / 1.6
	if not fits:
		_set_head(parts, at, size)

# Turns the parts into the landmarks, in the picture's pixels (scale is from the looked-at copy)
static func _landmarks(parts:Dictionary, scale:Vector2) -> Dictionary:
	var height = parts.bottom - parts.top
	var head: Vector2 = parts.head_at
	var head_size: Vector2 = parts.head_size
	var eyes = parts.get("eyes", [head + head_size * Vector2(-0.4, 0.2), head + head_size * Vector2(0.4, 0.2)])
	var mouth = parts.get("mouth", head + head_size * Vector2(0, 0.55))
	var gap = maxf(mouth.y - (eyes[0].y + eyes[1].y) / 2, head_size.y * 0.2)
	var eye_size = (head_size * Vector2(0.33, 0.22)).max(parts.get("eye_size", Vector2.ZERO) * 2.5)
	eye_size.y = minf(eye_size.y, gap * 0.45)
	var mouth_size = Vector2(maxf(head_size.x, parts.get("mouth_size", Vector2.ZERO).x * 1.7), minf(head_size.y * 0.62, gap * 1.1))
	var legs_end = parts.bottom - height * 0.06
	var hair_size = Vector2(head_size.x * 2.25, (parts.waist - parts.top) / 2 + height * 0.02)
	var landmarks = {
		Landmark.FIGURE: {"at": Vector2(parts.middle, (parts.top + parts.bottom) / 2),
			"size": Vector2(parts.width + height * 0.05, height / 2)},
		Landmark.HEAD: {"at": head, "size": Vector2.ONE * maxf(head_size.x, head_size.y) * 1.8},
		Landmark.NECK: {"at": Vector2(head.x, parts.neck), "size": head_size * Vector2(2.3, 0.37)},
		Landmark.LEFT_EYE: {"at": eyes[0], "size": eye_size},
		Landmark.RIGHT_EYE: {"at": eyes[1], "size": eye_size},
		Landmark.MOUTH: {"at": mouth, "size": mouth_size},
		Landmark.CHEEKS: {"at": Vector2(head.x, mouth.y + head_size.y * 0.3), "size": head_size * Vector2(1.5, 0.6)},
		Landmark.HAIR: {"at": Vector2(head.x, parts.top - height * 0.02 + hair_size.y), "size": hair_size},
		Landmark.SHOULDERS: {"at": Vector2(parts.middle, parts.shoulders), "size": Vector2(parts.shoulder_width * 1.4, height * 0.12)},
		Landmark.CHEST: {"at": Vector2(parts.middle, parts.chest), "size": Vector2(parts.shoulder_width * 1.1, height * 0.13)},
		Landmark.WAIST: {"at": Vector2(parts.middle, parts.waist), "size": Vector2(parts.waist_width * 1.6, height * 0.11)},
		Landmark.HIPS: {"at": Vector2(parts.middle, parts.hips), "size": Vector2(parts.hip_width * 1.4, height * 0.1),
			"turn": Vector2(parts.width * 1.75, height * 0.055)},
		Landmark.LEGS: {"at": Vector2(parts.middle, (parts.crotch + legs_end) / 2),
			"size": Vector2(parts.width + height * 0.05, (legs_end - parts.crotch) / 2)},
	}
	for key in landmarks:
		for part in landmarks[key]:
			landmarks[key][part] *= scale
	return landmarks

# The widest solid stretch on a row
static func _widest(row:Array):
	var widest = null
	for run in row:
		if widest == null or run.y - run.x > widest.y - widest.x:
			widest = run
	return widest

# The stretch on a row that overlaps run the most, or null if none do
static func _following(row:Array, run):
	var best = null
	var most = 0
	for other in row:
		var overlap = mini(run.y, other.y) - maxi(run.x, other.x)
		if overlap >= 0 and (best == null or overlap > most):
			best = other
			most = overlap
	return best

# The solid stretch on a row that x is in, or the nearest one
static func _run_at(row:Array, x:int):
	var best = null
	var nearest = INF
	for run in row:
		var away = maxi(run.x - x, x - run.y)
		if away < nearest:
			nearest = away
			best = run
	return best

static func _solid_at(look:Image, point:Vector2) -> bool:
	var spot = Vector2i(point.round())
	return Rect2i(Vector2i.ZERO, look.get_size()).has_point(spot) and look.get_pixelv(spot).a >= 0.5

static func _sum(numbers:PackedInt32Array) -> int:
	var total = 0
	for number in numbers:
		total += number
	return total

static func _solid_in(row:Array, x:int) -> bool:
	return row.any(func(run): return run.x <= x and x <= run.y)

# Half the width of the solid stretch at height y around x, or otherwise if there is none
static func _width_at(rows:Array, y:float, x:int, otherwise:float) -> float:
	var run = _run_at(rows[clampi(int(y), 0, len(rows) - 1)], x)
	return (run.y - run.x) / 2.0 if run != null else otherwise
