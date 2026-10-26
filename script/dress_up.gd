# This code is run at the start of the game
# it reads the images folder
# and uses that information to create the necessary sprites and menu elements

extends Node

@onready var dressup_menu: Control = %DressupMenu
@onready var sprite_placeholder: Sprite2D = %SpritePlaceholder
@onready var sprite_holder: Node2D = %SpriteHolder

@onready var category_buttons: HBoxContainer = %CategoryButtons
@onready var tabs_of_items_container: CenterContainer = %TabsOfItemsContainer
@onready var interactivity: Node = %Interactivity


@onready var category_scroll: ScrollContainer = $DressupMenu/ButtonTray/VBoxContainer/ScrollContainer

@export var button_base : PackedScene
@export var category_button : PackedScene
@export var tab_of_buttons:PackedScene

const IMAGE_FOLDER := "res://images/"
# File types that will show up as items
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]
const RECOLOR_SHADER = preload("res://shaders/recolor.gdshader")
# Stickers can be placed anywhere on the doll. Put your own sticker art in this folder.
const STICKER_FOLDER := "res://stickers"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	# ResourceLoader.list_directory() lists the files the same way in the editor
	# and in exported games, so items no longer show up twice when run from the editor.
	# Folders are sorted so the layers are always stacked in the same order.
	var folders := []
	for entry in ResourceLoader.list_directory(IMAGE_FOLDER):
		if entry.ends_with("/"):
			folders.append(entry.trim_suffix("/"))
	folders.sort()

	for file_name in folders:
		#print("Found directory: " + file_name)
		interactivity.layers += [file_name]

		#####################################
		############## SPRITES ##############
		#####################################

		### Add a sprite to the scene for each of the folders
		### These will later be used to display the images of
		### dressup items as user clicks on the buttons
		var new_layer
		#	if background layer (they should start with 00),
		#	reset position to cover entire screen:
		if file_name.begins_with("00"):
			new_layer = Sprite2D.new()
			new_layer.centered = false
			$BGHolder.add_child(new_layer)
		else:
			new_layer = sprite_placeholder.duplicate()
			new_layer.z_index = len(interactivity.layer_nodes)
			new_layer.name = file_name
			sprite_holder.add_child(new_layer)
		new_layer.visible = false
		# Each layer gets its own copy of the recolor effect, so colors can differ per layer
		new_layer.material = ShaderMaterial.new()
		new_layer.material.shader = RECOLOR_SHADER

		interactivity.layer_nodes.append(new_layer) # save the layer nodes into a list for easy access later



		#####################################
		############## CATEGORIES ###########
		#####################################

		### For each new category/layer, add a category button as well.
		### These will allow the user to switch between hair, makeup, etc.
		var icon_path = IMAGE_FOLDER + file_name + "/icon.png"
		var icon = load(icon_path) if ResourceLoader.exists(icon_path) else load("res://GUI/example_icon.png")
		var newbutton = category_button.instantiate()
		newbutton.icon = icon
		newbutton.name = file_name
		newbutton.category = file_name
		category_buttons.add_child(newbutton)


		#####################################
		############## CONTAINERS FOR ITEMS #
		#####################################
		### Also add a copy of the "tab_of_buttons" scene for each category/layer
		### This will display the buttons for different items from each category
		### For example, hair or dress options when that category is selected.
		var newtab = tab_of_buttons.instantiate()
		newtab.name = file_name
		newtab.layer = file_name
		tabs_of_items_container.add_child(newtab)
		interactivity.tab_nodes.append(newtab) # save the tab nodes into a list for easy access later

	# The placeholder is only used to position the doll in the editor
	sprite_placeholder.visible = false
	print_debug("Folder names were read, found ", len(interactivity.layers),";  ", interactivity.layers)


	# Remove example nodes, since we don't need them anymore
	for x in get_tree().get_nodes_in_group("remove_at_start"):
		x.queue_free()


	#####################################
	############## BUTTONS FOR ITEMS ####
	#####################################
	# repopulate found categories with the buttons / images
	for c in interactivity.tab_nodes:
		# Backgrounds and the body always show something, other layers can be taken off
		if not interactivity.is_required(c.layer):
			c.add_none_button()
		if not interactivity.is_background(c.layer):
			c.add_color_swatches()
		print_debug(read_files_in_folder(c, IMAGE_FOLDER + c.layer))
		# Items made while playing, such as AI backgrounds
		for path in GeneratedItems.list(c.layer):
			var picture = GeneratedItems.load_texture(path)
			if picture:
				c.add_item(picture, path)

	# The first background tab gets a button for making backgrounds with AI
	for c in interactivity.tab_nodes:
		if interactivity.is_background(c.layer):
			c.add_ai_button("Make a background with AI")
			break
	
	add_sticker_category()
	
	# Tell interactivity to initiate the first view
	interactivity.start_game()


#####################################
############## STICKERS #############
#####################################
### Stickers get their own category button and tab, like a layer,
### but pressing one places it on the doll instead of swapping a layer.
func add_sticker_category() -> void:
	var newbutton = category_button.instantiate()
	var icon_path = STICKER_FOLDER + "/icon.png"
	newbutton.icon = load(icon_path) if ResourceLoader.exists(icon_path) else load("res://GUI/sticker_icon.svg")
	newbutton.name = "Stickers"
	newbutton.category = interactivity.STICKERS
	newbutton.tooltip_text = "Stickers"
	category_buttons.add_child(newbutton)
	
	var newtab = tab_of_buttons.instantiate()
	newtab.name = "Stickers"
	newtab.layer = interactivity.STICKERS
	tabs_of_items_container.add_child(newtab)
	interactivity.sticker_tab = newtab
	
	newtab.add_ai_button("Make a sticker with AI")
	print_debug(read_files_in_folder(newtab, STICKER_FOLDER))
	for path in GeneratedItems.list(interactivity.STICKERS):
		var picture = GeneratedItems.load_texture(path)
		if picture:
			newtab.add_item(picture, path)


func read_files_in_folder(tab_node:Node, path:String) -> String:
	if not DirAccess.dir_exists_absolute(path):
		print("An error occurred when trying to access the path.")
		return "Could not read " + path
	var files = Array(ResourceLoader.list_directory(path))
	files.sort()
	for file_name in files:
		if file_name.ends_with("/"):
			continue # sub-folders are ignored
		if not file_name.get_extension().to_lower() in IMAGE_EXTENSIONS:
			continue
		# icon.png is the picture for the category button, not an item
		if file_name.get_basename().to_lower() == "icon":
			continue
		print_debug("Generate for ", path+"/"+file_name)
		tab_node.add_item(load(path + "/" + file_name), file_name)
	return "Folder contents were read for "+tab_node.layer
