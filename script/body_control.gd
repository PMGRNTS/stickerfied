# One body shaping control. Put these under BodyShaper in dress_up.tscn, over the part
# of the doll they change, and give each one a slider name. The Body menu gets a slider
# for each name; controls with the same name move together (such as both eyes).
#
# Shape "Area": changes the part of the doll inside an oval. Reach is the oval's half
#   width and half height. Stretch makes that part wider (x) or taller (y), Move shifts it.
#   The change fades out towards the edge of the oval, so nothing tears.
#   Soft Edge is how much of the oval fades: 1 fades all the way from the middle,
#   0.5 changes the inner half fully (good for moving a whole mouth). Harder edges
#   can't stretch or move as far before the picture would fold over, so they are held back.
#   Bend lifts the area's left and right ends more than its middle (in pixels at the
#   oval's sides), like the corners of a smiling mouth.
# Shape "Strip": changes everything between two lines across the whole doll.
#   Stretch.y makes the strip taller (Reach.y is half its height), and Stretch.x makes
#   it wider (Reach.x is half its width). What is beyond the strip moves out of the way.
#   Anchor says which edge of the strip stays where it is, such as the feet.
# Shape "Turn": turns everything above the control around it, like a head on its neck
#   or the body leaning at the hips. Turn is how far, in degrees (more turns clockwise).
#   Reach.y is half the height of the band where the turn fades in, so it bends
#   instead of breaking. Reach.x is half the width of what turns; Soft Edge fades the turn
#   out towards that, so arms or hair sticking out to the side don't swing too far.
#
# Stretch, Move, Bend and Turn are the change with the slider all the way right;
# all the way left is the opposite. 0.2 stretch is 20% bigger, -0.2 is 20% smaller.
# The ovals and strips are drawn in the editor, but not in the game.

@tool
extends Node2D

enum Shape { AREA, STRIP, TURN }
enum Anchor { MIDDLE, TOP_OR_LEFT, BOTTOM_OR_RIGHT }

# Smallest and biggest a part can be stretched to (0.05 = 5% of its size, such as closed eyes)
const STRETCH_LIMITS := Vector2(0.05, 2.0)

@export var slider := "Waist"
# The heading the slider is listed under in the Body menu
@export var group := "Body"
@export var shape := Shape.AREA:
	set(value):
		shape = value
		queue_redraw()
@export var reach := Vector2(60, 60):
	set(value):
		reach = value
		queue_redraw()
@export var stretch := Vector2(0.25, 0.0)
@export var move := Vector2.ZERO
@export var bend := 0.0
@export var turn := 0.0:
	set(value):
		turn = value
		queue_redraw()
@export_range(0.2, 1.0) var soft_edge := 1.0:
	set(value):
		soft_edge = value
		queue_redraw()
@export var anchor := Anchor.MIDDLE:
	set(value):
		anchor = value
		queue_redraw()

# Where point (on the screen) goes with the slider at value (-1 to 1).
# center is where the control's middle is now, after the controls before it moved it.
func shaped(point:Vector2, value:float, center := global_position) -> Vector2:
	var size = (reach * global_scale.abs()).max(Vector2.ONE)
	if shape == Shape.STRIP:
		var factor = (Vector2.ONE + stretch * value).clamp(Vector2.ONE * STRETCH_LIMITS.x, Vector2.ONE * STRETCH_LIMITS.y)
		return Vector2(_stretch_line(point.x, center.x, size.x, factor.x),
			_stretch_line(point.y, center.y, size.y, factor.y))
	var from_center = point - center
	var soft = clampf(soft_edge, 0.2, 1.0)
	if shape == Shape.TURN:
		# all of the turn above the band, none below it
		var above = smoothstep(-1.0, 1.0, -from_center.y / size.y)
		var amount = above * _fade(absf(from_center.x) / size.x, soft)
		return center + from_center.rotated(deg_to_rad(turn * value) * amount)
	# full change inside the hard middle, fading to nothing at the edge
	var weight = _fade((from_center / size).length(), soft)
	if weight == 0.0:
		return point
	# how far the change can go before the picture folds over (worked out for this fade)
	var biggest = minf(STRETCH_LIMITS.y, 1.0 + 1.2 * pow(soft, 1.45))
	var factor = (Vector2.ONE + stretch * value).clamp(Vector2.ONE * STRETCH_LIMITS.x, Vector2.ONE * biggest)
	var furthest = size * 0.6 * soft
	var lift = Vector2(0, -bend * value * pow(from_center.x / size.x, 2))
	var shift = (move * value + lift).clamp(-furthest, furthest)
	return point + (from_center * (factor - Vector2.ONE) + shift) * weight

