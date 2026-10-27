# Lets the player add their own pictures (a drawing, a photo) to the menus,
# with the upload button in each menu or by dropping a file on the game window.
#   - Backgrounds are scaled to cover the screen.
#   - Stickers are trimmed and placed on the doll, like AI stickers.
#   - Doll items (hair, faces...) are put in place by the player: drag to move,
#     mouse wheel or the corner handle to resize, then Done (or Enter).
#     A picture that is already the size of the doll's images is used as it is,
#     so art drawn over the doll's template lines up by itself.
#     Erase rubs out parts of it, such as the inside of a collar that shows above the neck.
# Stickers on the doll can be erased the same way (the eraser handle, see sticker_stage.gd).
# A plain background (such as white paper) is removed from stickers and doll items.
# Pictures are kept in user://generated/ like AI pictures, so they're there next time.
# AI Create sends the doll items it makes through the same placing step (place_picture).

extends Node2D

@export var interactivity: Node
# The doll's layers; the picture being placed is shown among them
@export var sprite_holder: Node2D
# Hidden while a picture is placed, so the outfit can't change meanwhile
@export var ui_root: Control
@export var sticker_stage: Node2D
# Shows a short message when a picture can't be used
@export var toolbar: Control

const AICreateDialog = preload("res://script/ai_create_dialog.gd")
const EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]
# Bigger pictures are made smaller first, so they don't slow the game down
const MAX_UPLOAD_SIZE := 2048
# How much of the doll a new picture covers at most when it is first placed
const START_SIZE := 0.6
# Smallest size (in pixels on screen) a picture can be made while placing it
const MIN_SIZE := 16.0
const HANDLE_RADIUS := 11.0
const FRAME_COLOR := Color(0.2, 0.33, 0.85)
# Smallest and biggest eraser (its radius in pixels on screen), and the one it starts with
const BRUSH_SIZES := Vector2(3, 60)
const START_BRUSH := 14.0
# How many strokes the eraser's Undo can take back
const MAX_ERASE_UNDO := 20

# The browser asks for a file with this, and sends back its name and contents (as base64)
const WEB_PICKER := """
window.dressUpPickPicture = (callback) => {
	const input = document.createElement('input');
	input.type = 'file';
	input.accept = '.png,.jpg,.jpeg,.webp,.svg';
	input.onchange = () => {
		const file = input.files[0];
		if (!file) return;
		const reader = new FileReader();
		reader.onload = () => callback(file.name, reader.result.split(',')[1]);
		reader.readAsDataURL(file);
	};
	input.click();
};
"""

enum Drag { NONE, MOVE, RESIZE }

var target_layer := "" # the menu the picture is going to
var file_dialog: FileDialog
var web_callback: JavaScriptObject # kept, or the browser forgets it

# While a doll item is being placed:
var placing := false
var placing_image: Image
var placing_description := ""
var placing_prefix := "upload" # start of the saved file's name, see GeneratedItems.save()
var preview: Sprite2D # shown on the doll, in the layer's place
var layer_sprite: Sprite2D # the layer's own sprite, hidden meanwhile
var drag := Drag.NONE
var drag_start_point := Vector2.ZERO
var drag_start_position := Vector2.ZERO
var drag_start_scale := 1.0
var bar: Control

# While the player erases parts of a picture (see start_erasing):
var erasing := false
var erase_sprite: Sprite2D # shows the picture being erased
var erase_image: Image
var erase_texture: ImageTexture
var erase_restore: Texture2D # the sprite's own texture, put back on Cancel
var erase_done: Callable # gets the erased Image when the player presses Done
var erase_undo := [] # copies of the picture from before each stroke
var painting := false
var paint_from := Vector2.ZERO # the last point erased, in the picture's pixels
var cursor := Vector2.ZERO # where the eraser is drawn, on screen
var erase_bar: Control
var brush_slider: HSlider

func _ready() -> void:
	z_index = 101 # handles show above the stickers (StickerStage is 100)
	SignalBus.dressup_item_signal.connect(func(button, operation):
		if operation == "upload":
			pick_file(button.category))
	get_window().files_dropped.connect(_on_files_dropped)
	sticker_stage.erase_requested.connect(erase_sticker)
	_build_bars()


#####################################
############## PICKING A FILE #######
#####################################

