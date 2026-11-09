# One bone of the doll's skeleton (see body_skeleton.gd): a part that turns at a joint,
# like an upper arm at the shoulder. Bones go under the Skeleton node in BodyShaper,
# with the bones that hang from them as their children (a forearm under its upper arm),
# so the forearm goes along when the upper arm turns.
#
# The bone's position is its joint, where it turns. End is where the bone ends,
# from the joint (for an upper arm, the elbow). Width is about half as wide as the part
# is: everything that close to the bone goes fully with it, and the doll gets extra grid
# points along it so it bends smoothly there. Give the torso a wide one, so the body
# holds still right up to the shoulders and hips.
# Both are drawn over the doll in the editor: move them over the parts of your own doll.
#
# The Body menu gets a slider named Slider, listed under Group (bones with the same
# Slider move together). Turn is how far the bone turns, in degrees, with the slider
# all the way left (x) and all the way right (y); more turns clockwise.
# A bone without a Slider never turns. Put one along the middle of the body (the torso):
# the parts of the doll nearest to it, such as the head, then stay put when the
# arms and legs turn.

@tool
extends Node2D

@export var slider := ""
@export var group := "Pose"
@export var turn := Vector2(-45.0, 45.0)
@export var end := Vector2(0, 100):
	set(value):
		end = value
		queue_redraw()
@export var width := 15.0:
	set(value):
		width = value
		queue_redraw()

# How far the bone turns, in radians, with its slider at value (-1 to 1)
func angle_for(value:float) -> float:
	value = clampf(value, -1.0, 1.0)
	return deg_to_rad(turn.y * value if value >= 0.0 else -turn.x * value)

# Where the bone ends, on the screen
func tip() -> Vector2:
	return global_transform * end

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color = Color(1.0, 0.65, 0.1, 0.9) if slider != "" else Color(0.6, 0.6, 0.6, 0.9)
	var across = end.orthogonal().normalized() * width
	draw_polyline(PackedVector2Array([across, end + across, end - across, -across, across]), Color(color, 0.4), 1.0)
	draw_line(Vector2.ZERO, end, color, 3.0)
	draw_circle(Vector2.ZERO, 5.0, color)
	draw_circle(end, 3.0, color)
