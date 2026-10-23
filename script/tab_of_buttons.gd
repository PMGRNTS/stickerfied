# This code is used to create the grid of selectable items for each category

extends VBoxContainer
@export var button_base : PackedScene

func _ready() -> void:
	for i in $ScrollContainer/GridContainer.get_children():
		i.queue_free()


func add_item(folder_path:String, file_name:String)->void:
	var newbutton = button_base.instantiate()
	newbutton.icon =  load(folder_path+"/"+file_name)
	newbutton.category = self.name
	$ScrollContainer/GridContainer.add_child(newbutton)
	newbutton.resize_to_picture()