func pick_file(layer:String) -> void:
	target_layer = layer
	if OS.has_feature("web"):
		if web_callback == null:
			JavaScriptBridge.eval(WEB_PICKER, true)
			web_callback = JavaScriptBridge.create_callback(_on_web_file)
		JavaScriptBridge.get_interface("window").dressUpPickPicture(web_callback)
		return
	if file_dialog == null:
		file_dialog = FileDialog.new()
		file_dialog.title = "Choose a picture"
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.use_native_dialog = true
		file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.svg ; Pictures"])
		file_dialog.file_selected.connect(func(path): add_file(path, target_layer))
		add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.7)

func _on_web_file(args:Array) -> void:
	add_picture(Marshalls.base64_to_raw(str(args[1])), str(args[0]), target_layer)

# A file dropped on the window goes to the menu that is open
func _on_files_dropped(files:PackedStringArray) -> void:
	if placing or erasing:
		return
	for tab in interactivity.tab_nodes + [interactivity.sticker_tab]:
		if tab and tab.visible:
			for path in files:
				if path.get_extension().to_lower() in EXTENSIONS:
					add_file(path, tab.layer)
					return

func add_file(path:String, layer:String) -> void:
	add_picture(FileAccess.get_file_as_bytes(path), path.get_file(), layer)


#####################################
############## ADDING A PICTURE #####
#####################################

func add_picture(bytes:PackedByteArray, file_name:String, layer:String) -> void:
	var image = decode(bytes, file_name.get_extension())
	if image == null or image.is_empty():
		toolbar.show_message("That file isn't a picture the game can read (png, jpg, webp or svg).")
		return
	image.convert(Image.FORMAT_RGBA8)
	var longest = maxi(image.get_width(), image.get_height())
	if longest > MAX_UPLOAD_SIZE:
		var factor = float(MAX_UPLOAD_SIZE) / longest
		image.resize(roundi(image.get_width() * factor), roundi(image.get_height() * factor), Image.INTERPOLATE_LANCZOS)
	# "red_beret.png" is described as "red beret", like the game's own items
	var description = file_name.get_basename().replace("_", " ").replace("-", " ").strip_edges()

	if layer == interactivity.STICKERS:
		_add(layer, StickerImage.prepare(image), description)
	elif interactivity.is_background(layer):
		var size = Vector2i(get_viewport_rect().size)
		_add(layer, AICreateDialog.fit_to_size(image, size), description)
	else:
		place_picture(layer, image, description)

# Puts a picture on the doll so the player can move it into place,
# after taking off a plain background and the empty space around it.
# A picture the size of the doll's images is added straight away.
func place_picture(layer:String, image:Image, description:String, prefix := "upload") -> void:
	image.convert(Image.FORMAT_RGBA8)
	if not StickerImage.has_transparent_corner(image):
		StickerImage.remove_flat_background(image)
	if image.get_size() == doll_size(layer):
		_add(layer, image, description, prefix)
		return
	var used = image.get_used_rect()
	if not used.has_area():
		toolbar.show_message("That picture is empty.")
		return
	start_placing(layer, image.get_region(used), description, prefix)

static func decode(bytes:PackedByteArray, extension:String) -> Image:
	if extension.to_lower() == "svg":
		var image := Image.new()
		return image if image.load_svg_from_buffer(bytes) == OK else null
	return OpenRouterClient.decode_image(bytes)

func _add(layer:String, image:Image, description:String, prefix := "upload") -> void:
	var path = GeneratedItems.save(layer, image, description, prefix)
	if path == "":
		toolbar.show_message("The picture couldn't be saved.")
		return
	var picture = ImageTexture.create_from_image(image)
	if layer == interactivity.STICKERS:
		interactivity.add_runtime_sticker(picture, path)
	else:
		interactivity.add_runtime_item(layer, picture, path)
	Sfx.play("sparkle")

# The size in pixels of the doll's images (they are all the same size):
# the size of an item in this layer, or in another layer of the doll
func doll_size(layer:String) -> Vector2i:
	var order = [layer] + interactivity.layers.filter(func(other): return not interactivity.is_background(other))
	for other in order:
		var tab = interactivity.tab_nodes[interactivity.layers.find(other)]
		for id in tab.get_item_ids():
			var button = tab.get_item_button(id)
			if button and button.image:
				return Vector2i(button.image.get_size())
	return Vector2i(get_viewport_rect().size)


#####################################
############## PLACING ON THE DOLL ##
#####################################

