# Gives the doll a personality: a bratty, high-maintenance girl.
# She stands with her weight on one hip, looking unimpressed. Every few seconds she shifts
# her hips, gives a little side-eye or flicks her hair, and when nobody plays with her for a
# while she gets bored: eye rolls and sighs. She has opinions about everything she is put in:
# things she loves make her light up, things she's not sure about get looked up and down,
# and things she hates get a pause, an eye roll and a pout. If the player changes things too
# fast she gets impatient, and she strikes a pose for photos.
# Poking her (clicking on the doll) annoys her more each time, until she sulks: she turns
# away for a while, and only something she loves makes up for it. She has opinions about
# the AI judge's score too. She says what she thinks in a speech bubble.
# She looks at items and colors the mouse is on if she loves them, and turns her nose up at
# ones she hates (ones she doesn't care about she ignores). Every minute or so she wants
# something: a color, a new item for a layer or a new background. She waits a while for it,
# reminds the player once, and gives up in a huff if it never comes.
#
# Faces are slider values added on top of the player's Body sliders (see body_control.gd),
# such as {"Smile": -0.6, "Cheeks": 0.4} for a pout. Sliders the doll doesn't have are left
# out, so any doll can use them. Faces are written for her standing on her right hip;
# the sliders in SIDED are turned around when she stands on her left.
# A reaction is a list of steps: [face, seconds to move there, snappy, seconds to hold it].
# Snappy moves are quick flicks that overshoot a little and settle, the others ease in and out.
# A step without a face (null) just waits, like a pause before she reacts. A step can also
# say a line from LINES (see _say_step).
# Change the faces, reactions and lines below to give her a different personality.
#
# She doesn't react to the doll's body or Body sliders, only to what she is wearing.

extends Node

const BodyControl = preload("res://script/body_control.gd")

@export var body_shaper: Node2D
@export var interactivity: Node
# She holds still while the player arranges stickers or fits or sculpts the doll.
# Clicks on the doll come from here too.
@export var sticker_stage: Node2D
@export var body_fitter: Node2D
@export var body_sculptor: Node2D
# Her speech bubbles are shown on this, so they are hidden with it for photos
@export var bubble_parent: Control
# Turn this off for no speech bubbles
@export var talks := true

# Words in item names that she always loves or always hates, separated by commas.
# Every other item gets an opinion of its own, which never changes.
@export var loves := "pink, sparkle, glitter, luxurious, glam, designer"
@export var hates := "plain, basic, cheap, boring"
# The colors she loves (see SWATCH_HUES in tab_of_buttons.gd): purple, pink and rose
@export var favorite_hues: Array[float] = [0.74, 0.84, 0.93]
# Shortest and longest time between her little moves, in seconds
@export var fidget_every := Vector2(3.5, 7.0)
# How long without the player changing anything before she gets bored, in seconds
@export var bored_after := 20.0
# How long she sulks, in seconds
@export var sulk_time := 15.0
# Turn this off and she never asks for anything
@export var demands := true
# Shortest and longest time between her demands, in seconds
@export var demand_every := Vector2(40.0, 80.0)

# This many changes within FAST_TIME seconds make her impatient
const FAST_CHANGES := 4
const FAST_TIME := 4.0
# How long she holds her pose after a photo, in seconds
const PHOTO_HOLD := 1.2
# Each poke makes her one step more annoyed (up to POKES_TO_SULK, when she sulks);
# she calms down one step every this many seconds
const CALM_DOWN := 4.0
const POKES_TO_SULK := 4
# How long a speech bubble shows: at least BUBBLE_TIME seconds, longer for longer lines
const BUBBLE_TIME := 1.4
const BUBBLE_TIME_PER_LETTER := 0.06
# The bubble's tail: how far its panel is from the doll's head, across and up
const BUBBLE_TAIL := Vector2(18, 16)
# How long she waits for what she asked for, in seconds
const DEMAND_TIME := 30.0

# Sliders that turn or look to one side
const SIDED := ["Lean", "Head tilt", "Look across"]

