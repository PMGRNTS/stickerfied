# This code is responsible for what happens when user presses a button
# It uses dressup_item_signal to listen for button presses
# and hides/shows elements based on what was pressed.
#
# It also remembers the current outfit, so it can be undone, randomized,
# saved and shared. An outfit is a Dictionary that looks like this:
#   { "03Hair": {"item": "bob.PNG", "hue": -1.0}, "01Skin": {...}, ... }
# "item" is "" when nothing is worn on that layer,
# "hue" is -1 for original colors, or 0..1 for a recolor.
# Stickers placed on the doll are kept in a list under "_stickers":
#   "_stickers": [{"id": "heart.svg", "x": 250, "y": 120, "scale": 0.5, "rot": 0.3}, ...]
# (x and y are screen positions, rot is the rotation in radians)

extends Node

signal outfit_changed

const NO_COLOR := -1.0
const MAX_UNDO := 50
const STICKERS := "_stickers"
const MAX_STICKERS := 30
const STICKER_SCALE_LIMITS := Vector2(0.1, 6.0)
# How big (in pixels) a new sticker is when it is first put on the doll
const NEW_STICKER_SIZE := 110.0

var layers :=[] #layer names (folder names)
var layer_nodes:=[] #access to sprite layers
var tab_nodes:=[] # access to tabs of buttons (node that contains all options for a category)
var sticker_tab: Node # tab of buttons with the sticker choices
@export var sticker_stage: Node2D # shows the stickers and lets the player move them

var outfit := {}
var undo_stack := []
var redo_stack := []

var delete_dialog: ConfirmationDialog
var button_to_delete: Button
var sounds_on := false # no sounds while the game is setting up

func _ready():
	SignalBus.dressup_item_signal.connect(_on_button_press)
	SignalBus.dressup_color_signal.connect(_on_color_press)

func start_game()->void:
	outfit = starting_outfit()
	apply_outfit(false)
	# fake pressing a button to hide unnecessary elements
	SignalBus.dressup_item_signal.emit( get_tree().get_first_node_in_group("category_button") , "category")
	sounds_on = true

func _on_button_press(node_pressed:Node, operation_name:String):
	#print_debug(node_pressed.name, operation_name)

	# user selected a category
	if operation_name == "category":
		for i in tab_nodes + [sticker_tab]:
			if i:
				i.visible = i.layer == node_pressed.category
		if sounds_on:
			Sfx.play("click")
	# user selected an item, such as a specific hair or makeup item
	if operation_name == "item" and node_pressed.category == STICKERS:
		add_sticker(node_pressed.item_id)
	elif operation_name == "item":
		var new_outfit = outfit.duplicate(true)
		new_outfit[node_pressed.category].item = node_pressed.item_id
		set_outfit(new_outfit)
	# user pressed the small "x" on an item made while playing
	if operation_name == "delete":
		confirm_delete(node_pressed)

func _on_color_press(layer:String, hue:float):
	var new_outfit = outfit.duplicate(true)
	new_outfit[layer].hue = hue
	set_outfit(new_outfit)
	Sfx.play("click")


#####################################
############## OUTFIT CHANGES #######
#####################################

func empty_outfit() -> Dictionary:
	var result := {}
	for layer in layers:
		result[layer] = {"item": "", "hue": NO_COLOR}
	result[STICKERS] = []
	return result

# The first background and the doll's body, nothing else
func starting_outfit() -> Dictionary:
	var result := empty_outfit()
	for i in len(layers):
		if is_required(layers[i]):
			var ids = tab_nodes[i].get_item_ids()
			if not ids.is_empty():
				result[layers[i]].item = ids[0]
	return result

# Use this to change the outfit, so the change can be undone
func set_outfit(new_outfit:Dictionary) -> void:
	new_outfit = cleaned_outfit(new_outfit)
	if new_outfit == outfit:
		return
	undo_stack.append(outfit)
	if len(undo_stack) > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()
	outfit = new_outfit
	apply_outfit()

func undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(outfit)
	outfit = cleaned_outfit(undo_stack.pop_back())
	apply_outfit()

func redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(outfit)
	outfit = cleaned_outfit(redo_stack.pop_back())
	apply_outfit()

func reset() -> void:
	set_outfit(starting_outfit())

# Picks a random item for every layer, and sometimes a random color
func randomize_outfit() -> void:
	var new_outfit := empty_outfit()
	for i in len(layers):
		var ids = tab_nodes[i].get_item_ids()
		if ids.is_empty():
			continue
		if not is_required(layers[i]) and randf() < 0.15:
			continue # sometimes leave optional layers empty
		new_outfit[layers[i]].item = ids.pick_random()
		if not is_background(layers[i]) and randf() < 0.3:
			new_outfit[layers[i]].hue = tab_nodes[i].SWATCH_HUES.slice(1).pick_random()
	new_outfit[STICKERS] = outfit[STICKERS].duplicate(true) # stickers stay where they are
	set_outfit(new_outfit)

# Adds an item that was created while playing (such as an AI background)
# and puts it on straight away
func add_runtime_item(layer:String, picture:Texture2D, id:String) -> void:
	var tab = tab_nodes[layers.find(layer)]
	tab.add_item(picture, id)
	var new_outfit = outfit.duplicate(true)
	new_outfit[layer].item = id
	set_outfit(new_outfit)

# Adds a sticker image that was made while playing, and puts it on the doll
func add_runtime_sticker(picture:Texture2D, id:String) -> void:
	sticker_tab.add_item(picture, id)
	add_sticker(id)