func start_placing(layer:String, image:Image, description:String, prefix := "upload") -> void:
	if placing:
		cancel_placing()
	target_layer = layer
	placing_image = image
	placing_description = description
	placing_prefix = prefix
	layer_sprite = interactivity.layer_nodes[interactivity.layers.find(layer)]

	preview = Sprite2D.new()
	preview.texture = ImageTexture.create_from_image(image)
	preview.z_index = layer_sprite.z_index
	preview.material = layer_sprite.material # so it shows the layer's color too
	sprite_holder.add_child(preview)
	layer_sprite.hide()

	var doll = _doll_rect()
	var picture_size = Vector2(image.get_size())
	var base = _base_scale()
	preview.position = doll.get_center()
	preview.scale = Vector2.ONE * minf(base.x, START_SIZE * minf(doll.size.x / picture_size.x, doll.size.y / picture_size.y))

	placing = true
	ui_root.hide()
	sticker_stage.deselect()
	sticker_stage.hide()
	bar.show()
	queue_redraw()

func finish_placing() -> void:
	if not placing:
		return
	var image = _bake()
	_end_placing()
	_add(target_layer, image, placing_description, placing_prefix)

func cancel_placing() -> void:
	if placing:
		_end_placing()

func _end_placing() -> void:
	placing = false
	drag = Drag.NONE
	preview.queue_free()
	layer_sprite.visible = layer_sprite.texture != null
	ui_root.show()
	sticker_stage.show()
	bar.hide()
	queue_redraw()

# Draws the picture onto an empty image the size of the doll's images,
# where it was placed on the doll
func _bake() -> Image:
	var size = doll_size(target_layer)
	var canvas = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var factor = preview.scale / _base_scale()
	var picture: Image = placing_image.duplicate()
	var new_size = Vector2i((Vector2(picture.get_size()) * factor).round()).max(Vector2i.ONE)
	picture.resize(new_size.x, new_size.y, Image.INTERPOLATE_LANCZOS)
	var top_left = preview.position - preview.texture.get_size() * preview.scale / 2
	var corner = (top_left - _doll_rect().position) / _base_scale()
	canvas.blend_rect(picture, Rect2i(Vector2i.ZERO, new_size), Vector2i(corner.round()))
	return canvas

# The layer's scale, without the little "pop" when an item is put on
func _base_scale() -> Vector2:
	return layer_sprite.get_meta("base_scale", layer_sprite.scale)

# Where the doll's images are, in the sprite holder
func _doll_rect() -> Rect2:
	var size = Vector2(doll_size(target_layer)) * _base_scale()
	var center = layer_sprite.position + layer_sprite.offset * _base_scale()
	return Rect2(center - size / 2, size)

# The picture's corners on screen: top-left, top-right, bottom-right, bottom-left
func _corners() -> Array:
	var half = preview.texture.get_size() * preview.scale / 2
	var to_screen = sprite_holder.get_global_transform()
	return [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)].map(
		func(corner): return to_screen * (preview.position + corner * half))

func _resize(factor:float, from_scale:float) -> void:
	var smallest = MIN_SIZE / maxf(preview.texture.get_width(), preview.texture.get_height())
	var largest = 3.0 * maxf(_doll_rect().size.x / preview.texture.get_width(), _doll_rect().size.y / preview.texture.get_height())
	preview.scale = Vector2.ONE * clampf(from_scale * factor, smallest, maxf(smallest, largest))
	queue_redraw()

func _unhandled_input(event:InputEvent) -> void:
	if not placing and not erasing:
		return
	# nothing else (stickers, undo...) reacts while a picture is being placed or erased
	get_viewport().set_input_as_handled()
	var point = get_canvas_transform().affine_inverse() * event.position if event is InputEventMouse else Vector2.ZERO
	if erasing:
		_erase_input(event, point)
		return
	var to_holder = sprite_holder.get_global_transform().affine_inverse()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			drag = Drag.NONE
			return
		drag_start_point = point
		drag_start_position = preview.position
		drag_start_scale = preview.scale.x
		if point.distance_to(_corners()[2]) <= HANDLE_RADIUS + 3:
			drag = Drag.RESIZE
		elif Rect2(_corners()[0], _corners()[2] - _corners()[0]).has_point(point):
			drag = Drag.MOVE
	elif event is InputEventMouseButton and event.pressed:
		var step = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0
		if step != 0:
			_resize(pow(1.1, step), preview.scale.x)
	elif event is InputEventMouseMotion and drag == Drag.MOVE:
		preview.position = drag_start_position + to_holder.basis_xform(point - drag_start_point)
		queue_redraw()
	elif event is InputEventMouseMotion and drag == Drag.RESIZE:
		var center = sprite_holder.get_global_transform() * drag_start_position
		var start_distance = drag_start_point.distance_to(center)
		if start_distance > 1:
			_resize(point.distance_to(center) / start_distance, drag_start_scale)
	elif event is InputEventMagnifyGesture:
		_resize(event.factor, preview.scale.x)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			finish_placing()
		elif event.keycode == KEY_ESCAPE:
			cancel_placing()

