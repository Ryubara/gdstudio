class_name MenuSoundService
extends Node
## The menus' sounds: every gds_ui control and the router send their cues here (`UIAudio`), and a
## table of roles and cues picks one of the players under this node, each with its own stream,
## volume and pitch on the `UI` bus. Tune a sound by selecting its player (or swapping its stream);
## the rules below only decide when one plays.
##
## A control's role is its `ui_sound_role` metadata when it has one (a settings tab says `tab`, a
## Back button `back`), else what the control says itself (`ui_sound_role()`: a primary button,
## a toggle, a slider...). Hover and focus are one quiet hint, never two for one control, and none
## at all for a finger, a disabled control, a screen still moving in, or within
## `quiet_after_action` of a press (the screen it opens took the focus, the player did not move
## it). A screen's swish plays only when nothing was pressed just before it (Esc opening the pause
## menu): the press is the sound of the screen it opens. Slider ticks are spaced by `tick_gap` and
## rise in pitch with the value. Kit docs: gamedev/audio/ui-sounds.md, engines/godot/audio.md.

## The quiet hint for hover and focus.
const HINT := &"Hint"
## Role and cue to the player that sounds it; `&""` is a silence written down. A role or a cue the
## table does not know is reported once (`unknown`).
const TABLE := {
	&"button_primary": {&"hover": HINT, &"focus": HINT, &"press": &"Confirm"},
	&"button_secondary": {&"hover": HINT, &"focus": HINT, &"press": &"Press"},
	&"button_ghost": {&"hover": HINT, &"focus": HINT, &"press": &"Press"},
	&"tab": {&"hover": HINT, &"focus": HINT, &"press": &"Tab", &"tab": &"Tab"},
	&"back": {&"hover": HINT, &"focus": HINT, &"press": &"Back"},
	&"toggle": {&"hover": HINT, &"focus": HINT, &"on": &"ToggleOn", &"off": &"ToggleOff"},
	&"slider": {&"hover": HINT, &"focus": HINT, &"tick": &"Tick"},
	&"option": {&"hover": HINT, &"focus": HINT, &"select": &"Select"},
	# Typing is silent: the field's focus is its sound.
	&"field": {&"hover": HINT, &"focus": HINT},
	&"list": {&"hover": HINT, &"focus": HINT, &"tick": &"Tick", &"press": &"Press"},
	# An inventory slot: a choice from a set.
	&"cell": {&"hover": HINT, &"focus": HINT, &"select": &"Select"},
	&"router": {&"back": &"Back", &"push": &"Open", &"pop": &"Close"},
}
## Cues any source may send (a game's own code): a commit that went through, one that cannot.
const ANY_SOURCE := {&"confirm": &"Confirm", &"refuse": &"Refuse"}
## Cues that are the player acting: a hint or a swish right after one belongs to it.
const ACTIONS: Array[StringName] = [
	&"press", &"confirm", &"refuse", &"back", &"tab", &"select", &"on", &"off"
]

## Plays nothing when off (the cues still arrive).
@export var enabled := true
## The shortest time between two hints, seconds: a pointer swept down a column is not a drum roll.
@export_range(0.0, 0.5, 0.01, "suffix:s") var hint_gap := 0.07
## How long after a press (or a back, a toggle...) a hint or a screen's swish stays silent, seconds.
@export_range(0.0, 1.0, 0.01, "suffix:s") var quiet_after_action := 0.3
## The shortest time between two slider ticks, seconds.
@export_range(0.0, 0.5, 0.01, "suffix:s") var tick_gap := 0.06
## The tick's pitch at a slider's lowest and highest value.
@export var tick_pitch := Vector2(0.9, 1.25)

## Cues heard, as `[cue, player name]` (`&""` when silent), for a test. Kept to the last 64.
var heard: Array = []

var _now := 0.0
var _last_action := -INF
var _last_hint := -INF
var _last_tick := -INF
var _hover_source: Object = null
var _reported := {}


func _enter_tree() -> void:
	UIAudio.handler = handle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Decoded once while loading: a press then starts in a microsecond, not a Vorbis set-up.
	for player in players():
		player.stream = DecodedSounds.decoded(player.stream)


func _exit_tree() -> void:
	if UIAudio.handler == Callable(self, &"handle"):
		UIAudio.handler = Callable()
	for player in players():
		player.stop()