# Puts a sticker on the doll, near its middle, and selects it so it can be moved
func add_sticker(id:String) -> void:
	var button = sticker_tab.get_item_button(id)
	if button == null or button.image == null:
		return
	var new_outfit = outfit.duplicate(true)
	var position = sticker_stage.new_sticker_position()
	var picture_size = button.image.get_size()
	new_outfit[STICKERS].append({"id": id, "x": position.x, "y": position.y,
		"scale": NEW_STICKER_SIZE / maxf(picture_size.x, picture_size.y), "rot": 0.0})
	set_outfit(new_outfit)
	sticker_stage.select(len(outfit[STICKERS]) - 1)
	if sounds_on:
		Sfx.play("pop")

# Used by the sticker stage after the player moves, turns or removes stickers
func set_stickers(stickers:Array) -> void:
	var new_outfit = outfit.duplicate(true)
	new_outfit[STICKERS] = stickers
	set_outfit(new_outfit)

# Asks before deleting, since the picture can't be brought back
func confirm_delete(button:Button) -> void:
	if delete_dialog == null:
		delete_dialog = ConfirmationDialog.new()
		delete_dialog.title = "Delete picture"
		delete_dialog.dialog_text = "Delete this picture? This can't be undone."
		delete_dialog.ok_button_text = "Delete"
		delete_dialog.confirmed.connect(func(): delete_item(button_to_delete))
		add_child(delete_dialog)
	button_to_delete = button
	delete_dialog.popup_centered()

func delete_item(button:Button) -> void:
	if not is_instance_valid(button):
		return
	GeneratedItems.delete(button.item_id)
	button.queue_free()
	# if it was being worn, the layer goes back to its first item (or nothing)
	set_outfit(outfit)

# Makes sure an outfit (for example one loaded from a share code)
# only contains layers and items that exist in this game
func cleaned_outfit(new_outfit:Dictionary) -> Dictionary:
	var result := empty_outfit()
	for i in len(layers):
		var entry = new_outfit.get(layers[i])
		if not entry is Dictionary:
			entry = {}
		var id = str(entry.get("item", ""))
		if id != "" and tab_nodes[i].get_item_button(id) == null:
			id = ""
		if id == "" and is_required(layers[i]):
			id = starting_outfit()[layers[i]].item
		var hue = float(entry.get("hue", NO_COLOR))
		result[layers[i]] = {"item": id, "hue": clampf(hue, 0.0, 1.0) if hue >= 0 else NO_COLOR}
	
	# Stickers whose picture doesn't exist (anymore) are left out
	var given = new_outfit.get(STICKERS)
	for sticker in given if given is Array else []:
		if not sticker is Dictionary or sticker_tab == null:
			continue
		var id = str(sticker.get("id", ""))
		if sticker_tab.get_item_button(id) == null:
			continue
		result[STICKERS].append({
			"id": id,
			"x": snappedf(float(sticker.get("x", 0.0)), 0.1),
			"y": snappedf(float(sticker.get("y", 0.0)), 0.1),
			"scale": snappedf(clampf(float(sticker.get("scale", 1.0)), STICKER_SCALE_LIMITS.x, STICKER_SCALE_LIMITS.y), 0.001),
			"rot": snappedf(wrapf(float(sticker.get("rot", 0.0)), -PI, PI), 0.001),
		})
	result[STICKERS] = result[STICKERS].slice(-MAX_STICKERS)
	return result

static func is_background(layer:String) -> bool:
	return layer.begins_with("00")

# Backgrounds and the doll's body (the first layer after the backgrounds)
# always show something, so they don't get a "nothing" button
func is_required(layer:String) -> bool:
	if is_background(layer):
		return true
	for other in layers:
		if not is_background(other):
			return other == layer
	return false


#####################################
############## DISPLAY ##############
#####################################

# Updates sprites and buttons to show the current outfit
func apply_outfit(animate := true) -> void:
	var any_changed := false
	for i in len(layers):
		var entry = outfit[layers[i]]
		var sprite: Sprite2D = layer_nodes[i]
		var button = tab_nodes[i].get_item_button(entry.item)
		var new_texture = button.image if button else null
		var changed = sprite.texture != new_texture or sprite.visible != (new_texture != null)

		sprite.texture = new_texture
		sprite.visible = new_texture != null
		if sprite.material:
			sprite.material.set_shader_parameter("enabled", entry.hue >= 0)
			sprite.material.set_shader_parameter("target_hue", maxf(entry.hue, 0.0))
		tab_nodes[i].show_selected(entry.item, entry.hue)

		if animate and changed and sprite.visible:
			play_swap_animation(sprite)
			any_changed = true
	if sticker_stage:
		sticker_stage.show_stickers(outfit[STICKERS])
	if any_changed and sounds_on:
		Sfx.play("pop")
	outfit_changed.emit()

# A quick fade and "pop" when an item is put on
func play_swap_animation(sprite:Sprite2D) -> void:
	var base_scale: Vector2 = sprite.get_meta("base_scale", sprite.scale)
	sprite.set_meta("base_scale", base_scale)
	if sprite.has_meta("tween"):
		sprite.get_meta("tween").kill()
	var tween = sprite.create_tween().set_parallel()
	sprite.set_meta("tween", tween)
	sprite.modulate.a = 0.3
	tween.tween_property(sprite, "modulate:a", 1.0, 0.15)
	if not sprite.centered:
		return # backgrounds only fade
	sprite.scale = base_scale * 1.04
	tween.tween_property(sprite, "scale", base_scale, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