func _draw() -> void:
	if erasing:
		_draw_eraser()
		return
	if not placing:
		return
	var corners = _corners()
	draw_polyline(corners + [corners[0]], FRAME_COLOR, 2.0, true)
	# resize handle, like the stickers' one
	draw_circle(corners[2], HANDLE_RADIUS, Color.WHITE)
	draw_circle(corners[2], HANDLE_RADIUS, FRAME_COLOR, false, 2.0, true)
	draw_arc(corners[2], HANDLE_RADIUS * 0.5, -PI * 0.25, PI * 1.25, 12, FRAME_COLOR, 2.0, true)

# The strips at the top of the screen with a hint and buttons:
# one for placing a picture, one for erasing
func _build_bars() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	bar = _make_bar(layer, "Drag your picture into place. Scroll or drag the corner to resize.",
		[["Erase", _erase_placing], ["Cancel", cancel_placing], ["Done", finish_placing]])
	erase_bar = _make_bar(layer, "Paint over the parts to erase.",
		[["Undo", undo_erase], ["Cancel", cancel_erasing], ["Done", finish_erasing]])
	brush_slider = HSlider.new()
	brush_slider.min_value = BRUSH_SIZES.x
	brush_slider.max_value = BRUSH_SIZES.y
	brush_slider.value = START_BRUSH
	brush_slider.custom_minimum_size = Vector2(90, 0)
	brush_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_slider.focus_mode = Control.FOCUS_NONE
	brush_slider.tooltip_text = "Eraser size (or scroll)"
	brush_slider.value_changed.connect(func(_value): queue_redraw())
	var row = erase_bar.get_child(0).get_child(0)
	row.add_child(brush_slider)
	row.move_child(brush_slider, 1)

