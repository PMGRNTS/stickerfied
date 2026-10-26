# This code is used to create the grid of selectable items for each category

extends VBoxContainer
@export var button_base : PackedScene

const NONE_ICON = preload("res://GUI/none_icon.svg")
const AI_ICON = preload("res://GUI/ai_icon.svg")
# item_id of the "make one with AI" button, so it isn't mistaken for an item
const AI_BUTTON_ID := "::ai"

# Hues offered by the color swatches under the item grid (0 = red, 0.33 = green, 0.66 = blue...)
# Add or remove values to change the swatches. -1 means "original colors".
const SWATCH_HUES := [-1.0, 0.0, 0.06, 0.13, 0.27, 0.42, 0.53, 0.62, 0.74, 0.84, 0.93]

# Folder name of the layer this tab belongs to, such as "03Hair"
var layer : String

@onready var grid: GridContainer = $ScrollContainer/GridContainer
@onready var swatches: HBoxContainer = $Swatches

func _ready() -> void:
	for i in grid.get_children():
		i.queue_free()


func add_item(picture: Texture2D, id: String) -> Button:
	var newbutton = button_base.instantiate()
	newbutton.category = layer
	newbutton.item_id = id
	newbutton.tooltip_text = id.get_file().get_basename()
	grid.add_child(newbutton)
	newbutton.show_picture(picture)
	if id.begins_with(GeneratedItems.ROOT):
		newbutton.add_delete_button()
	return newbutton


# A button that opens the AI window, to make a new item for this tab
func add_ai_button(tooltip:String) -> void:
	var newbutton = add_item(AI_ICON, AI_BUTTON_ID)
	newbutton.image = null
	newbutton.operation = "ai"
	newbutton.tooltip_text = tooltip
	grid.move_child(newbutton, 0)


# A button that takes the item off (hides the layer)
func add_none_button() -> void:
	var newbutton = add_item(NONE_ICON, "")
	newbutton.image = null
	newbutton.tooltip_text = "Nothing"
	grid.move_child(newbutton, 0)


func get_item_button(id: String) -> Button:
	for button in grid.get_children():
		if button.item_id == id and not button.is_queued_for_deletion():
			return button
	return null


# All item names in this tab, not counting the "nothing" button
func get_item_ids() -> Array:
	var ids := []
	for button in grid.get_children():
		if button.item_id not in ["", AI_BUTTON_ID] and not button.is_queued_for_deletion():
			ids.append(button.item_id)
	return ids


func add_color_swatches() -> void:
	for hue in SWATCH_HUES:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.set_meta("hue", hue)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.set_border_width_all(2)
		if hue < 0:
			style.bg_color = Color.WHITE
			style.border_color = Color(0.6, 0.6, 0.6)
			swatch.tooltip_text = "Original colors"
		else:
			style.bg_color = Color.from_hsv(hue, 0.7, 0.95)
			style.border_color = style.bg_color
		for state in ["normal", "hover", "pressed", "focus"]:
			swatch.add_theme_stylebox_override(state, style)
		swatch.pressed.connect(func(): SignalBus.dressup_color_signal.emit(layer, hue))
		swatches.add_child(swatch)


# Highlights the item and color currently worn on this layer
func show_selected(id: String, hue: float) -> void:
	for button in grid.get_children():
		button.set_selected(button.item_id == id)
	for swatch in swatches.get_children():
		var style: StyleBoxFlat = swatch.get_theme_stylebox("normal")
		var chosen = is_equal_approx(swatch.get_meta("hue"), hue)
		style.border_color = Color(0.11, 0.2, 0.45) if chosen else (
			Color(0.6, 0.6, 0.6) if swatch.get_meta("hue") < 0 else style.bg_color)