# Weight on one hip, the other elbow bent towards it, head tilted back, half-lidded and unimpressed.
# The arm and leg sliders (the Skeleton's bones) aren't in SIDED: they stay on their own side.
const RESTING := {"Lean": 0.4, "Head tilt": -0.3, "Squint": 0.3, "Smile": -0.1, "Right arm": 0.25, "Right elbow": -1.0}
const SIDE_EYE := {"Lean": 0.4, "Head tilt": -0.2, "Squint": 0.45, "Smile": -0.15, "Look across": 0.9, "Right arm": 0.25, "Right elbow": -1.0}
const HAIR_DIP := {"Lean": 0.4, "Head tilt": 0.2, "Squint": 0.3, "Smile": -0.1, "Right arm": 0.25, "Right elbow": -1.0}
const HAIR_FLICK := {"Lean": 0.45, "Head tilt": -0.7, "Squint": 0.4, "Smile": 0.1, "Smirk": 0.4, "Right arm": 0.25, "Right elbow": -1.0}
const ROLL_START := {"Lean": 0.3, "Head tilt": -0.35, "Squint": 0.2, "Smile": -0.2, "Look up": 0.6, "Look across": -0.8, "Right arm": 0.25, "Right elbow": -1.0}
const ROLL_TOP := {"Lean": 0.3, "Head tilt": -0.45, "Squint": 0.15, "Smile": -0.2, "Look up": 1.0, "Right arm": 0.25, "Right elbow": -1.0}
const ROLL_END := {"Lean": 0.3, "Head tilt": -0.4, "Squint": 0.35, "Smile": -0.25, "Look up": 0.5, "Look across": 0.8, "Right arm": 0.25, "Right elbow": -1.0}
const SIGH := {"Lean": 0.15, "Head tilt": 0.15, "Squint": 0.7, "Smile": -0.35, "Look up": -0.5, "Right arm": 0.1, "Right elbow": -0.8}
const LOVE := {"Lean": 0.6, "Head tilt": 0.35, "Eye size": 0.35, "Cheeks": 0.4, "Smile": 0.8, "Squint": -0.2, "Left arm": 0.3, "Right arm": 0.5, "Right elbow": -0.5}
const LOVE_HOLD := {"Lean": 0.45, "Head tilt": 0.25, "Eye size": 0.25, "Cheeks": 0.35, "Smile": 0.7, "Squint": 0.1, "Left arm": 0.2, "Right arm": 0.4, "Right elbow": -0.6}
const LOOK_DOWN := {"Lean": 0.4, "Head tilt": -0.2, "Squint": 0.4, "Smile": -0.1, "Look up": -1.0, "Right arm": 0.25, "Right elbow": -1.0}
const NOT_BAD := {"Lean": 0.4, "Head tilt": -0.35, "Squint": 0.45, "Smirk": 0.5, "Right arm": 0.25, "Right elbow": -1.0}
# Looks and turns away, cheeks puffed
const POUT := {"Lean": -0.3, "Head tilt": -0.6, "Look across": -0.9, "Squint": 0.35, "Smile": -0.6, "Mouth size": -0.3, "Cheeks": 0.4, "Right arm": -0.2, "Right elbow": -0.5}
const GASP := {"Lean": -0.4, "Head tilt": 0.1, "Eye size": 0.4, "Mouth size": 0.5, "Smile": -0.3, "Squint": -0.3, "Left elbow": 0.6, "Right arm": 0.2, "Right elbow": -0.5}
const PHOTO := {"Lean": 0.65, "Head tilt": -0.45, "Squint": 0.35, "Smile": 0.3, "Smirk": 0.8, "Eye size": 0.1, "Look across": -0.15, "Right arm": 0.45, "Right elbow": -0.4, "Left leg": 0.3}
const SMUG := {"Lean": 0.6, "Head tilt": -0.5, "Squint": 0.5, "Smile": 0.2, "Smirk": 0.9, "Look across": -0.3, "Right arm": 0.25, "Right elbow": -1.0}
# Turned away, arms in close, instead of RESTING while she sulks
const SULK := {"Lean": -0.35, "Head tilt": -0.45, "Look across": -1.0, "Squint": 0.45, "Smile": -0.45, "Cheeks": 0.25, "Right arm": -0.5, "Left arm": -0.3}
# For pokes these are turned towards the side she is poked from, not her hip:
# she jumps away from the poke, then looks back at whoever did it
const FLINCH := {"Lean": 0.5, "Head tilt": 0.3, "Eye size": 0.35, "Squint": -0.2, "Smile": -0.2, "Left elbow": 0.4, "Right arm": 0.4, "Right elbow": -0.3}
const LOOK_BACK := {"Lean": 0.35, "Head tilt": -0.1, "Look across": -0.9, "Squint": 0.2, "Eye size": 0.15}
const GLARE := {"Lean": 0.3, "Head tilt": -0.3, "Look across": -1.0, "Squint": 0.6, "Smile": -0.4}
# Asking for something: hip out, looking right at whoever should get it
const DEMAND := {"Lean": 0.55, "Head tilt": 0.2, "Squint": 0.35, "Smile": -0.25, "Look across": -0.4, "Eye size": 0.1, "Right arm": 0.35, "Right elbow": -1.0}

