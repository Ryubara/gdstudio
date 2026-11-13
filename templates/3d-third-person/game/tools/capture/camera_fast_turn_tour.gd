## Turns the camera at full mouse speed beside the AI section's orange screen wall, the turn of
## kit #1344 (the view went inside the wall for a few frames): a steady fast turn each way, a
## flick, and a run along the wall while turning. The turns are mouse motion events sent through
## `Input`, as a player's mouse sends them; it prints, every physics tick, the share of the
## shoulder offset the lens guard allows (`LENS`).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 9 --fps 60 --name fast-turn`
## with `--scene res://tools/capture/camera_fast_turn_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Beside the middle of the orange screen (its east face is at x = -51.5), facing north.
const SPOT := Vector3(-50.95, 0.0, -9.0)

## The tour. Each step: `wait` for `frames`; `turn` by `degrees` a frame for `frames` (positive
## turns right), with `actions` held.
const TOUR: Array[Dictionary] = [
	{"do": "wait", "frames": 50},
	{"do": "turn", "degrees": 12.0, "frames": 30, "actions": []},
	{"do": "wait", "frames": 30},
	{"do": "turn", "degrees": -12.0, "frames": 30, "actions": []},
	{"do": "wait", "frames": 30},
	{"do": "turn", "degrees": 30.0, "frames": 12, "actions": []},
	{"do": "wait", "frames": 30},
	{"do": "turn", "degrees": 6.0, "frames": 60, "actions": [&"move_forward"]},
	{"do": "wait", "frames": 30},
]

var _index := 0
var _frames := 0
var _held: Array[StringName] = []
var _degrees_per_pixel := 0.0
var _calibrating := 0
var _yaw_before := 0.0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _camera: Camera3D = $Main/PlayerRig/Camera


func _ready() -> void:
	_rig.require_captured_mouse = false


func _physics_process(_delta: float) -> void:
	if _calibrating == 0:
		_player.teleport(SPOT)
		_rig.yaw = 0.0
		_yaw_before = _rig.yaw
		_mouse(10.0)
		_calibrating = 1
		return
	if _calibrating < 4:
		_calibrating += 1
		if _calibrating == 4:
			_degrees_per_pixel = absf(wrapf(_rig.yaw - _yaw_before, -180.0, 180.0)) / 10.0
			_rig.yaw = 0.0
		return
	var lens: CameraLensGuard = _rig.get(&"_lens")
	print(
		"LENS yaw ", snappedf(_rig.yaw, 1.0), " room ", snappedf(lens.room, 0.01) if lens else 1.0
	)
	if _index >= TOUR.size():
		_hold([])
		_finish()
		return
	var step := TOUR[_index]
	_frames += 1
	if step["do"] == "turn":
		_hold(step["actions"])
		_mouse(float(step["degrees"]) / maxf(_degrees_per_pixel, 0.0001))
	else:
		_hold([])
	if _frames >= int(step["frames"]):
		_index += 1
		_frames = 0


func _mouse(pixels: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(pixels, 0.0)
	Input.parse_input_event(motion)


func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame_count in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)
