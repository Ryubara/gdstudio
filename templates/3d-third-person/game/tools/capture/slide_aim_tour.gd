## Films shooting while sliding (kit #1253) from the game camera behind the character: a sprint
## into a slide, then the aim held and the view turned ahead, to the left and to the right of the
## slide (and up and down), with a shot in each, so the arms swing to put the pistol on the
## crosshair while the body slides on along its line. It presses the input actions the way a player
## would (it only puts the body back at the start of a stage and turns the camera as a mouse
## would). The slide is made longer and slower than the template's (a copy of its tuning), so each
## aim holds long enough to see.
##
## `AIM_LAYER_OFF=1` turns the aim layer off (the clips alone: the pistol pointed at the sky).
## `CLOSE=1` films the hands from a camera beside them instead (the grip, the trigger finger and
## the support hand in each direction); `CLOSE_SIDE=left` puts it on the left of the body.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/slide_aim_tour.tscn --seconds 16
## --fps 20`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone).
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 18.0)
## A row of boards ahead of the slide, so the shots have something to land on.
const BOARDS_AT := -14.0
## The camera's look down while sprinting, degrees.
const PITCH := 6.0
## The stages: `name`, `yaw` and `pitch` the view turns to while aiming (degrees: positive yaw to
## the left, positive pitch looks up), `seconds` of aiming, a shot at `fire_at` seconds.
const AIMS: Array[Dictionary] = [
	{"name": "ahead", "yaw": 0.0, "pitch": 0.0},
	{"name": "left", "yaw": 55.0, "pitch": 0.0},
	{"name": "right", "yaw": -55.0, "pitch": 0.0},
	{"name": "up", "yaw": 0.0, "pitch": 20.0},
	{"name": "down", "yaw": 15.0, "pitch": -20.0},
]
const SPRINT_SECONDS := 1.1
const DROP_SECONDS := 0.2
const AIM_SECONDS := 1.6
const FIRE_AT := 0.9

var _index := -1
var _clock := 0.0
var _phase := 0
var _held: Array[StringName] = []
var _close: Camera3D

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var blocks := load("res://world/blocks/proto_block.tscn") as PackedScene
	var floor_block := blocks.instantiate()
	floor_block.size = Vector3(40.0, 1.0, 50.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	for x in range(-12, 13, 4):
		var board := blocks.instantiate()
		board.size = Vector3(1.5, 2.5, 0.3)
		board.position = Vector3(float(x), 301.25, BOARDS_AT + absf(x) * 0.3)
		add_child(board)
	_player.slide_tuning = _player.slide_tuning.duplicate()
	_player.slide_tuning.max_time = 4.0
	_player.slide_tuning.friction = 0.6
	_player.slide_tuning.drag = 0.05
	(_player.get_node("AimLayer") as AimLayer).disabled = OS.get_environment("AIM_LAYER_OFF") == "1"
	if OS.get_environment("CLOSE") == "1":
		_close = Camera3D.new()
		_close.fov = 40.0
		# Placed every drawn frame from the drawn pose: no smoothing between ticks.
		_close.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_close)
		_close.make_current()
	_player.teleport(START, PI)


func _physics_process(delta: float) -> void:
	if _index >= AIMS.size():
		return
	if _index < 0 or _phase_done():
		_next_phase()
		if _index >= AIMS.size():
			_finish()
			return
	_clock += delta
	var aim := AIMS[_index]
	var actions: Array[StringName] = []
	match _phase:
		0:
			_turn_to(0.0, -PITCH)
			actions = [&"move_forward", &"sprint"]
		1:
			actions = [&"move_forward", &"sprint", &"crouch"]
		2:
			_turn_to(aim["yaw"], aim["pitch"])
			actions = [&"crouch", &"aim"]
			if _clock >= FIRE_AT and _clock < FIRE_AT + 0.1:
				actions.append(&"fire")
	_hold(actions)


func _process(_delta: float) -> void:
	if _close == null:
		return
	# Beside the hands, a little ahead of the chest, looking back at the pistol.
	var muzzle := _player.weapon.muzzle
	if muzzle == null:
		return
	var side := -1.0 if OS.get_environment("CLOSE_SIDE") == "left" else 1.0
	var body := _player.model.global_basis
	var grip := muzzle.global_position - muzzle.global_basis.z * -0.12
	_close.global_position = grip + body.x * side * -0.7 + body.z * 0.45 + Vector3.UP * 0.2
	_close.look_at(grip, Vector3.UP)


func _phase_done() -> bool:
	var lengths := [SPRINT_SECONDS, DROP_SECONDS, AIM_SECONDS]
	return _clock >= float(lengths[_phase])


func _next_phase() -> void:
	_clock = 0.0
	_phase += 1
	if _index >= 0 and _phase <= 2:
		return
	_phase = 0
	_index += 1
	if _index >= AIMS.size():
		return
	print("STAGE ", AIMS[_index]["name"])
	_hold([])
	_player.teleport(START, PI)
	_rig.yaw = 0.0


# Turns the view toward `yaw` and `pitch` (degrees, positive pitch up) as a mouse would, a few
# degrees a tick.
func _turn_to(yaw: float, pitch: float) -> void:
	var turn := clampf(wrapf(yaw - _rig.yaw, -180.0, 180.0), -5.0, 5.0)
	var lift := clampf(-pitch - _rig.pitch, -3.0, 3.0)
	_rig.orbit(Vector2(-turn, lift))


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