# What she says. A line is picked at random (not the same one twice in a row);
# %d is the judge's score, and %s what she wants (a color or a layer's name).
const LINES := {
	"love": ["Obsessed.", "Okay, finally.", "Now THIS is me.", "I look expensive.", "Yes. Yes yes yes."],
	"not_sure": ["It's... fine.", "Hmm. Maybe.", "It's giving... something.", "I guess?"],
	"hate": ["Ew. No.", "Absolutely not.", "Are you serious?", "I'm not wearing that.", "Who even makes this?"],
	"offended": ["Excuse me?!", "Put it BACK.", "Rude."],
	"impatient": ["Ugh, just decide.", "Can you pick one?", "I'm getting dizzy."],
	"bored": ["Hello? I'm waiting.", "Are we done yet?", "I'm so bored.", "Anyone?"],
	"photo": ["Get my good side.", "Make it cute.", "Okay, now."],
	"poke_1": ["Hm?", "Yes?"],
	"poke_2": ["Excuse me?", "Can I help you?"],
	"poke_3": ["Stop it.", "Seriously?"],
	"poke_4": ["Hands OFF!", "That's it. I'm not talking to you."],
	"poke_head": ["Not the hair!", "Watch the hair!"],
	"sulking": ["Hmph.", "I'm still mad."],
	"sulk_over": ["...Fine. I forgive you.", "Okay, you're forgiven. Barely."],
	"judge_high": ["Obviously.", "Told you.", "I know, right?"],
	"judge_mid": ["A %d? I'll allow it.", "Only a %d? Whatever."],
	"judge_low": ["The judge is clearly jealous.", "A %d?! Rigged.", "I'm not talking to anyone."],
	"eyeing_love": ["Ooh.", "Wait. That one.", "Gimme."],
	"eyeing_hate": ["Don't you dare.", "Don't even think about it.", "Ew."],
	"demand_color": ["I want something %s.", "Make something %s. Now.", "Why isn't anything %s?"],
	"demand_layer": ["New %s. Now.", "I'm so over this %s.", "Change my %s. Please. Now."],
	"demand_background": ["Take me somewhere else.", "I hate it here. New background."],
	"remind_color": ["Still waiting for something %s.", "Something %s? Hello?"],
	"remind_layer": ["Still waiting on that new %s.", "Hello? New %s?"],
	"remind_background": ["Still here. Still hate it.", "New background. Today."],
	"demand_met": ["Finally!", "See? Was that so hard?", "Thank you. Finally."],
	"demand_wrong": ["Not THAT one.", "Ew, not that.", "Try again."],
	"demand_failed": ["Forget it.", "Ugh. Never mind.", "Fine. I'll just stand here."],
}

var side := 1.0 # the hip she stands on: 1 right, -1 left
var steps := [] # the steps of her reaction still to come
var hold := 0.0 # seconds left to hold the face she is making
var fidget_wait := 3.0 # seconds until her next little move
var idle := 0.0 # seconds since the player last changed something
var changes := [] # when the player changed things lately, in seconds since the game started
var still := false # true while she holds still
var last_outfit := {}
var annoyed := 0.0 # how annoyed pokes made her, 0 to POKES_TO_SULK
var sulking := 0.0 # seconds of sulking left
var score_waiting := [] # [score, best, window] from the judge, until its window is closed
var eyeing: Control = null # the item button or color swatch the mouse is on, if she cares about it
var eyeing_opinion := 0 # 1 if she loves what she's eyeing, -1 if she hates it
var gaze_face := {} # the face she makes at what she's eyeing, or {} when she isn't looking at anything
# What she wants: {"kind": "color", "hue", "name"}, {"kind": "layer" or "background", "layer", "name"},
# or {} for nothing. "reminded" is true once she has asked again.
var demand := {}
var demand_wait := 0.0 # seconds until she wants something
var demand_left := 0.0 # seconds she still waits for it

