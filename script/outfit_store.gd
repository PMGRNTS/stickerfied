# Saves outfits (with a small picture of each) in the user:// folder,
# and turns outfits into short "share codes" that can be pasted to a friend.

class_name OutfitStore

const FOLDER := "user://outfits/"
const INDEX_FILE := FOLDER + "outfits.json"
const SHARE_CODE_PREFIX := "DU1-"

# Returns a list of saved outfits, newest first:
#   [{"id": "1700000000000", "outfit": {...}, "thumbnail": "user://outfits/1700000000000.png"}, ...]
static func load_all() -> Array:
	if not FileAccess.file_exists(INDEX_FILE):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(INDEX_FILE))
	return data if data is Array else []

static func save_outfit(outfit:Dictionary, thumbnail:Image) -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var id = str(int(Time.get_unix_time_from_system() * 1000))
	var thumbnail_path = FOLDER + id + ".png"
	thumbnail.save_png(thumbnail_path)
	var all = load_all()
	all.push_front({"id": id, "outfit": outfit, "thumbnail": thumbnail_path})
	_write_index(all)

static func delete_outfit(id:String) -> void:
	var all = load_all()
	for entry in all:
		if entry.id == id:
			DirAccess.remove_absolute(entry.thumbnail)
	_write_index(all.filter(func(entry): return entry.id != id))

static func _write_index(all:Array) -> void:
	var file = FileAccess.open(INDEX_FILE, FileAccess.WRITE)
	if file == null:
		push_error("Could not save outfits: ", error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(all))


#####################################
############## SHARE CODES ##########
#####################################
# The outfit is stored as {"03Hair": ["bob.PNG", -1], ...}, compressed,
# and written as text. Empty layers are left out to keep the code short.
# Stickers are stored as "_stickers": [["heart.svg", x, y, scale, rotation], ...]

const STICKERS := "_stickers"

static func to_share_code(outfit:Dictionary) -> String:
	var compact := {}
	for layer in outfit:
		var entry = outfit[layer]
		if layer == STICKERS:
			if not entry.is_empty():
				compact[STICKERS] = entry.map(func(sticker):
					return [sticker.id, sticker.x, sticker.y, sticker.scale, sticker.rot])
		elif entry.item != "" or entry.hue >= 0:
			compact[layer] = [entry.item, snappedf(entry.hue, 0.001)]
	var bytes = JSON.stringify(compact).to_utf8_buffer()
	var packed = bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	return SHARE_CODE_PREFIX + Marshalls.raw_to_base64(packed)

# Returns the outfit, or an empty Dictionary if the code can't be read
static func from_share_code(code:String) -> Dictionary:
	code = code.strip_edges()
	if not code.begins_with(SHARE_CODE_PREFIX):
		return {}
	var text = code.trim_prefix(SHARE_CODE_PREFIX)
	if RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$").search(text) == null:
		return {}
	var packed = Marshalls.base64_to_raw(text)
	if packed.is_empty():
		return {}
	var bytes = packed.decompress_dynamic(64 * 1024, FileAccess.COMPRESSION_DEFLATE)
	var compact = JSON.parse_string(bytes.get_string_from_utf8())
	if not compact is Dictionary:
		return {}
	var outfit := {}
	for layer in compact:
		var entry = compact[layer]
		if layer == STICKERS and entry is Array:
			outfit[STICKERS] = []
			for sticker in entry:
				if sticker is Array and len(sticker) == 5:
					outfit[STICKERS].append({"id": str(sticker[0]), "x": sticker[1], "y": sticker[2],
						"scale": sticker[3], "rot": sticker[4]})
		elif entry is Array and len(entry) == 2:
			outfit[layer] = {"item": str(entry[0]), "hue": float(entry[1])}
	return outfit