func _process(delta: float) -> void:
	_now += delta


## Moves the clock the gaps are read on, seconds (`_process` does it each frame; a test can too).
func advance(seconds: float) -> void:
	_now += seconds


## Every sound's player.
func players() -> Array[AudioStreamPlayer]:
	var found: Array[AudioStreamPlayer] = []
	for child in get_children():
		if child is AudioStreamPlayer:
			found.append(child as AudioStreamPlayer)
	return found


## What kind of control `source` is for the table: its `ui_sound_role` metadata, what it says of
## itself, `router` for the router, else `&""`.
static func role_of(source: Object) -> StringName:
	if source == null:
		return &""
	if source.has_meta(&"ui_sound_role"):
		return StringName(source.get_meta(&"ui_sound_role"))
	if source.has_method(&"ui_sound_role"):
		return source.call(&"ui_sound_role")
	if source is CanvasLayer and source.has_signal(&"screen_changed"):
		return &"router"
	return &""


## The player the table names for `cue` from `source` (`&""`: silent by the table).
static func sound_for(cue: StringName, source: Object) -> StringName:
	if ANY_SOURCE.has(cue):
		return ANY_SOURCE[cue]
	var row: Dictionary = TABLE.get(role_of(source), {})
	return row.get(cue, &"")


## Whether the table has a row for this role and cue (a missing one is a bug a test finds).
static func knows(cue: StringName, source: Object) -> bool:
	return ANY_SOURCE.has(cue) or (TABLE.get(role_of(source), {}) as Dictionary).has(cue)


## One cue of the `UIAudio` vocabulary: the table picks the sound, the rules decide if it plays.
func handle(cue: StringName, source: Object = null) -> void:
	if not knows(cue, source):
		_unknown(cue, source)
		_hear(cue, &"")
		return
	var sound := sound_for(cue, source)
	if cue in ACTIONS:
		_last_action = _now
	if sound == HINT and not _hint_allowed(cue, source):
		sound = &""
	elif cue == &"push" or cue == &"pop":
		if _now - _last_action < quiet_after_action:
			sound = &""
		_last_action = _now
	elif sound == &"Tick":
		if _now - _last_tick < tick_gap:
			sound = &""
		else:
			_last_tick = _now
	if sound == &"" or not enabled:
		_hear(cue, &"")
		return
	var player := get_node_or_null(NodePath(sound)) as AudioStreamPlayer
	if player == null:
		_unknown(cue, source)
		_hear(cue, &"")
		return
	if sound == &"Tick":
		player.pitch_scale = _tick_pitch(source)
	player.play()
	_hear(cue, sound)


func _hint_allowed(cue: StringName, source: Object) -> bool:
	var was_hovered := _hover_source == source
	if cue == &"hover":
		_hover_source = source
	# A finger has no hover; a disabled control and a screen still moving in were not the player.
	var silent := (
		UIInputMode.touch
		or (source is BaseButton and (source as BaseButton).disabled)
		or _router_busy()
		or _now - _last_action < quiet_after_action
		or _now - _last_hint < hint_gap
	)
	# Hover and focus are one sound: a click focuses the button the pointer is already on, and a
	# pointer arriving on the focused control adds nothing.
	silent = silent or (cue == &"focus" and was_hovered)
	silent = silent or (cue == &"hover" and source is Control and (source as Control).has_focus())
	if not silent:
		_last_hint = _now
	return not silent


func _router_busy() -> bool:
	var router := get_node_or_null(^"/root/UIRouter")
	return router != null and bool(router.get(&"busy"))


func _tick_pitch(source: Object) -> float:
	var value_range := source as Range
	if value_range == null or value_range.max_value <= value_range.min_value:
		return tick_pitch.x
	var t := inverse_lerp(value_range.min_value, value_range.max_value, value_range.value)
	return lerpf(tick_pitch.x, tick_pitch.y, clampf(t, 0.0, 1.0))


func _hear(cue: StringName, sound: StringName) -> void:
	heard.append([cue, sound])
	if heard.size() > 64:
		heard.pop_front()


func _unknown(cue: StringName, source: Object) -> void:
	var key := "%s/%s" % [role_of(source), cue]
	if _reported.has(key):
		return
	_reported[key] = true
	push_warning("MenuSoundService: no sound for cue '%s' of role '%s'." % [cue, role_of(source)])
