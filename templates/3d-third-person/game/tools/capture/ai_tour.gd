## Films the three shipped AI profiles side by side from the player's own camera, with the debug
## overlay on (profile, situation and tier above each head): a grunt, an ally and a civilian
## stand in a row; the ally steps aside on its movement channel and turns Alert, the civilian
## turns Fleeing, and the grunt is killed by a hit through its `Health` and goes into the ragdoll.
## The characters are `ai_character.tscn`, managed by the level's `AiDirector`.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/ai_tour.tscn --seconds 7`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const CHARACTER := "res://gameplay/ai/ai_character.tscn"
const PROFILES: Array[String] = [
	"res://gameplay/ai/profiles/grunt.tres",
	"res://gameplay/ai/profiles/ally.tres",
	"res://gameplay/ai/profiles/civilian.tres",
]
## Where the player stands (looking along -Z) and the row the characters stand in, facing it.
const STAND := Vector3(-7.0, 0.0, 16.5)
const ROW_Z := 12.0
const ROW_X: Array[float] = [-5.0, -3.3, -1.6]
## Seconds into the clip of each beat.
const ALLY_STEPS := 2.0
const ALLY_STOPS := 2.6
const CIVILIAN_FLEES := 3.0
const GRUNT_DIES := 3.8
const END := 6.5
## Camera pitch, in degrees, while filming.
const PITCH := 4.0

var _clock := 0.0
var _characters: Array[AiCharacter] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_player.teleport(STAND, PI)
	for index in PROFILES.size():
		var character := (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
		character.profile = load(PROFILES[index]) as AiProfile
		character.debug = true
		_player.get_parent().add_child(character)
		character.teleport(Vector3(ROW_X[index], 0.0, ROW_Z), 0.0)
		_characters.append(character)


func _physics_process(delta: float) -> void:
	var was := _clock
	_clock += delta
	_face()
	var grunt := _characters[0]
	var ally := _characters[1]
	var civilian := _characters[2]
	if _crossed(was, ALLY_STEPS):
		ally.ai_controller().walk_direction = Vector3.RIGHT
		ally.ai_controller().walk_strength = 0.35
		ally.situation.request(AiSituation.Situation.ALERT)
	if _crossed(was, ALLY_STOPS):
		ally.ai_controller().release()
	if _crossed(was, CIVILIAN_FLEES):
		civilian.situation.request(AiSituation.Situation.FLEEING)
	if _crossed(was, GRUNT_DIES):
		grunt.take_hit(HitRecord.blow(Health.of(grunt).max_value, _player))
	if _crossed(was, END):
		_finish()


func _crossed(was: float, at: float) -> bool:
	return was < at and _clock >= at


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds the camera along -Z at a small pitch, a few degrees a frame.
func _face() -> void:
	var by_yaw := clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0)
	var by_pitch := clampf(PITCH - _rig.pitch, -2.0, 2.0)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