var bubble: Control # the speech bubble: its tail's tip is where it is placed
var bubble_panel: PanelContainer
var bubble_tween: Tween
var bubble_flipped := false # true when the bubble is on the head's left, to stay on the screen
var last_line := ""

func _ready() -> void:
	interactivity.outfit_changed.connect(_on_outfit_changed)
	SignalBus.dressup_hover_signal.connect(_on_hover)
	if sticker_stage:
		sticker_stage.clicked.connect(_on_doll_clicked)
	if bubble_parent:
		_make_bubble()
	demand_wait = randf_range(demand_every.x, demand_every.y) / 2

func _process(delta:float) -> void:
	if bubble and bubble.visible:
		_place_bubble()
	if last_outfit.is_empty():
		return # the game hasn't started yet
	annoyed = maxf(annoyed - delta / CALM_DOWN, 0.0)
	if not score_waiting.is_empty() and not (score_waiting[2] and score_waiting[2].visible):
		_react_to_score(score_waiting[0], score_waiting[1])
		score_waiting = []
	if _holding_still():
		if not still:
			still = true
			steps = []
			hold = 0.0
			body_shaper.show_expression({}, 0.2)
		return
	if still:
		still = false
		_play(_rest())
	idle += delta
	if sulking > 0.0:
		sulking -= delta
		if sulking <= 0.0:
			_play([_say_step("sulk_over")] + _rest())
	_wait_for_demand(delta)
	if body_shaper.is_posing():
		return
	if hold > 0.0:
		hold -= delta
		return
	if not steps.is_empty():
		_next_step()
		return
	if _look_at_eyeing():
		return
	fidget_wait -= delta
	if fidget_wait <= 0.0:
		fidget_wait = randf_range(fidget_every.x, fidget_every.y)
		_play(_fidget())

# Strikes a pose for a photo, and holds it a moment after. Wait for it before taking the picture.
func pose_for_photo() -> void:
	if last_outfit.is_empty() or _holding_still():
		return
	still = false
	_play([_step(PHOTO, 0.2, true, PHOTO_HOLD), _say_step("photo", 0.5)] + _rest())
	var waited := 0.0
	while body_shaper.is_posing() and waited < 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

# The AI judge scored the look (see ai_stylist_dialog.gd): score out of best.
# She reacts once window (the judge's, which hides her) is closed.
func react_to_score(score:int, best:int, window:Control = null) -> void:
	score_waiting = [score, best, window]

# She holds still while the player arranges stickers (their frames don't follow her poses),
# fits the doll or sculpts it
func _holding_still() -> bool:
	if body_shaper.neutral:
		return true
	if sticker_stage and (not sticker_stage.selection.is_empty() or sticker_stage.drag != 0):
		return true
	if body_fitter and body_fitter.fitting:
		return true
	return body_sculptor != null and body_sculptor.sculpting


#####################################
############## REACTIONS ############
#####################################

# Starts a reaction straight away, instead of the rest of the one playing
func _play(new_steps:Array) -> void:
	steps = new_steps
	hold = 0.0
	gaze_face = {}
	_next_step()

func _next_step() -> void:
	if steps.is_empty():
		return
	var step = steps.pop_front()
	if len(step) > 4:
		if randf() < step[5]:
			_say(step[4], step[6])
	elif step[0] != null:
		body_shaper.show_expression(step[0], step[1], step[2])
	hold = step[3]

# A step of a reaction, with the face turned to the hip she stands on,
# or to facing (1 right, -1 left) when it's given
func _step(face, seconds:float, snappy := false, hold_for := 0.0, facing := 0.0) -> Array:
	if face is Dictionary:
		face = face.duplicate()
		for slider in SIDED:
			if face.has(slider):
				face[slider] *= facing if facing != 0.0 else side
	return [face, seconds, snappy, hold_for]

# A step that says a line of this kind from LINES, sometimes (chance is 0 to 1),
# with value filled in for its %d or %s
func _say_step(kind:String, chance := 1.0, value = null) -> Array:
	return [null, 0.0, false, 0.0, kind, chance, value]

func _rest() -> Array:
	return [_step(SULK if sulking > 0.0 else RESTING, 0.45)]

