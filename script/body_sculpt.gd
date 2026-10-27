# The doll's shape as pushed around with the sculpt brush (see body_sculptor.gd):
# a lattice of points over the doll's images, each moved some way. Everything in
# between moves smoothly along with the points around it.
# It is applied before the Body menu's sliders, so they work on the sculpted doll.
# Outfits keep it in the doll's shape as "_sculpt": {"index": [x, y], ...}, the
# lattice points that were moved and how far, in pixels of the doll's images.

extends RefCounted

# Pixels of the doll's images between lattice points
const SPACING := 15.0
# How far (in pixels) a lattice point can be pushed
const LIMIT := 60.0

# The body shaper calls each control's shaped(), and blinking looks at slider
var slider := ""

var columns := 0
var rows := 0
var corner := Vector2.ZERO # the lattice's first point, in a doll layer's coordinates
var offsets := PackedVector2Array() # how far each lattice point is pushed, in a layer's coordinates
var to_screen := Transform2D()
var from_screen := Transform2D()

func _init(image_corner:Vector2, image_size:Vector2, layer_to_screen:Transform2D) -> void:
	corner = image_corner
	columns = ceili(image_size.x / SPACING) + 1
	rows = ceili(image_size.y / SPACING) + 1
	offsets.resize(columns * rows)
	to_screen = layer_to_screen
	from_screen = layer_to_screen.affine_inverse()

func is_empty() -> bool:
	for offset in offsets:
		if offset != Vector2.ZERO:
			return false
	return true

# Where point (on the screen) goes on the sculpted doll
func shaped(point:Vector2, _value := 1.0, _center := Vector2.ZERO) -> Vector2:
	return point + to_screen.basis_xform(offset_at(from_screen * point))

# Blinking only looks at areas with the blink slider
func reaches(_point:Vector2, _center := Vector2.ZERO) -> bool:
	return false

# How far the lattice moves a point (in a layer's coordinates), blended from the 4 around it
func offset_at(local:Vector2) -> Vector2:
	var place = (local - corner) / SPACING
	var cell = Vector2i(place.floor()).clamp(Vector2i.ZERO, Vector2i(columns - 2, rows - 2))
	var within = (place - Vector2(cell)).clamp(Vector2.ZERO, Vector2.ONE)
	var i = cell.y * columns + cell.x
	var top = offsets[i].lerp(offsets[i + 1], within.x)
	var bottom = offsets[i + columns].lerp(offsets[i + columns + 1], within.x)
	return top.lerp(bottom, within.y)

# Pushes what is shown at middle (in a layer's coordinates, on the sculpted doll) by push_by,
# fading out at radius. Long pushes are done in short steps, so the picture never folds over.
func push(middle:Vector2, push_by:Vector2, radius:float) -> void:
	var steps = maxi(1, ceili(push_by.length() / (radius / 4.0)))
	var amount = push_by / steps
	for step in steps:
		var brush = middle + amount * step
		for i in len(offsets):
			var shown = corner + Vector2(i % columns, i / columns) * SPACING + offsets[i]
			var weight = _falloff(shown.distance_to(brush) / radius)
			if weight > 0.0:
				offsets[i] = (offsets[i] + amount * weight).limit_length(LIMIT)

# Eases what is shown around middle back to the doll as drawn, by strength (0 to 1)
func restore(middle:Vector2, radius:float, strength:float) -> void:
	for i in len(offsets):
		var shown = corner + Vector2(i % columns, i / columns) * SPACING + offsets[i]
		offsets[i] *= 1.0 - clampf(strength, 0.0, 1.0) * _falloff(shown.distance_to(middle) / radius)
		if offsets[i].length_squared() < 0.01:
			offsets[i] = Vector2.ZERO

func clear() -> void:
	offsets.fill(Vector2.ZERO)

# 1 in the middle of the brush, fading smoothly to 0 at its edge
static func _falloff(distance:float) -> float:
	if distance >= 1.0:
		return 0.0
	return (1.0 - distance * distance) * (1.0 - distance * distance)

# The lattice as kept in outfits: only the points that moved
func to_saved() -> Dictionary:
	var saved := {}
	for i in len(offsets):
		var offset = offsets[i].snapped(Vector2.ONE * 0.5)
		if offset != Vector2.ZERO:
			saved[str(i)] = [offset.x, offset.y]
	return saved

# Sets the lattice from an outfit's "_sculpt", leaving out anything that doesn't fit
func load_saved(saved) -> void:
	clear()
	if not saved is Dictionary:
		return
	for key in saved:
		var entry = saved[key]
		if not (str(key).is_valid_int() and entry is Array and len(entry) == 2):
			continue
		var i = str(key).to_int()
		if i >= 0 and i < len(offsets) and (entry[0] is float or entry[0] is int) and (entry[1] is float or entry[1] is int):
			offsets[i] = Vector2(entry[0], entry[1]).limit_length(LIMIT)
