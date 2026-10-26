# Stores pictures that are made while playing (such as AI backgrounds)
# in the user:// folder, so they are still there the next time the game starts.
# In a web export, user:// is kept in the browser's storage.

class_name GeneratedItems

const ROOT := "user://generated/"

# Saves the image as a png and returns its path, which is also used as the item_id
static func save(layer:String, image:Image) -> String:
	var folder = ROOT + layer
	DirAccess.make_dir_recursive_absolute(folder)
	var path = "%s/ai_%d.png" % [folder, int(Time.get_unix_time_from_system() * 1000)]
	var error = image.save_png(path)
	if error != OK:
		push_error("Could not save generated image to ", path, ": ", error_string(error))
		return ""
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

static func load_texture(path:String) -> Texture2D:
	var image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)