# A little move when nothing happens. She gets more fed up the longer she waits.
func _fidget() -> Array:
	var pick = randf()
	if sulking > 0.0:
		return [_say_step("sulking", 0.5)] + _sigh() + _rest() if pick < 0.4 else []
	var bored = idle > bored_after
	if bored and pick < 0.3:
		return [_say_step("bored", 0.5)] + _sigh() + _rest()
	if bored and pick < 0.55:
		return _eye_roll() + _rest()
	if pick < 0.7:
		side = -side
		return [_step(RESTING, 0.4, true)]
	if pick < 0.85:
		return [_step(SIDE_EYE, 0.15, true, 1.0)] + _rest()
	return _hair_flick()

func _hair_flick() -> Array:
	return [_step(HAIR_DIP, 0.15), _step(HAIR_FLICK, 0.16, true, 0.6), _step(RESTING, 0.5)]

func _eye_roll() -> Array:
	return [_step(ROLL_START, 0.15, false, 0.05), _step(ROLL_TOP, 0.18), _step(ROLL_END, 0.18, false, 0.25)]

func _sigh() -> Array:
	return [_step(SIGH, 0.7, false, 0.6)]

func _love() -> Array:
	if sulking > 0.0:
		sulking = 0.0 # something she loves makes up for it
		return [_say_step("sulk_over"), _step(LOVE, 0.18, true, 0.15), _step(LOVE_HOLD, 0.25, false, 1.3)] + _rest()
	return [_say_step("love", 0.6), _step(LOVE, 0.18, true, 0.15), _step(LOVE_HOLD, 0.25, false, 1.3)] + _rest()

# She looks it up and down: "fine, I guess"
func _not_sure() -> Array:
	return [_step(LOOK_DOWN, 0.25, false, 0.35), _say_step("not_sure", 0.4), _step(NOT_BAD, 0.3, false, 0.9)] + _rest()

# A pause, as if she can't believe it, then an eye roll and a pout
func _hate(kind := "hate", chance := 0.7) -> Array:
	return [_step(null, 0.0, false, 0.35), _say_step(kind, chance)] + _eye_roll() \
		+ [_step(POUT, 0.16, true, 1.4)] + _rest()

# Something she loved was taken off
func _offended() -> Array:
	return [_say_step("offended"), _step(GASP, 0.12, true, 0.5), _step(POUT, 0.2, true, 1.2)] + _rest()

func _impatient() -> Array:
	return [_say_step("impatient")] + _sigh() + _eye_roll() + _rest()

func _sulk() -> Array:
	sulking = sulk_time
	return [_step(GASP, 0.12, true, 0.3), _step(SULK, 0.25, true, 0.0)]

# The player clicked: if it was on her, it's a poke
func _on_doll_clicked(point:Vector2) -> void:
	if last_outfit.is_empty() or _holding_still() or not body_shaper.is_on_doll(point):
		return
	idle = 0.0
	annoyed = minf(annoyed + 1.0, POKES_TO_SULK)
	var middle = body_shaper.to_screen * body_shaper.middle
	var away = 1.0 if point.x < middle.x else -1.0 # she jumps away from the poke
	var poked = [_step(FLINCH, 0.1, true, 0.1, away)]
	var level = ceili(annoyed)
	if level >= POKES_TO_SULK:
		annoyed = 0.0
		_play(poked + [_say_step("poke_4")] + _sulk())
		return
	poked.append(_say_step("poke_head" if _on_head(point) else "poke_%d" % level))
	if sulking > 0.0:
		_play(poked + [_step(SULK, 0.2, true)])
	elif level == 1:
		_play(poked + [_step(LOOK_BACK, 0.15, true, 0.7, away)] + _rest())
	elif level == 2:
		_play(poked + [_step(GLARE, 0.15, true, 1.0, away)] + _rest())
	else:
		_play(poked + [_step(POUT, 0.16, true, 1.4, -away)] + _rest())

# Whether point is above the doll's neck
func _on_head(point:Vector2) -> bool:
	for control in body_shaper.controls():
		if control.landmark == BodyControl.Landmark.NECK:
			return point.y < body_shaper.shaped(control.global_position).y
	return false

func _react_to_score(score:int, best:int) -> void:
	var rating = float(score) / maxf(best, 1)
	if rating >= 0.8:
		_play([_say_step("judge_high", 1.0, score), _step(SMUG, 0.2, true, 1.8)] + _rest())
	elif rating >= 0.5:
		_play([_step(LOOK_DOWN, 0.25, false, 0.3), _say_step("judge_mid", 1.0, score), _step(NOT_BAD, 0.3, false, 1.2)] + _rest())
	else:
		_play([_step(null, 0.0, false, 0.4), _say_step("judge_low", 1.0, score)] + _eye_roll() + _sulk())


