# The player's API keys, shared by the AI Create and AI Stylist windows.
# There is one key for each provider: "openrouter", "fal", "replicate" or "runpod".
# Keys are only stored on this device (in the browser's storage on the web).

class_name AIKey

const SETTINGS_FILE := "user://ai_settings.cfg"

static func load_key(provider := "openrouter") -> String:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	return config.get_value(provider, "api_key", "")

static func remembers_key(provider := "openrouter") -> bool:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	return config.get_value(provider, "remember_key", true)

# When remember is off, the key is used until the game closes, but not saved
static var _unsaved_keys := {}

static func save_key(key:String, remember := true, provider := "openrouter") -> void:
	key = key.strip_edges()
	_unsaved_keys[provider] = key
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	config.set_value(provider, "remember_key", remember)
	config.set_value(provider, "api_key", key if remember else "")
	config.save(SETTINGS_FILE)

# The key to use right now: the saved one, or the one typed in this session
static func current_key(provider := "openrouter") -> String:
	var saved = load_key(provider)
	return saved if saved != "" else _unsaved_keys.get(provider, "")