# Whether the control can change point (an area only changes what is inside its oval)
func reaches(point:Vector2, center := global_position) -> bool:
	if shape != Shape.AREA:
		return true
	return ((point - center) / (reach * global_scale.abs()).max(Vector2.ONE)).length() < 1.0

# 1 inside the hard middle (distance 0 to 1 - soft), fading smoothly to 0 at distance 1
static func _fade(distance:float, soft:float) -> float:
	if distance >= 1.0:
		return 0.0
	var fade = clampf((distance - (1.0 - soft)) / soft, 0.0, 1.0)
	return (1.0 - fade * fade) * (1.0 - fade * fade)

# Stretches one direction of a strip: x is the point, middle and half its middle and half size
func _stretch_line(x:float, middle:float, half:float, factor:float) -> float:
	if factor == 1.0:
		return x
	var pivot = middle
	if anchor == Anchor.TOP_OR_LEFT:
		pivot = middle - half
	elif anchor == Anchor.BOTTOM_OR_RIGHT:
		pivot = middle + half
	var inside = clampf(x, middle - half, middle + half)
	return pivot + (inside - pivot) * factor + (x - inside)

# Shows the control's oval or strip in the editor
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color = Color(1, 0.4, 0.7, 0.9)
	if shape == Shape.TURN:
		# the band where the turn fades in, and an arc showing how far it turns
		for y in [-reach.y, reach.y]:
			draw_line(Vector2(-reach.x, y), Vector2(reach.x, y), Color(color, 0.5), 1.0)
		var angle = deg_to_rad(turn)
		draw_arc(Vector2.ZERO, reach.y * 3.0, -PI / 2 - angle, -PI / 2 + angle, 16, color, 2.0)
		draw_line(Vector2.ZERO, Vector2(0, -reach.y * 3.0), color, 2.0)
		draw_circle(Vector2.ZERO, 4.0, color)
		return
	if shape == Shape.AREA:
		var oval := PackedVector2Array()
		for i in 49:
			oval.append(Vector2.from_angle(TAU * i / 48.0) * reach)
		draw_polyline(oval, color, 2.0)
		if soft_edge < 1.0:
			# the hard middle, where the change is full
			var middle := PackedVector2Array()
			for point in oval:
				middle.append(point * (1.0 - soft_edge))
			draw_polyline(middle, Color(color, 0.5), 1.0)
		draw_circle(Vector2.ZERO, 3.0, color)
		return
	if stretch.y != 0.0:
		for y in [-reach.y, reach.y]:
			draw_line(Vector2(-reach.x, y), Vector2(reach.x, y), color, 2.0)
	if stretch.x != 0.0:
		for x in [-reach.x, reach.x]:
			draw_line(Vector2(x, -reach.y), Vector2(x, reach.y), color, 2.0)
	# a dot on the edge that stays put
	var edge = Vector2(0, reach.y) if stretch.y != 0.0 else Vector2(reach.x, 0)
	var pinned = {Anchor.TOP_OR_LEFT: -edge, Anchor.BOTTOM_OR_RIGHT: edge}
	draw_circle(pinned.get(anchor, Vector2.ZERO), 4.0, color)
