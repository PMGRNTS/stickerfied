# This code is responsible for what happens when user presses a button
# It uses dressup_item_signal to listen for button presses 
# and hides/shows elements based on what was pressed.

extends Node

var layers :=[] #layer names (folder names)
var layer_nodes:=[] #access to sprite layers
var tab_nodes:=[] # access to tabs of buttons (node that contains all options for a category)

func _ready():
	SignalBus.dressup_item_signal.connect(_on_button_press)

func start_game()->void:
	# fake pressing a button to hide unnecessary elements
	SignalBus.dressup_item_signal.emit( get_tree().get_first_node_in_group("category_button") , "category")

func _on_button_press(node_pressed:Node, operation_name:String):
	#print_debug(node_pressed.name, operation_name)
	
	# user selected a category
	if operation_name == "category": 
		for i in %TabsOfItemsContainer.get_children():
			i.visible = false
			if i.name == node_pressed.name:
				i.visible = true
	# user selected an item, such as a specific hair or makeup item
	if operation_name == "item":
		var layerindex = layers.find(node_pressed.category)
		layer_nodes[layerindex].texture = node_pressed.image
		if !layer_nodes[layerindex].visible:
			layer_nodes[layerindex].visible = true
