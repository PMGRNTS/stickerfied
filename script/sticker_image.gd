# Turns a picture from an AI model into a sticker: makes it a sensible size,
# removes a plain background if the model didn't make one transparent,
# and trims the empty space around it.

class_name StickerImage

# Longest side of a saved sticker, in pixels
const MAX_SIZE := 384
# How close (0 to 1) a color must be to the background color to be removed
const TOLERANCE := 0.14

static func prepare(image: Image) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	var longest = maxi(image.get_width(), image.get_height())
	if longest > MAX_SIZE:
		var factor = float(MAX_SIZE) / longest
		image.resize(roundi(image.get_width() * factor), roundi(image.get_height() * factor), Image.INTERPOLATE_LANCZOS)
	if not has_transparent_corner(image):
		remove_flat_background(image)
	var used = image.get_used_rect()
	if used.has_area():
		image = image.get_region(used.grow(2).intersection(Rect2i(Vector2i.ZERO, image.get_size())))
	return image

static func has_transparent_corner(image: Image) -> bool:
	var last = image.get_size() - Vector2i.ONE
	for corner in [Vector2i.ZERO, Vector2i(last.x, 0), Vector2i(0, last.y), last]:
		if image.get_pixelv(corner).a < 0.5:
			return true
	return false

# Starting from the edges, clears every pixel that has (about) the same color
# as the top-left corner, stopping at the drawing's outline.
# Pixels at the edge of the drawing are faded a little, so no light halo is left.
static func remove_flat_background(image: Image) -> void:
	var width = image.get_width()
	var height = image.get_height()
	var data = image.get_data()
	var background = image.get_pixel(0, 0)
	var limit = TOLERANCE * 3.0

	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)
	var queue := PackedInt32Array()
	for x in width:
		queue.append(x)
		queue.append((height - 1) * width + x)
	for y in height:
		queue.append(y * width)
		queue.append(y * width + width - 1)
	for i in queue:
		visited[i] = 1

	var head := 0
	while head < queue.size():
		var i = queue[head]
		head += 1
		var difference = _difference(data, i, background)
		if difference > limit * 2.0:
			continue # part of the drawing
		if difference > limit:
			# an edge pixel: fade it, but don't go past it
			data[i * 4 + 3] = mini(data[i * 4 + 3], int(255 * (difference - limit) / limit))
			continue
		data[i * 4 + 3] = 0
		var x = i % width
		var y = i / width
		for neighbor in [i - 1 if x > 0 else -1, i + 1 if x < width - 1 else -1,
				i - width if y > 0 else -1, i + width if y < height - 1 else -1]:
			if neighbor >= 0 and visited[neighbor] == 0:
				visited[neighbor] = 1
				queue.append(neighbor)
	image.set_data(width, height, false, Image.FORMAT_RGBA8, data)

static func _difference(data: PackedByteArray, i: int, color: Color) -> float:
	return absf(data[i * 4] / 255.0 - color.r) + absf(data[i * 4 + 1] / 255.0 - color.g) \
		+ absf(data[i * 4 + 2] / 255.0 - color.b)
