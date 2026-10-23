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

func _ready() -> void:
	if operation == "item":
		texture_rect = $TextureRect

func resize_to_picture()->void:
	image = icon
	texture_rect.texture = image
	texture_rect.size = self.size
	icon = BUTTON_BG

func _on_button_pressed():
	#When button is pressed, it sends a signal to the global "SignalBus" ( script/signalbus.gd )
	SignalBus.dressup_item_signal.emit(self, operation)