func _make_bar(layer:CanvasLayer, text:String, choices:Array) -> Control:
	var holder = MarginContainer.new()
	holder.theme = preload("res://theme.tres")
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.add_theme_constant_override("margin_top", 12)
	layer.add_child(holder)
	var panel = PanelContainer.new()
	panel.theme_type_variation = &"Toast"
	holder.add_child(panel)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var hint = Label.new()
	hint.theme_type_variation = &"ToastLabel"
	hint.text = text
	row.add_child(hint)
	for choice in choices:
		var button = Button.new()
		button.theme_type_variation = &"ToolButton"
		button.text = choice[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(choice[1])
		row.add_child(button)
	holder.hide()
	return holder


#####################################
############## ERASING ##############
#####################################

# Lets the player rub out parts of the picture shown by sprite, right where it is on the doll.
# on_done gets the erased picture (a copy: image itself doesn't change).
func start_erasing(sprite:Sprite2D, image:Image, on_done:Callable) -> void:
	erase_sprite = sprite
	erase_image = image.duplicate()
	if erase_image.is_compressed():
		erase_image.decompress()
	erase_image.convert(Image.FORMAT_RGBA8)
	erase_texture = ImageTexture.create_from_image(erase_image)
	erase_restore = sprite.texture
	sprite.texture = erase_texture
	erase_done = on_done
	erase_undo.clear()
	painting = false
	erasing = true
	ui_root.hide()
	sticker_stage.deselect()
	bar.hide()
	erase_bar.show()
	queue_redraw()

# The Erase button while placing a picture on the doll
func _erase_placing() -> void:
	start_erasing(preview, placing_image, func(image): placing_image = image)

# The eraser handle on a sticker. Every copy of that sticker on the doll changes.
# The game's own stickers aren't changed: the erased one is added as a new sticker.
func erase_sticker(index:int) -> void:
	if placing or erasing or index >= len(sticker_stage.stickers):
		return
	var id: String = sticker_stage.stickers[index].id
	var button = interactivity.sticker_tab.get_item_button(id)
	var image = button.image.get_image() if button and button.image else null
	if image == null or image.is_empty():
		return
	start_erasing(sticker_stage.sprites[index], image, func(erased): _save_erased_sticker(button, index, erased))

func _save_erased_sticker(button:Button, index:int, image:Image) -> void:
	var picture = ImageTexture.create_from_image(image)
	var id: String = button.item_id
	if id.begins_with(GeneratedItems.ROOT):
		if image.save_png(id) != OK:
			toolbar.show_message("The sticker couldn't be saved.")
		else:
			button.show_picture(picture)
		sticker_stage.show_stickers(interactivity.outfit[interactivity.STICKERS])
	else:
		var path = GeneratedItems.save(interactivity.STICKERS, image, interactivity.sticker_tab.item_label(id), "upload")
		if path == "":
			toolbar.show_message("The sticker couldn't be saved.")
			sticker_stage.show_stickers(interactivity.outfit[interactivity.STICKERS])
			return
		interactivity.sticker_tab.add_item(picture, path)
		var stickers = interactivity.outfit[interactivity.STICKERS].duplicate(true)
		stickers[index].id = path
		interactivity.set_stickers(stickers)
	Sfx.play("sparkle")

func finish_erasing() -> void:
	if not erasing:
		return
	var on_done = erase_done
	var image = erase_image
	_end_erasing()
	on_done.call(image)

func cancel_erasing() -> void:
	if not erasing:
		return
	erase_sprite.texture = erase_restore
	_end_erasing()

# Takes back the last stroke
func undo_erase() -> void:
	if erase_undo.is_empty():
		return
	erase_image = erase_undo.pop_back()
	erase_texture.update(erase_image)

func _end_erasing() -> void:
	erasing = false
	painting = false
	erase_undo.clear()
	erase_bar.hide()
	# back to placing the picture, if that's where the eraser was started
	bar.visible = placing
	ui_root.visible = not placing
	queue_redraw()

func _erase_input(event:InputEvent, point:Vector2) -> void:
	if event is InputEventMouse:
		cursor = point
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		painting = event.pressed
		if painting:
			erase_undo.append(erase_image.duplicate())
			if len(erase_undo) > MAX_ERASE_UNDO:
				erase_undo.pop_front()
			paint_from = _to_picture(point)
			_paint(paint_from)
	elif event is InputEventMouseButton and event.pressed:
		var step = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0
		brush_slider.value *= pow(1.15, step)
	elif event is InputEventMouseMotion and painting:
		_paint(_to_picture(point))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			finish_erasing()
		elif event.keycode == KEY_ESCAPE:
			cancel_erasing()
		elif event.keycode == KEY_Z and event.is_command_or_control_pressed():
			undo_erase()

# Erases from the last point to this one (in the picture's pixels)
func _paint(to:Vector2) -> void:
	var radius = brush_slider.value / absf(erase_sprite.get_global_transform().get_scale().x)
	erase_line(erase_image, paint_from, to, radius)
	erase_texture.update(erase_image)
	paint_from = to

# A point on screen, in the pixels of the picture being erased
func _to_picture(point:Vector2) -> Vector2:
	var local = erase_sprite.get_global_transform().affine_inverse() * point
	if erase_sprite.flip_h:
		local.x = -local.x
	return local + erase_texture.get_size() / 2

# Clears the picture along a line with round ends, with a soft edge one pixel wide
static func erase_line(image:Image, from:Vector2, to:Vector2, radius:float) -> void:
	var area = Rect2(from, Vector2.ZERO).expand(to).grow(radius + 1)
	var pixels = Rect2i(Vector2i(area.position.floor()), Vector2i(area.size.ceil()) + Vector2i.ONE) \
		.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(pixels.position.y, pixels.end.y):
		for x in range(pixels.position.x, pixels.end.x):
			var middle = Vector2(x + 0.5, y + 0.5)
			var distance = middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, from, to))
			var keep = clampf(distance - radius + 0.5, 0.0, 1.0)
			if keep < 1.0:
				var color = image.get_pixel(x, y)
				if color.a > 0.0:
					color.a *= keep
					image.set_pixel(x, y, color)

# A frame around the picture, and the eraser's size where the pointer is
func _draw_eraser() -> void:
	var half = erase_texture.get_size() / 2
	var to_screen = erase_sprite.get_global_transform()
	var corners = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)].map(
		func(corner): return to_screen * (corner * half))
	draw_polyline(corners + [corners[0]], Color(FRAME_COLOR, 0.5), 1.5, true)
	draw_circle(cursor, brush_slider.value, Color(1, 1, 1, 0.25))
	draw_circle(cursor, brush_slider.value, Color.WHITE, false, 2.5, true)
	draw_circle(cursor, brush_slider.value, FRAME_COLOR, false, 1.2, true)