#####################################
############## OPINIONS #############
#####################################

# Reacts to what changed on the doll since the last time
func _on_outfit_changed() -> void:
	var outfit = interactivity.outfit.duplicate(true)
	var before = last_outfit
	last_outfit = outfit
	if before.is_empty():
		_play(_rest()) # the game just started
		return
	idle = 0.0
	var opinion := 0
	var changed := false
	var lost_favorite := false
	var got_demand := false # she got what she wanted
	var wrong_demand := false # she got something she hates instead
	for layer in interactivity.layers:
		if interactivity.is_required(layer) and not interactivity.is_background(layer):
			continue # the doll's body
		var was = before.get(layer, {})
		var now = outfit[layer]
		if was == now:
			continue
		changed = true
		if demand.get("kind") == "color" and now.item != "" and now.hue >= 0.0 \
				and absf(now.hue - demand.hue) < 0.04 and now.hue != was.get("hue"):
			got_demand = true
		elif demand.get("layer") == layer and now.item != "" and now.item != was.get("item"):
			got_demand = _opinion(layer, now.item, now.hue) >= 0
			wrong_demand = not got_demand
		if now.item == "":
			lost_favorite = lost_favorite or _opinion(layer, str(was.get("item", "")), float(was.get("hue", -1.0))) > 0
		elif now.item == was.get("item"):
			opinion += _color_opinion(layer, now.item, now.hue) # only the color changed
		else:
			opinion += _opinion(layer, now.item, now.hue)
	if not changed or _holding_still():
		return

	var now_time = Time.get_ticks_msec() / 1000.0
	changes = changes.filter(func(time): return now_time - time < FAST_TIME)
	changes.append(now_time)
	if got_demand:
		demand = {}
		demand_wait = randf_range(demand_every.x, demand_every.y)
		sulking = 0.0
		changes = []
		_play([_say_step("demand_met"), _step(LOVE, 0.18, true, 0.15), _step(LOVE_HOLD, 0.25, false, 1.5)] + _rest())
		Sfx.play("sparkle")
	elif wrong_demand:
		_play(_hate("demand_wrong", 1.0))
	elif len(changes) >= FAST_CHANGES:
		changes = []
		_play(_impatient())
	elif lost_favorite:
		_play(_offended())
	elif opinion > 0:
		_play(_love())
		Sfx.play("sparkle")
	elif sulking > 0.0:
		_play([_say_step("sulking", 0.5), _step(SULK, 0.2, true)]) # nothing less will do
	elif opinion < 0:
		_play(_hate())
	else:
		_play(_not_sure())

# 1 if she loves an item in that color, -1 if she hates it, 0 if she isn't sure
func _opinion(layer:String, item:String, hue:float) -> int:
	if item == "":
		return 0
	var name = item.get_file().get_basename().to_lower()
	for word in _words(loves):
		if name.contains(word):
			return 1
	for word in _words(hates):
		if name.contains(word):
			return -1
	var taste = posmod(hash(layer + "/" + item), 20)
	var opinion = 1 if taste < 6 else (0 if taste < 13 else -1)
	return signi(opinion + _color_opinion(layer, item, hue))

func _color_opinion(layer:String, item:String, hue:float) -> int:
	if hue < 0.0:
		return 0
	for favorite in favorite_hues:
		if absf(hue - favorite) < 0.04:
			return 1
	return posmod(hash("%s/%s/%.2f" % [layer, item, hue]), 3) - 1

static func _words(list:String) -> Array:
	var words = Array(list.to_lower().split(",")).map(func(word): return word.strip_edges())
	return words.filter(func(word): return word != "")


#####################################
############## EYEING ###############
#####################################

