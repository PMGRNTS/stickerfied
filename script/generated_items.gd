# Stores pictures that are made while playing (such as AI backgrounds)
# in the user:// folder, so they are still there the next time the game starts.
# In a web export, user:// is kept in the browser's storage.
# Each picture can have a short description (the prompt it was made from),
# kept in a .txt file with the same name. The AI Stylist reads it.

class_name GeneratedItems

const ROOT := "user://generated/"

# Saves the image as a png and returns its path, which is also used as the item_id
static func save(layer:String, image:Image, description := "") -> String:
	var folder = ROOT + layer
	DirAccess.make_dir_recursive_absolute(folder)
	var path = "%s/ai_%d.png" % [folder, int(Time.get_unix_time_from_system() * 1000)]
	var error = image.save_png(path)
	if error != OK:
		push_error("Could not save generated image to ", path, ": ", error_string(error))
		return ""
	if description != "":
		var file = FileAccess.open(_description_path(path), FileAccess.WRITE)
		if file:
			file.store_string(description)
	return path

static func list(layer:String) -> Array:
	var folder = ROOT + layer
	var paths := []
	if not DirAccess.dir_exists_absolute(folder):
		return paths
	var files = Array(DirAccess.get_files_at(folder))
	files.sort()
	for file_name in files:
		if file_name.get_extension().to_lower() == "png":
			paths.append(folder + "/" + file_name)
	return paths

static func delete(path:String) -> void:
	if path.begins_with(ROOT):
		DirAccess.remove_absolute(path)
		if FileAccess.file_exists(_description_path(path)):
			DirAccess.remove_absolute(_description_path(path))

# The description saved with the picture, or "" if it has none
static func describe(path:String) -> String:
	if not path.begins_with(ROOT) or not FileAccess.file_exists(_description_path(path)):
		return ""
	return FileAccess.get_file_as_string(_description_path(path)).strip_edges()

static func _description_path(path:String) -> String:
	return path.get_basename() + ".txt"

static func load_texture(path:String) -> Texture2D:
	var image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)
