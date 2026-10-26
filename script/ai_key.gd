# The player's OpenRouter API key, shared by the AI Create and AI Stylist windows.
# The key is only stored on this device (in the browser's storage on the web).

class_name AIKey

const SETTINGS_FILE := "user://ai_settings.cfg"

static func load_key() -> String:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	return config.get_value("openrouter", "api_key", "")

static func remembers_key() -> bool:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	return config.get_value("openrouter", "remember_key", true)

# When remember is off, the key is used until the game closes, but not saved
static var _unsaved_key := ""

static func save_key(key:String, remember := true) -> void:
	key = key.strip_edges()
	_unsaved_key = key
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	config.set_value("openrouter", "remember_key", remember)
	config.set_value("openrouter", "api_key", key if remember else "")
	config.save(SETTINGS_FILE)

# The key to use right now: the saved one, or the one typed in this session
static func current_key() -> String:
	var saved = load_key()
	return saved if saved != "" else _unsaved_key
