## Plays the prone aim the way a player would, for a clip: the character lies down, aims, looks
## up and down to the prone look limits, shoots three times, crawls while it aims, turns and
## gets up. It presses the input actions (never moves the body itself) and turns the camera with
## the same `orbit()` the mouse, the stick and the touch layer use.
##
## The picture is the player's own camera, or with `PRONE_AIM_VIEW` set a camera of the tour's
## that rides the body: `side`, `front`, `top`, or `hands`, `hands_left`, `hands_top` and
## `hands_front` (close on the pistol from its right, its left, above and ahead, for the hands on
## the weapon). `PRONE_AIM_MODEL=male` swaps the mannequin, and `PRONE_AIM_STANDING_VIEW=1` aims
## with the camera's standing aim view (`PlayerCamera.prone_aim_view` off), to compare.
##
## `gds capture frames --project game --scene res://tools/capture/prone_aim_tour.tscn --seconds 14`
## It prints a `STEP` line as each step starts, with the frame, to find a moment's frame. It
## lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Camera turn speed toward a heading, in degrees a second.
const TURN_SPEED := 90.0
## Where the tour starts: open ground on the east side of the map.
const START := Vector3(5.5, 0.0, 8.0)
## The tour's own views: where the camera is and what it looks at, in the body's space (+Z its
## front, the origin under the lying body's middle; for the `hands` views the origin is the
## pistol's grip), and its field of view.
const VIEWS: Dictionary = {
	"side": [Vector3(-2.2, 0.45, 0.35), Vector3(0.0, 0.2, 0.35), 40.0],
	"front": [Vector3(-0.9, 0.5, 2.3), Vector3(0.0, 0.2, 0.5), 40.0],
	"top": [Vector3(0.0, 2.6, 0.45), Vector3(0.0, 0.0, 0.5), 40.0],
	"hands": [Vector3(-0.45, 0.12, -0.08), Vector3(0.0, 0.03, 0.02), 30.0],
	"hands_left": [Vector3(0.45, 0.12, -0.08), Vector3(0.0, 0.03, 0.02), 30.0],
	"hands_top": [Vector3(0.0, 0.6, -0.1), Vector3(0.0, 0.0, 0.02), 30.0],
	"hands_front": [Vector3(-0.12, 0.1, 0.7), Vector3(0.0, 0.03, 0.0), 30.0],
}

## The tour: `wait` holds `actions` for `seconds`; `tap` presses one action for a moment; `look`
## turns the camera to a heading and a pitch while it holds `actions`.
const TOUR: Array[Dictionary] = [
	{"do": "look", "yaw": 0.0, "pitch": 4.0, "actions": []},
	{"do": "wait", "actions": [], "seconds": 0.4},
	{"do": "tap", "action": &"prone"},
	{"do": "wait", "actions": [], "seconds": 1.0},
	{"do": "wait", "actions": [&"aim"], "seconds": 1.2},
	{"do": "look", "yaw": 0.0, "pitch": -12.0, "actions": [&"aim"]},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.7},
	{"do": "look", "yaw": 0.0, "pitch": 40.0, "actions": [&"aim"]},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.7},
	{"do": "look", "yaw": 0.0, "pitch": 2.0, "actions": [&"aim"]},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.4},
	{"do": "wait", "actions": [&"aim", &"fire"], "seconds": 0.1},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.4},
	{"do": "wait", "actions": [&"aim", &"fire"], "seconds": 0.1},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.4},
	{"do": "wait", "actions": [&"aim", &"fire"], "seconds": 0.1},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.6},
	{"do": "wait", "actions": [&"aim", &"move_forward"], "seconds": 1.6},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.4},
	{"do": "look", "yaw": 50.0, "pitch": 2.0, "actions": [&"aim"]},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.8},
	{"do": "wait", "actions": [], "seconds": 0.6},
	{"do": "tap", "action": &"prone"},
	{"do": "wait", "actions": [], "seconds": 1.3},
]

var _index := 0
var _clock := 0.0
var _frame := 0
var _held: Array[StringName] = []
var _started := false
var _view: Array = []
var _camera: Camera3D
var _on_pistol := false

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_view = VIEWS.get(OS.get_environment("PRONE_AIM_VIEW"), [])
	_rig.prone_aim_view = OS.get_environment("PRONE_AIM_STANDING_VIEW").is_empty()
	_on_pistol = OS.get_environment("PRONE_AIM_VIEW").begins_with("hands")
	if OS.get_environment("PRONE_AIM_MODEL") == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		var male := load("res://assets/characters/mannequin/mannequin_male.glb") as PackedScene
		slot.add_child(male.instantiate())
	if not _view.is_empty():
		_add_view()


# The tour's own camera draws over the game in a viewport of its own (same world): the game's
# camera stays the window's, since the player aims along it and would turn after any other.
func _add_view() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(container)
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	_camera = Camera3D.new()
	_camera.fov = _view[2]
	_camera.near = 0.02
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(_camera)
	_camera.make_current()


func _process(_delta: float) -> void:
	if _camera == null:
		return
	# The tour's own camera rides the body (or the pistol).
	var body := Transform3D(Basis(Vector3.UP, _player.facing), _player.global_position)
	if _on_pistol:
		body.origin = (_player.get_node("Model/PistolHeld/Pistol") as Node3D).global_position
	_camera.global_position = body * (_view[0] as Vector3)
	_camera.look_at(body * (_view[1] as Vector3))


func _physics_process(delta: float) -> void:
	_frame += 1
	if not _started:
		_started = true
		_player.teleport(START, PI)
		return
	if _index >= TOUR.size():
		_hold([])
		_finish()
		return
	var step := TOUR[_index]
	if _clock == 0.0:
		print("STEP %d tick %d %s" % [_index, _frame, step])
	var done := false
	_clock += delta
	match step["do"]:
		"wait":
			_hold(step["actions"])
			done = _clock >= float(step["seconds"])
		"tap":
			_hold([step["action"]])
			done = _clock >= 0.1
		"look":
			_hold(step["actions"])
			done = _turn(step["yaw"], step["pitch"], delta)
	if done:
		_index += 1
		_clock = 0.0


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _wait in 8:
		await get_tree().process_frame
	get_tree().quit()


# Turns the camera toward a heading and a pitch; true when it is there (or as far as it goes).
func _turn(yaw: float, pitch: float, delta: float) -> bool:
	var limits := _rig.pitch_limits()
	var wanted := clampf(pitch, limits.x, limits.y)
	var by_yaw := clampf(
		wrapf(yaw - _rig.yaw, -180.0, 180.0), -TURN_SPEED * delta, TURN_SPEED * delta
	)
	var by_pitch := clampf(wanted - _rig.pitch, -TURN_SPEED * delta, TURN_SPEED * delta)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
	return absf(wrapf(yaw - _rig.yaw, -180.0, 180.0)) < 1.0 and absf(wanted - _rig.pitch) < 1.0


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)
