# Pop-up that lists saved outfits. Click a picture to wear that outfit again.

extends OverlayDialog

@export var interactivity: Node

@onready var grid: GridContainer = %Grid
@onready var empty_label: Label = %EmptyLabel

func _ready() -> void:
	super()
	%CloseButton.pressed.connect(close)

func _on_open() -> void:
	refresh()

func refresh() -> void:
	for card in grid.get_children():
		card.queue_free()
	var outfits = OutfitStore.load_all()
	empty_label.visible = outfits.is_empty()
	for entry in outfits:
		var card := VBoxContainer.new()

		var wear := Button.new()
		wear.theme_type_variation = &"ToolButton"
		wear.custom_minimum_size = Vector2(150, 100)
		wear.icon = GeneratedItems.load_texture(entry.thumbnail)
		wear.expand_icon = true
		wear.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wear.tooltip_text = "Wear this outfit"
		wear.pressed.connect(func():
			interactivity.set_outfit(entry.outfit)
			close())
		card.add_child(wear)

		var delete := Button.new()
		delete.theme_type_variation = &"ToolButton"
		delete.text = "Delete"
		delete.pressed.connect(func():
			OutfitStore.delete_outfit(entry.id)
			refresh())
		card.add_child(delete)

		grid.add_child(card)