# The mouse moved onto an item button or color swatch (control), or off one (control is null)
func _on_hover(control, layer:String, item_id:String, hue:float) -> void:
	eyeing = null
	if control == null or not layer in interactivity.layers \
			or (interactivity.is_required(layer) and not interactivity.is_background(layer)):
		return # not a layer (such as the stickers), or the doll's body
	var worn = interactivity.outfit[layer]
	var opinion := 0
	if item_id == "" and hue >= 0.0 and worn.item != "" and not is_equal_approx(hue, worn.hue):
		opinion = _color_opinion(layer, worn.item, hue)
	elif item_id != "" and not item_id.begins_with("::") and item_id != worn.item:
		opinion = _opinion(layer, item_id, worn.hue)
	if opinion == 0:
		return # she couldn't care less
	eyeing = control
	eyeing_opinion = opinion
	if steps.is_empty() and hold <= 0.0 and sulking <= 0.0 and randf() < 0.35:
		_say("eyeing_love" if opinion > 0 else "eyeing_hate")

# While she isn't doing anything else, she looks at what she's eyeing: eyes wide and head
# tilted towards something she loves, nose up and looking away from something she hates.
# Returns true while she does.
func _look_at_eyeing() -> bool:
	var face = _eyeing_face()
	if face != gaze_face:
		gaze_face = face
		if face.is_empty():
			body_shaper.show_expression(_rest()[0][0], 0.3)
		else:
			body_shaper.show_expression(face, 0.2, true)
	return not gaze_face.is_empty()

func _eyeing_face() -> Dictionary:
	if eyeing == null or not is_instance_valid(eyeing) or not eyeing.is_visible_in_tree() or sulking > 0.0:
		return {}
	var toward = eyeing.get_global_rect().get_center() - get_viewport().canvas_transform * _head(0.0)
	var across = snappedf(clampf(toward.x / 150.0, -1.0, 1.0), 0.1)
	var up = snappedf(clampf(-toward.y / 200.0, -1.0, 1.0), 0.1)
	var face: Dictionary = _step(RESTING, 0.0)[0]
	if eyeing_opinion > 0:
		face.merge({"Look across": across, "Look up": up, "Eye size": 0.25, "Squint": 0.05, "Smile": 0.3,
			"Head tilt": face["Head tilt"] + 0.25 * signf(across)}, true)
	else:
		face.merge({"Look across": -signf(across), "Look up": 0.6, "Squint": 0.5, "Smile": -0.3,
			"Head tilt": face["Head tilt"] - 0.3 * signf(across)}, true)
	return face


#####################################
############## DEMANDS ##############
#####################################

# Counts down to her next demand, and how long she still waits for the one she made.
# She only asks when she isn't busy, and reminds the player once, half way through.
func _wait_for_demand(delta:float) -> void:
	if not demands:
		return
	var free = steps.is_empty() and hold <= 0.0 and sulking <= 0.0
	if demand.is_empty():
		demand_wait -= delta
		if demand_wait <= 0.0 and free:
			_make_demand()
		return
	demand_left -= delta
	if demand_left <= 0.0:
		demand = {}
		demand_wait = randf_range(demand_every.x, demand_every.y)
		_play([_say_step("demand_failed")] + _sigh() + _eye_roll() + _rest())
	elif demand_left <= DEMAND_TIME / 2 and not demand.reminded and free:
		demand.reminded = true
		_play([_step(SIDE_EYE, 0.15, true), _say_step("remind_" + demand.kind, 1.0, demand.name),
			_step(null, 0.0, false, 1.2)] + _rest())

# Picks something to want: one of her favorite colors, a new item for a layer that has
# more than one, or a new background
func _make_demand() -> void:
	var options := []
	for hue in favorite_hues:
		options.append({"kind": "color", "hue": hue, "name": _color_name(hue)})
	for i in len(interactivity.layers):
		var layer = interactivity.layers[i]
		if (interactivity.is_required(layer) and not interactivity.is_background(layer)) \
				or len(interactivity.tab_nodes[i].get_item_ids()) < 2:
			continue
		var kind = "background" if interactivity.is_background(layer) else "layer"
		options.append({"kind": kind, "layer": layer, "name": _layer_name(layer)})
	if options.is_empty():
		demand_wait = randf_range(demand_every.x, demand_every.y)
		return
	demand = options.pick_random()
	demand.reminded = false
	demand_left = DEMAND_TIME
	_play([_step(DEMAND, 0.2, true), _say_step("demand_" + demand.kind, 1.0, demand.name),
		_step(null, 0.0, false, 1.5)] + _rest())

# The name of the color swatch closest to hue, such as "pink" (see tab_of_buttons.gd)
func _color_name(hue:float) -> String:
	var tab = interactivity.tab_nodes[0]
	var closest = 1
	for i in range(1, len(tab.SWATCH_HUES)):
		if absf(tab.SWATCH_HUES[i] - hue) < absf(tab.SWATCH_HUES[closest] - hue):
			closest = i
	return tab.SWATCH_NAMES[closest]

