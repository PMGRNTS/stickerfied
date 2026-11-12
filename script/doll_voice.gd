# Speaks the doll's chat answers out loud.
# With a voice server (a Mac running voice_server/start_voice.sh, see "Voice" in readme.txt)
# she speaks in her own designed voice. Without one, or when it doesn't answer in time,
# the browser or computer reads her lines with one of its built-in voices.
# She stays quiet while the sound is off.

class_name DollVoice
extends Node

# The address start_voice.sh shows, such as https://my-mac.tail1234.ts.net
# Leave it empty to only use the built-in voice.
@export var server_url := ""
# Give up on the voice server after this long, and use the built-in voice
@export var wait_seconds := 15.0
# The built-in voice: a little higher and quicker sounds more like her
@export_range(0.0, 2.0) var builtin_pitch := 1.3
@export_range(0.5, 2.0) var builtin_rate := 1.1

var http: HTTPRequest
var player: AudioStreamPlayer
var line := "" # what she's saying now

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = wait_seconds
	http.request_completed.connect(_on_voice)
	add_child(http)
	player = AudioStreamPlayer.new()
	add_child(player)
	Sfx.muted_changed.connect(func(muted): if muted: stop())

func speak(text:String) -> void:
	stop()
	if Sfx.is_muted() or text == "":
		return
	line = text
	if server_url == "":
		_speak_builtin()
		return
	# Sent as plain text, so browsers don't have to ask the server first (no CORS preflight)
	var error = http.request(server_url.strip_edges().trim_suffix("/") + "/speak", ["Content-Type: text/plain"],
		HTTPClient.METHOD_POST, JSON.stringify({"text": text}))
	if error != OK:
		_speak_builtin()

func stop() -> void:
	http.cancel_request()
	player.stop()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()

func _on_voice(result:int, code:int, _headers:PackedStringArray, body:PackedByteArray) -> void:
	var voice: AudioStreamWAV = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		voice = AudioStreamWAV.load_from_buffer(body)
	else:
		push_warning("Voice server: %s %s" % [OpenRouterClient.describe_result(result), body.get_string_from_utf8().strip_edges()])
	if voice == null:
		_speak_builtin()
		return
	player.stream = voice
	player.play()

func _speak_builtin() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var voices = DisplayServer.tts_get_voices_for_language("en")
	DisplayServer.tts_speak(line, voices[0] if not voices.is_empty() else "", 70, builtin_pitch, builtin_rate, 0, true)
