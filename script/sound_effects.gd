# This code is set as "global" in the project settings (as "Sfx"), so any script
# can play a sound with Sfx.play("pop").
#
# The sounds are made by code, so the template needs no audio files.
# To use your own sounds instead, put files named after the sound
# (pop.ogg, click.wav, shutter.mp3, sparkle.ogg...) in a "sounds" folder: res://sounds/

extends Node

const SOUND_FOLDER := "res://sounds/"
const SETTINGS_FILE := "user://settings.cfg"
const MIX_RATE := 22050
const VOLUME_DB := -8.0

signal muted_changed(muted)

var sounds := {}
var players := []
var next_player := 0

func _ready() -> void:
	sounds = {
		"pop": _sound_or_file("pop", _make_pop),
		"click": _sound_or_file("click", _make_click),
		"shutter": _sound_or_file("shutter", _make_shutter),
		"sparkle": _sound_or_file("sparkle", _make_sparkle),
	}
	# a few players, so quick sounds can overlap
	for i in 4:
		var player = AudioStreamPlayer.new()
		player.volume_db = VOLUME_DB
		add_child(player)
		players.append(player)
	var config = ConfigFile.new()
	config.load(SETTINGS_FILE)
	set_muted(config.get_value("sound", "muted", false), false)

func play(sound_name: String) -> void:
	if is_muted() or not sounds.has(sound_name):
		return
	var player: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % len(players)
	player.stream = sounds[sound_name]
	player.pitch_scale = randf_range(0.95, 1.05) # a little variety
	player.play()

func is_muted() -> bool:
	return AudioServer.is_bus_mute(0)

func set_muted(muted: bool, remember := true) -> void:
	AudioServer.set_bus_mute(0, muted)
	muted_changed.emit(muted)
	if remember:
		var config = ConfigFile.new()
		config.load(SETTINGS_FILE)
		config.set_value("sound", "muted", muted)
		config.save(SETTINGS_FILE)

func _sound_or_file(sound_name: String, make: Callable) -> AudioStream:
	for extension in ["ogg", "wav", "mp3"]:
		var path = SOUND_FOLDER + sound_name + "." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return make.call()


#####################################
############## MADE BY CODE #########
#####################################
# Each sound is a list of samples between -1 and 1

func _make_pop() -> AudioStream:
	# a quick upward "bloop"
	return _to_stream(_tone(0.09, func(t): return lerpf(500.0, 1100.0, t / 0.09), 30.0))

func _make_click() -> AudioStream:
	return _to_stream(_tone(0.03, func(_t): return 1400.0, 120.0))

func _make_shutter() -> AudioStream:
	# two bursts of noise, like a camera
	var samples := PackedFloat32Array()
	for burst in 2:
		var length = int(MIX_RATE * 0.06)
		for i in length:
			samples.append(randf_range(-1.0, 1.0) * exp(-float(i) / length * 6.0) * 0.6)
		for i in int(MIX_RATE * 0.04):
			samples.append(0.0) # a short silence
	return _to_stream(samples)

func _make_sparkle() -> AudioStream:
	# three rising notes
	var samples := PackedFloat32Array()
	for frequency in [1046.5, 1318.5, 1568.0]:
		samples.append_array(_tone(0.07, func(_t): return frequency, 25.0))
	return _to_stream(samples)

# A sine wave that fades out. frequency is a Callable so the pitch can slide.
func _tone(seconds: float, frequency: Callable, fade_speed: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var phase := 0.0
	for i in int(MIX_RATE * seconds):
		var t = float(i) / MIX_RATE
		phase += TAU * frequency.call(t) / MIX_RATE
		var attack = minf(1.0, i / 40.0) # avoids a click at the start
		samples.append(sin(phase) * exp(-t * fade_speed) * attack * 0.7)
	return samples

func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	return stream
