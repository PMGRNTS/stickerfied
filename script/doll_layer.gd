# One layer of the doll (skin, a face, hair...). It shows its picture like a Sprite2D,
# but drawn on a grid of points that body_shaper.gd can move,
# so every layer bends the same way when the doll is reshaped.

extends Node2D

# The picture shown, like a Sprite2D's texture
var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
# The middle of the picture, from the layer's position (like a centered Sprite2D's offset)
var offset := Vector2.ZERO

# The grid the picture is drawn on (set by body_shaper.gd):
# where each point is, where it is in the picture (0 to 1), and which points make each triangle
var points := PackedVector2Array()
var uvs := PackedVector2Array()
var triangles := PackedInt32Array()
var colors := PackedColorArray()

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
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), triangles, points, colors, uvs,
		PackedInt32Array(), PackedFloat32Array(), texture.get_rid())
