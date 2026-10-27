# The Body menu: sliders that reshape the doll (see body_shaper.gd).
# Dragging a slider shows the change straight away; letting go puts it on, so it can be undone.
# Double-clicking a slider puts it back in the middle (as drawn).
# Fit points lets the player move the sliders' controls onto their doll (see body_fitter.gd),
# and Sculpt lets them push the doll into any shape (see body_sculptor.gd).

extends VBoxContainer

signal fit_requested
signal sculpt_requested

const TEXT_COLOR := Color(0.16, 0.13, 0.33)

# Used like a layer name, so the category button shows this menu
var layer := "_body"
var values := {} # slider name -> -1..1, as worn now
var sliders := {} # slider name -> HSlider

# groups comes from body_shaper.gd's slider_groups()
func build(groups:Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(250, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new() # keeps the sliders' ends clear of the scroll bar
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	scroll.add_child(margin)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	margin.add_child(list)

	for entry in groups:
		var heading := Label.new()
		heading.text = entry.group
		heading.add_theme_font_size_override("font_size", 15)
		list.add_child(heading)
		for slider_name in entry.sliders:
			list.add_child(_slider_row(slider_name))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	add_child(buttons)
	var reset := Button.new()
	reset.theme_type_variation = &"ToolButton"
	reset.text = "As drawn"
	reset.tooltip_text = "Put every slider back in the middle and take off the sculpting"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func(): SignalBus.dressup_body_signal.emit({}))
	buttons.add_child(reset)
	var fit := Button.new()
	fit.theme_type_variation = &"ToolButton"
	fit.text = "Fit points"
	fit.tooltip_text = "Move the sliders' points onto the parts of your doll"
	fit.focus_mode = Control.FOCUS_NONE
	fit.pressed.connect(fit_requested.emit)
	buttons.add_child(fit)
	var sculpt := Button.new()
	sculpt.theme_type_variation = &"ToolButton"
	sculpt.text = "Sculpt"
	sculpt.tooltip_text = "Push the doll into any shape with a brush"
	sculpt.focus_mode = Control.FOCUS_NONE
	sculpt.pressed.connect(sculpt_requested.emit)
	buttons.add_child(sculpt)

func _slider_row(slider_name:String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = slider_name
	label.custom_minimum_size = Vector2(88, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = -1.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = slider_name + " (double-click for as drawn)"
	slider.value_changed.connect(func(value):
		SignalBus.dressup_body_preview_signal.emit(_with(slider_name, value)))
	slider.drag_started.connect(func(): slider.set_meta("dragging", true))
	slider.drag_ended.connect(func(_changed):
		slider.remove_meta("dragging")
		SignalBus.dressup_body_signal.emit(_with(slider_name, slider.value)))
	slider.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.double_click:
			slider.accept_event() # so the slider doesn't start dragging
			SignalBus.dressup_body_signal.emit(_with(slider_name, 0.0)))
	row.add_child(slider)
	sliders[slider_name] = slider
	return row

# The values worn now, with one slider changed
func _with(slider_name:String, value:float) -> Dictionary:
	var result = values.duplicate()
	result[slider_name] = value
	return result

# Moves the sliders to the values worn now
func show_values(new_values:Dictionary) -> void:
	values = new_values.duplicate()
	for slider_name in sliders:
		if not sliders[slider_name].has_meta("dragging"):
			sliders[slider_name].set_value_no_signal(values.get(slider_name, 0.0))
