## Films the slide from the game camera, beside the character: a sprint into a slide that ends
## crouched, a slide let go of (it stands), a jump out of a slide, a slide under a gap too low to
## crouch in, and a slide down a ramp. It presses the input actions the way a player would (it
## only puts the body back at the start of a stage), for the pull request's captures.
## `SLIDE_OFF=1` turns the slide off, which is how crouch at a sprint behaved before it.
## `SLIDE_WEAPON=rifle` gives the player the rifle and slides with it in the hands (kit #1413).
## `SLIDE_WEAPON=unarmed` slides with the hands empty, `SLIDE_BODY=male` in the male body
## (kit #1439, the slide's end into the crouch).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/slide_tour.tscn --seconds 17
## --fps 20`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone), where each
## stage starts, and the camera's pitch.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(-20.0, 300.1, 0.0)
const PITCH := 8.0
## The camera backs off the shoulder view so the whole body is in the frame.
const DISTANCE := 4.2
## A slab whose underside is 1.0 m over the floor (under the crouch's 1.1 m, over the slide's
## 0.9 m), 4 m long, in a lane of its own (the other stages run along z = 0) and narrow, so the
## camera's arm passes beside it.
const GAP_AT := Vector3(-8.0, 301.2, -8.0)
const GAP_SIZE := Vector3(4.0, 0.4, 1.2)
## A ramp down to the right, 18 degrees, past the gap.
const RAMP_AT := Vector3(12.0, 297.0, 0.0)
const RAMP_DEGREES := 18.0

## The tour, as in `carry_tour.gd`: `name`, `hold`, `seconds`, `reset` (to `at`, or the start),
## `tap` pressed for `tap_seconds` at `tap_at` seconds into the stage.
const STAGES: Array[Dictionary] = [
	{"name": "sprint", "hold": [&"move_right", &"sprint"], "seconds": 1.0, "reset": true},
	{"name": "slide", "hold": [&"move_right", &"sprint", &"crouch"], "seconds": 1.8},
	{"name": "stand", "hold": [], "seconds": 0.6},
	{"name": "sprint", "hold": [&"move_right", &"sprint"], "seconds": 1.0, "reset": true},
	{"name": "slide let go", "hold": [&"move_right", &"sprint", &"crouch"], "seconds": 0.5},
	{"name": "run on", "hold": [&"move_right"], "seconds": 0.8},
	{"name": "sprint", "hold": [&"move_right", &"sprint"], "seconds": 1.0, "reset": true},
	{
		"name": "slide jump",
		"hold": [&"move_right", &"sprint", &"crouch"],
		"seconds": 1.4,
		"tap": [&"jump"],
		"tap_at": 0.35,
		"tap_seconds": 0.2,
	},
	{
		"name": "sprint",
		"hold": [&"move_right", &"sprint"],
		"seconds": 0.9,
		"reset": true,
		"at": Vector3(-17.0, 300.1, -8.0),
	},
	{"name": "slide under the gap", "hold": [&"move_right", &"crouch"], "seconds": 2.6},
	{"name": "stand past it", "hold": [], "seconds": 0.6},
	{
		"name": "sprint",
		"hold": [&"move_right", &"sprint"],
		"seconds": 0.8,
		"reset": true,
		"at": Vector3(12.0, 300.1, 0.0),
	},
	{"name": "slide down the ramp", "hold": [&"move_right", &"sprint", &"crouch"], "seconds": 2.6},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var blocks := load("res://world/blocks/proto_block.tscn") as PackedScene
	var floor_block := blocks.instantiate()
	floor_block.size = Vector3(40.0, 1.0, 24.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var gap := blocks.instantiate()
	gap.size = GAP_SIZE
	gap.position = GAP_AT
	add_child(gap)
	var ramp := blocks.instantiate()
	ramp.size = Vector3(30.0, 1.0, 24.0)
	ramp.rotation.z = deg_to_rad(-RAMP_DEGREES)
	# Its top edge meets the floor's right end (x = 20, y = 300).
	var half := 15.0
	var angle := deg_to_rad(RAMP_DEGREES)
	ramp.position = Vector3(
		20.0 + half * cos(angle) - 0.5 * sin(angle),
		300.0 - half * sin(angle) - 0.5 * cos(angle),
		0.0
	)
	add_child(ramp)
	if OS.get_environment("SLIDE_OFF") == "1":
		_player.slide_tuning.enabled = false
	_rig.distance = DISTANCE
	_player.teleport(START, PI / 2.0)
	if OS.get_environment("SLIDE_WEAPON") == "rifle":
		_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 60)
	if OS.get_environment("SLIDE_WEAPON") == "unarmed":
		_player.loadout.equip_now(WeaponLoadout.UNARMED)
	if OS.get_environment("SLIDE_BODY") == "male":
		_player.model.variant = load(CharacterBodies.MALE) as PackedScene


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_next()
		if _index >= STAGES.size():
			_finish()
			return
	var stage := STAGES[_index]
	_clock += delta
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	if stage.has("tap"):
		var from := float(stage["tap_at"])
		if _clock >= from and _clock < from + float(stage["tap_seconds"]):
			actions.append_array(stage["tap"])
	_hold(actions)


func _next() -> void:
	_index += 1
	_clock = 0.0
	if _index >= STAGES.size():
		return
	var stage := STAGES[_index]
	print("STAGE ", stage["name"], " ", _player.global_position, " ", _player.ground_speed())
	if stage.get("reset", false):
		_hold([])
		_player.teleport(stage.get("at", START), PI / 2.0)


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
