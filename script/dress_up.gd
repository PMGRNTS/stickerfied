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

#var layers :=[] #layer names (folder names)
#var layer_nodes:=[] #access to sprite layers
#var tab_nodes:=[] # access to tabs of buttons (node that contains all options for a category)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	var path = "res://images/"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
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
				
				interactivity.layer_nodes.append(new_layer) # save the layer nodes into a list for easy access later
				
				
				
				#####################################
				############## CATEGORIES ###########
				#####################################
				
				### For each new category/layer, add a category button as well.
				### These will allow the user to switch between hair, makeup, etc.
				var icon = load("res://images/"+file_name+"/icon.png")
				if !icon:
					icon = load("res://GUI/example_icon.png")
				var newbutton = category_button.instantiate()
				newbutton.icon = icon
				newbutton.name = file_name
				category_buttons.add_child(newbutton)
				
				
				#####################################
				############## CONTAINERS FOR ITEMS #
				#####################################
				### Also add a copy of the "tab_of_buttons" scene for each category/layer
				### This will display the buttons for different items from each category
				### For example, hair or dress options when that category is selected.
				var newtab = tab_of_buttons.instantiate()
				newtab.name = file_name
				tabs_of_items_container.add_child(newtab)
				interactivity.tab_nodes.append(newtab) # save the tab nodes into a list for easy access later
				
			else:
				pass
			file_name = dir.get_next()
	print_debug("Folder names were read, found ", len(interactivity.layers),";  ", interactivity.layers)
	
	
	# Remove example nodes, since we don't need them anymore
	for x in get_tree().get_nodes_in_group("remove_at_start"):
		x.queue_free()

	
	#####################################
	############## BUTTONS FOR ITEMS ####
	#####################################
	# repopulate found categories with the buttons / images
	for c in interactivity.tab_nodes:
		print_debug(read_files_in_folder(c))
	
	# Tell interactivity to initiate the first view
	interactivity.start_game()


func read_files_in_folder(tab_node:Node) -> String:
	var path = "res://images/"+tab_node.name
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				pass #print("Found directory: " + file_name)
			else:
				#print_debug("Found file: " + file_name)
				file_name = file_name.replace('.import', '')
				if file_name.ends_with(".png") or file_name.ends_with(".PNG") or file_name.ends_with(".jpg"):
					if !file_name.contains("icon"):
						print_debug("Generate for ", path+"/"+file_name)
						tab_node.add_item(path, file_name)
			file_name = dir.get_next()
	else:
		print("An error occurred when trying to access the path.")
	return "Folder contents were read for "+tab_node.name
