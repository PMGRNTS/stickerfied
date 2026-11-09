# One layer of the doll (skin, a face, hair...). It shows its picture like a Sprite2D,
# but drawn on a grid of points that body_shaper.gd can move,
# so every layer bends the same way when the doll is reshaped.

extends Node2D

# The picture shown, like a Sprite2D's texture
var texture: Texture2D:
	set(value):
		texture = value
		mended = false
		queue_redraw()
# The middle of the picture, from the layer's position (like a centered Sprite2D's offset)
var offset := Vector2.ZERO

# The grid the picture is drawn on (set by body_shaper.gd):
# where each point is, where it is in the picture (0 to 1), and which points make each triangle
var points := PackedVector2Array()
var uvs := PackedVector2Array()
var triangles := PackedInt32Array():
	set(value):
		triangles = value
		mended = false
var colors := PackedColorArray()
# The grid tears between parts of the doll that turn differently (see body_skeleton.gd's tear()).
# For each torn triangle reaching across a gap: [where it is in triangles, its points
# before tearing, its middle in the picture (0 to 1)]. Where this layer's picture covers
# the gap, such as a skirt between the legs, the triangle is drawn whole.
var mends := []:
	set(value):
		mends = value
		mended = false
var shown_triangles := PackedInt32Array() # triangles, mended where this layer's picture covers a gap
var mended := false # whether shown_triangles is up to date

func set_points(new_points:PackedVector2Array) -> void:
	points = new_points
	queue_redraw()

func _draw() -> void:
	if texture == null:
		return
	if points.is_empty():
		# no grid yet: draw the picture as it is
		draw_texture(texture, offset - texture.get_size() / 2)
		return
	if not mended:
		_mend()
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), shown_triangles, points, colors, uvs,
		PackedInt32Array(), PackedFloat32Array(), texture.get_rid())

func _mend() -> void:
	mended = true
	shown_triangles = triangles
	if mends.is_empty():
		return
	var image = texture.get_image()
	if image == null:
		return
	if image.is_compressed():
		image.decompress()
	shown_triangles = triangles.duplicate()
	for mend in mends:
		if image.get_pixelv(Vector2i(mend[2] * Vector2(image.get_size())).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)).a > 0.5:
			for k in 3:
				shown_triangles[mend[0] + k] = mend[1][k]