# A layer's folder name without its number, such as "hair" for 03Hair
static func _layer_name(layer:String) -> String:
	var name = layer
	while name != "" and (name[0].is_valid_int() or name[0] in "_- "):
		name = name.substr(1)
	return name.to_lower() if name != "" else "outfit"


#####################################
############## SPEECH BUBBLE ########
#####################################

# Says a line of this kind from LINES, with value filled in for its %d or %s
func _say(kind:String, value = null) -> void:
	if not talks or bubble == null:
		return
	var lines = Array(LINES.get(kind, [])).filter(func(line): return line != last_line)
	if lines.is_empty():
		return
	last_line = lines.pick_random()
	var label: Label = bubble_panel.get_child(0)
	label.text = last_line % value if value != null and last_line.contains("%") else last_line
	label.text = label.text[0].to_upper() + label.text.substr(1)
	bubble_panel.reset_size()
	bubble.show()
	_place_bubble()
	if bubble_tween:
		bubble_tween.kill()
	bubble.modulate.a = 0.0
	bubble.scale = Vector2.ONE * 0.6
	bubble_tween = bubble.create_tween()
	bubble_tween.tween_property(bubble, "modulate:a", 1.0, 0.1)
	bubble_tween.parallel().tween_property(bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bubble_tween.tween_interval(BUBBLE_TIME + BUBBLE_TIME_PER_LETTER * len(label.text))
	bubble_tween.tween_property(bubble, "modulate:a", 0.0, 0.3)
	bubble_tween.tween_callback(bubble.hide)

# A panel like the toolbar's messages, with a tail pointing at her head
func _make_bubble() -> void:
	bubble = Control.new()
	bubble.name = "SpeechBubble"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 10
	bubble.hide()
	var tail = Control.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.draw.connect(func(): _draw_tail(tail))
	bubble.add_child(tail)
	bubble_panel = PanelContainer.new()
	bubble_panel.theme_type_variation = &"Toast"
	bubble_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label = Label.new()
	label.theme_type_variation = &"ToastLabel"
	bubble_panel.add_child(label)
	bubble.add_child(bubble_panel)
	bubble_parent.add_child(bubble)

func _draw_tail(tail:Control) -> void:
	var style = bubble_panel.get_theme_stylebox("panel")
	var color = style.bg_color if style is StyleBoxFlat else Color(0.16, 0.13, 0.33, 0.9)
	var across = -1.0 if bubble_flipped else 1.0
	tail.draw_colored_polygon(PackedVector2Array([Vector2.ZERO,
		Vector2(across * (BUBBLE_TAIL.x + 4), -BUBBLE_TAIL.y - 1),
		Vector2(across * (BUBBLE_TAIL.x + 18), -BUBBLE_TAIL.y - 1)]), color)

# Puts the bubble's tail at the top of her head, where it is on the screen now (zoomed or not),
# and its panel to the right, or to the left when there's no room
func _place_bubble() -> void:
	var spot = get_viewport().canvas_transform * _head(0.7)
	var room = bubble_parent.size
	var size = bubble_panel.size
	var flipped = spot.x + BUBBLE_TAIL.x + size.x > room.x - 8 and spot.x - BUBBLE_TAIL.x - size.x >= 8
	if flipped != bubble_flipped:
		bubble_flipped = flipped
		bubble.get_child(0).queue_redraw()
	spot.y = maxf(spot.y, size.y + BUBBLE_TAIL.y + 8)
	bubble.position = spot
	bubble_panel.position = Vector2(-BUBBLE_TAIL.x - size.x if flipped else BUBBLE_TAIL.x, -BUBBLE_TAIL.y - size.y)

# A spot on her head, on the doll (not the screen): up is how far above its middle,
# from 0 (the middle) to 1 (the top). Without a Head control, the top of the doll's pictures.
func _head(up:float) -> Vector2:
	for control in body_shaper.controls():
		if control.landmark == BodyControl.Landmark.HEAD:
			return body_shaper.shaped(control.global_position - Vector2(0, control.reach.y * control.global_scale.y * up))
	return body_shaper.to_screen * (body_shaper.middle - Vector2(0, body_shaper.image_size.y / 2))
