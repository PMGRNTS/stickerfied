# This code is used for the buttons that display category (skin, face, hair..),
# as well as the ones showing items (such as specific hair: bob, curly, straight...).

extends Button

@export_enum("item", "category") var operation: String
var category : String
@onready var texture_rect: TextureRect
const BUTTON_BG = preload("uid://dhbs2i3tsygun")

# The texture that is read when updating item sprites,
# for example when choosing a different hat:
var image : Texture2D

# Name used to remember this item in saved outfits and share codes.
# It is the file name (such as "bob.PNG"), the full path for AI generated
# items, or "" for the "nothing" button.
var item_id : String

func _ready() -> void:
	if operation == "item":
		texture_rect = $TextureRect

# Shows the picture inside the button. The picture also becomes
# the texture used on the doll when this button is pressed.
func show_picture(picture: Texture2D) -> void:
	image = picture
	texture_rect.texture = zoomed_to_content(picture)
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon = BUTTON_BG

# Dress-up images are mostly empty space (a hair clip on a whole-doll canvas),
# so the button only shows the part of the image that has something drawn on it
static func zoomed_to_content(picture: Texture2D) -> Texture2D:
	var picture_image = picture.get_image()
	if picture_image == null or picture_image.is_compressed():
		return picture
	var full = Rect2i(Vector2i.ZERO, picture_image.get_size())
	var used = picture_image.get_used_rect()
	if not used.has_area() or used == full:
		return picture
	var zoomed = AtlasTexture.new()
	zoomed.atlas = picture
	zoomed.region = Rect2(used.grow(4).intersection(full))
	return zoomed

# A small "x" in the corner, for items made while playing (such as AI backgrounds)
func add_delete_button() -> void:
	var delete = Button.new()
	delete.theme_type_variation = &"DeleteButton"
	delete.text = "x"
	delete.tooltip_text = "Delete"
	delete.focus_mode = Control.FOCUS_NONE
	add_child(delete)
	delete.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	delete.offset_left = -24
	delete.offset_top = 6
	delete.offset_right = -6
	delete.offset_bottom = 24
	delete.pressed.connect(func(): SignalBus.dressup_item_signal.emit(self, "delete"))

# Draws a frame around the button when its item is being worn
func set_selected(selected: bool) -> void:
	if has_node("Selected"):
		$Selected.visible = selected

func _on_button_pressed():
	#When button is pressed, it sends a signal to the global "SignalBus" ( script/signalbus.gd )
	SignalBus.dressup_item_signal.emit(self, operation)
