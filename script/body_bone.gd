# One bone of the doll's skeleton (see body_skeleton.gd): a part that turns at a joint,
# like an upper arm at the shoulder. Bones go under the Skeleton node in BodyShaper,
# with the bones that hang from them as their children (a forearm under its upper arm),
# so the forearm goes along when the upper arm turns.
#
# The bone's position is its joint, where it turns. It ends where the one bone hanging
# from it starts (an upper arm ends at the elbow, where the forearm starts); a bone with
# no bone or several bones hanging from it ends at End, from its joint (a forearm at
# the hand, the torso at the neck). Width is about half as wide as the part is:
# everything that close to the bone goes fully with it, and the doll gets extra grid
# points along it so it bends smoothly there. Give the torso a wide one, so the body
# holds still right up to the shoulders and hips.
# Both are drawn over the doll in the editor: move them over the parts of your own doll.
#
# Joint says which joint of the body the bone's joint is, and End Joint which one its end
# is (only for bones that end at End). Players can move them in Fit points, and Find parts
# and Standard put them on those parts of any doll (see joint_finder.gd).
#
# The Body menu gets a slider named Slider, listed under Group (bones with the same
# Slider move together). Turn is how far the bone turns, in degrees, with the slider
# all the way left (x) and all the way right (y); more turns clockwise.
# A bone without a Slider never turns. Put one along the middle of the body (the torso):
# the parts of the doll nearest to it, such as the head, then stay put when the
# arms and legs turn.

@tool
extends Node2D

# Left and right are as seen on the screen
enum Joint { NONE, PELVIS, NECK, LEFT_SHOULDER, LEFT_ELBOW, LEFT_HAND, RIGHT_SHOULDER, RIGHT_ELBOW,
	RIGHT_HAND, LEFT_HIP, LEFT_KNEE, LEFT_FOOT, RIGHT_HIP, RIGHT_KNEE, RIGHT_FOOT }

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
@export var joint := Joint.NONE
@export var end_joint := Joint.NONE

# How far the bone turns, in radians, with its slider at value (-1 to 1)
func angle_for(value:float) -> float:
	value = clampf(value, -1.0, 1.0)
	return deg_to_rad(turn.y * value if value >= 0.0 else -turn.x * value)

# The bones hanging from this one
func hanging() -> Array:
	return get_children().filter(func(child): return child.get_script() == get_script())

# Whether the bone ends at End (rather than where the one bone hanging from it starts)
func ends_at_end() -> bool:
	return len(hanging()) != 1

# Where the bone ends, on the screen
func tip() -> Vector2:
	var below = hanging()
	return below[0].global_position if len(below) == 1 else global_transform * end

# Moves the joint to spot (on the screen), leaving the bones hanging from it and its end where they are
func move_joint(spot:Vector2) -> void:
	var below = hanging()
	var kept = below.map(func(bone): return bone.global_position)
	var end_at = tip()
	global_position = spot
	for i in len(below):
		below[i].global_position = kept[i]
	if ends_at_end():
		move_end(end_at)

# Moves the end to spot (on the screen); only for bones that end at End
func move_end(spot:Vector2) -> void:
	end = global_transform.affine_inverse() * spot

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color = Color(1.0, 0.65, 0.1, 0.9) if slider != "" else Color(0.6, 0.6, 0.6, 0.9)
	var to = to_local(tip())
	var across = to.orthogonal().normalized() * width
	draw_polyline(PackedVector2Array([across, to + across, to - across, -across, across]), Color(color, 0.4), 1.0)
	draw_line(Vector2.ZERO, to, color, 3.0)
	draw_circle(Vector2.ZERO, 5.0, color)
	draw_circle(to, 3.0, color)
