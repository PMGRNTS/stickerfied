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
# Names for the swatches above, in the same order. Shown as tooltips and used by the AI Stylist.
const SWATCH_NAMES := ["original", "red", "orange", "yellow", "green", "teal", "sky blue",
	"blue", "purple", "pink", "rose"]
const TEXT_COLOR := Color(0.16, 0.13, 0.33)

# Folder name of the layer this tab belongs to, such as "03Hair"
var layer : String

@onready var grid: GridContainer = $ScrollContainer/GridContainer
@onready var swatches: HBoxContainer = $Swatches
var keep_box: CheckBox
var hue_slider: HSlider

func _ready() -> void:
	for i in grid.get_children():
		i.queue_free()


func add_item(picture: Texture2D, id: String) -> Button:
	var newbutton = button_base.instantiate()
	newbutton.category = layer
	newbutton.item_id = id
	newbutton.tooltip_text = item_label(id)
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
			swatch.tooltip_text = SWATCH_NAMES[SWATCH_HUES.find(hue)].capitalize()
		for state in ["normal", "hover", "pressed", "focus"]:
			swatch.add_theme_stylebox_override(state, style)
		swatch.pressed.connect(func(): SignalBus.dressup_color_signal.emit(layer, hue))
		swatches.add_child(swatch)


# A name for an item, such as "bob curly" for bob_curly.PNG,
# or the description of a picture made with AI
static func item_label(id: String) -> String:
	var description = GeneratedItems.describe(id)
	if description != "":
		return description
	if id.begins_with(GeneratedItems.ROOT):
		return "AI picture"
	return id.get_file().get_basename().replace("_", " ").replace("-", " ")


# A row under the swatches with a "Keep" box (Random leaves this layer alone)
# and, for layers that can be recolored, a rainbow slider for any color.
func add_options(can_recolor: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	keep_box = CheckBox.new()
	keep_box.text = "Keep"
	keep_box.tooltip_text = "Keep this when picking a random outfit"
	keep_box.focus_mode = Control.FOCUS_NONE
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		keep_box.add_theme_color_override(state, TEXT_COLOR)
	row.add_child(keep_box)
	if not can_recolor:
		return

	hue_slider = HSlider.new()
	hue_slider.min_value = 0.0
	hue_slider.max_value = 1.0
	hue_slider.step = 0.005
	hue_slider.scrollable = false
	hue_slider.focus_mode = Control.FOCUS_NONE
	hue_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hue_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hue_slider.tooltip_text = "Pick any color"
	var rainbow := Gradient.new()
	rainbow.offsets = PackedFloat32Array([0.0, 1.0 / 6, 2.0 / 6, 3.0 / 6, 4.0 / 6, 5.0 / 6, 1.0])
	rainbow.colors = PackedColorArray(range(7).map(func(i): return Color.from_hsv(i / 6.0, 0.7, 0.95)))
	var track := GradientTexture2D.new()
	track.gradient = rainbow
	track.width = 128
	track.height = 8
	var track_style := StyleBoxTexture.new()
	track_style.texture = track
	track_style.content_margin_top = 4
	track_style.content_margin_bottom = 4
	hue_slider.add_theme_stylebox_override("slider", track_style)
	hue_slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	hue_slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	# while dragging, the doll shows the color; letting go puts it on (so it can be undone)
	hue_slider.value_changed.connect(func(value):
		if hue_slider.has_meta("dragging"):
			SignalBus.dressup_color_preview_signal.emit(layer, value))
	hue_slider.drag_started.connect(func(): hue_slider.set_meta("dragging", true))
	hue_slider.drag_ended.connect(func(_changed):
		hue_slider.remove_meta("dragging")
		SignalBus.dressup_color_signal.emit(layer, hue_slider.value))
	row.add_child(hue_slider)


func is_kept() -> bool:
	return keep_box != null and keep_box.button_pressed


# Highlights the item and color currently worn on this layer
func show_selected(id: String, hue: float) -> void:
	for button in grid.get_children():
		button.set_selected(button.item_id == id)
	if hue_slider and hue >= 0 and not hue_slider.has_meta("dragging"):
		hue_slider.set_value_no_signal(hue)
	for swatch in swatches.get_children():
		var style: StyleBoxFlat = swatch.get_theme_stylebox("normal")
		var chosen = is_equal_approx(swatch.get_meta("hue"), hue)
		style.border_color = Color(0.11, 0.2, 0.45) if chosen else (
			Color(0.6, 0.6, 0.6) if swatch.get_meta("hue") < 0 else style.bg_color)
