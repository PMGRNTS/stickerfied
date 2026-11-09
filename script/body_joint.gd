# A point players can fit to their doll (see body_fitter.gd) on one of the skeleton's
# joints: where a bone turns (is_end false), or where a bone that ends at its End ends
# (is_end true), such as a hand. It works like a body control (body_control.gd) for fitting:
# moving it moves only that joint, not the bones hanging from it, and its reach is the
# bone's Width. Fits keep it under its name, like the controls.

extends RefCounted

const BodyBone = preload("res://script/body_bone.gd")
const BodyControl = preload("res://script/body_control.gd")

var bone: BodyBone
var is_end := false
var name := ""
var label := "" # shown in Fit points
var which := 0 # the BodyBone.Joint it is

# Like a body control's, so fitting treats it the same way
var landmark := BodyControl.Landmark.NONE # joints are put on parts by joint_finder.gd instead
var shape := BodyControl.Shape.AREA
var swing := 0.0
var slider := ""
var group := ""

var global_position: Vector2:
	get:
		return bone.tip() if is_end else bone.global_position
	set(value):
		if is_end:
			bone.move_end(value)
		else:
			bone.move_joint(value)

var reach: Vector2:
	get:
		return Vector2.ONE * bone.width
	set(value):
		bone.width = maxf(value.x, 2.0)

var global_scale: Vector2:
	get:
		return bone.global_scale

# The fit points for a skeleton's bones (from body_skeleton.gd's bones): every joint,
# and the end of every bone that ends at its End
static func for_bones(bones:Array) -> Array:
	var points := []
	for bone in bones:
		points.append(_make(bone, false))
		if bone.ends_at_end():
			points.append(_make(bone, true))
	return points

static func _make(bone:BodyBone, at_end:bool) -> RefCounted:
	var point = new()
	point.bone = bone
	point.is_end = at_end
	point.which = bone.end_joint if at_end else bone.joint
	point.name = "%s:%s" % [bone.name, "end" if at_end else "joint"]
	if point.which != BodyBone.Joint.NONE:
		point.label = String(BodyBone.Joint.keys()[point.which]).capitalize()
	else:
		point.label = "%s %s" % [String(bone.name).capitalize(), "end" if at_end else "joint"]
	return point

# Draws the bone over the doll while fitting, with this point at middle
func draw_shape(canvas:CanvasItem, middle:Vector2, color:Color) -> void:
	var start = bone.global_position
	var finish = bone.tip()
	var other = start if is_end else finish
	var across = (other - middle).orthogonal().normalized() * bone.width
	canvas.draw_polyline(PackedVector2Array([middle + across, other + across, other - across,
		middle - across, middle + across]), Color(color, color.a * 0.5), 1.0)
	canvas.draw_line(middle, other, color, 2.0)
	canvas.draw_circle(other, 3.0, color)
