## Films the character aiming the pistol from the player's own camera, as the game shows it:
## standing through the idle's weight shift, walking forward, then standing again (kit #1154).
## The crosshair is where the view points, so a pistol that points off it is seen at once.
## `AIM_BRACE=0` turns `CharacterAnimation.aim_brace` off (the aim pose then turns with the
## pelvis of the legs' clip) and `AIM_IDLE=ual1/Idle` plays another idle clip, for the pull
## request's before and after.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/aim_brace_tour.tscn --seconds 9
## --fps 12`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone).
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 10.0)
const PITCH := 0.0

## Each stage: `name` (printed when it starts), `hold` the actions held and `seconds` how long.
const STAGES: Array[Dictionary] = [
	{"name": "aim standing", "hold": [&"aim"], "seconds": 5.0},
	{"name": "aim walking", "hold": [&"aim", &"move_forward"], "seconds": 2.5},
	{"name": "aim standing again", "hold": [&"aim"], "seconds": 1.5},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var animation: CharacterAnimation = _player.get_node("Animation")
	if OS.get_environment("AIM_BRACE") == "0":
		animation.aim_brace = false
	if OS.get_environment("AIM_IDLE") != "":
		animation.idle_clip = StringName(OS.get_environment("AIM_IDLE"))
	print("aim_brace ", animation.aim_brace, " idle ", animation.idle_clip)
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(30.0, 1.0, 60.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_player.teleport(START, PI)


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		print("STAGE ", STAGES[_index]["name"])
	_clock += delta
	var actions: Array[StringName] = []
	actions.append_array(STAGES[_index]["hold"])
	_hold(actions)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	_hold([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array[StringName]) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action in actions:
		Input.action_press(action)
		_held.append(action)
