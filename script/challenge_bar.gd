# Challenge mode: the game picks a theme and the player dresses the doll for it
# before the time runs out. Then the AI judge (if the player has a key) gives a score,
# or the player can just take a photo.
# Add your own themes to the list in the Inspector (select Toolbar/ChallengeBar in GUI/toolbar.tscn).
# Its z_index is above the doll and stickers (StickerStage is 100), so they never cover it.

extends VBoxContainer

signal message(text)
signal judge_requested

@export var themes: Array[String] = [
	"A day at the beach", "Royal ball", "Space explorer", "Rainy day", "Rock concert",
	"Winter wonderland", "Birthday party", "Under the sea", "Spooky night", "Garden tea party",
	"Superhero", "First day of school", "Camping trip", "Fairy tale", "Disco night",
	"Pirate adventure", "Sports day", "Cozy pajama party", "Wedding guest", "Robot future",
]
# How long the player has, in seconds. 0 means no time limit.
@export var seconds := 90

var current_theme := ""
var seconds_left := 0.0

func _ready() -> void:
	%StartButton.pressed.connect(start)
	%NewThemeButton.pressed.connect(start)
	%JudgeThemeButton.pressed.connect(judge_requested.emit)
	%StopButton.pressed.connect(stop)
	%ChallengePanel.hide()
	set_process(false)

func start() -> void:
	var choices = themes.filter(func(theme_name): return theme_name != current_theme)
	if choices.is_empty():
		choices = themes
	if choices.is_empty():
		return
	current_theme = choices.pick_random()
	seconds_left = seconds
	%ThemeLabel.text = "Dress for: " + current_theme
	%StartButton.hide()
	%ChallengePanel.show()
	set_process(seconds > 0)
	_show_time()
	Sfx.play("sparkle")

func stop() -> void:
	current_theme = ""
	set_process(false)
	%ChallengePanel.hide()
	%StartButton.show()
	Sfx.play("click")

func _process(delta: float) -> void:
	seconds_left -= delta
	if seconds_left <= 0:
		seconds_left = 0
		set_process(false)
		Sfx.play("sparkle")
		message.emit("Time's up! Press Judge for a score, or take a Photo.")
	_show_time()

func _show_time() -> void:
	if seconds <= 0:
		%TimeLabel.text = ""
	elif seconds_left <= 0:
		%TimeLabel.text = "Time's up!"
	else:
		var left = ceili(seconds_left)
		%TimeLabel.text = "%d:%02d" % [left / 60, left % 60]
