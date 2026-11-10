## Plays prone and the crawl the way a player would, for a clip: the character lies down, crawls
## under a slab only a lying body fits under (the tour puts it in the open, 0.8 m up), is refused
## when it tries to get up there, crawls out and gets up through crouch, then lies down again to
## aim and shoot. It presses the input actions (never moves the body itself) and turns the camera
## with the same `orbit()` the mouse, the stick and the touch layer use.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/prone_tour.tscn --seconds 20`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Camera turn speed toward a heading, in degrees a second.
const TURN_SPEED := 120.0
## Where the tour starts (open ground on the east side of the map), and where the slab is.
const START := Vector3(5.5, 0.0, 8.0)
const GAP_CENTRE := Vector3(5.5, 0.0, 3.0)
## The slab's underside, metres: under the crouched capsule (1.1 m), over the lying one (0.6 m).
const GAP_HEIGHT := 0.8

## The tour: `wait` holds `actions` for `seconds`; `tap` presses one action for a moment; `crawl`
## pushes forward until the body is past `z` (or `seconds` run out); `look` turns the camera.
const TOUR: Array[Dictionary] = [
	{"do": "look", "yaw": 0.0, "pitch": 5.0},
	{"do": "wait", "actions": [], "seconds": 0.6},
	{"do": "tap", "action": &"prone"},
	{"do": "wait", "actions": [], "seconds": 0.9},
	{"do": "crawl", "z": 3.0, "seconds": 8.0},
	{"do": "tap", "action": &"prone"},
	{"do": "wait", "actions": [], "seconds": 1.2},
	{"do": "crawl", "z": 0.6, "seconds": 6.0},
	{"do": "wait", "actions": [], "seconds": 1.4},
	{"do": "look", "yaw": 25.0, "pitch": 6.0},
	{"do": "tap", "action": &"prone"},
	{"do": "wait", "actions": [], "seconds": 0.8},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.8},
	{"do": "wait", "actions": [&"aim", &"fire"], "seconds": 0.15},
	{"do": "wait", "actions": [&"aim"], "seconds": 0.8},
	{"do": "wait", "actions": [], "seconds": 0.3},
	{"do": "tap", "action": &"prone"},
	{"do": "wait", "actions": [], "seconds": 1.4},
]

var _index := 0
var _clock := 0.0
var _held: Array[StringName] = []
var _started := false

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_add_slab()


func _physics_process(delta: float) -> void:
	if not _started:
		_started = true
		_player.teleport(START, PI)
		return
	if _index >= TOUR.size():
		_hold([])
		_finish()
		return
	var step := TOUR[_index]
	var done := false
	_clock += delta
	match step["do"]:
		"wait":
			_hold(step["actions"])
			done = _clock >= float(step["seconds"])
		"tap":
			_hold([step["action"]])
			done = _clock >= 0.1
		"crawl":
			_hold([&"move_forward"])
			done = _player.global_position.z < float(step["z"]) or _clock > float(step["seconds"])
		"look":
			_hold([])
			done = _turn(step["yaw"], step["pitch"], delta)
	if done:
		_index += 1
		_clock = 0.0


# A slab on two posts across the way, its underside `GAP_HEIGHT` up, solid to the character.
func _add_slab() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.45, 0.2)
	var parts := [
		[Vector3(3.0, 0.3, 2.4), Vector3(0.0, GAP_HEIGHT + 0.15, 0.0)],
		[Vector3(0.3, GAP_HEIGHT, 2.4), Vector3(-1.35, GAP_HEIGHT / 2.0, 0.0)],
		[Vector3(0.3, GAP_HEIGHT, 2.4), Vector3(1.35, GAP_HEIGHT / 2.0, 0.0)],
	]
	var slab := StaticBody3D.new()
	slab.name = "ProneSlab"
	slab.collision_layer = PhysicsLayers.WORLD
	for part: Array in parts:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = part[0]
		shape.shape = box
		shape.position = part[1]
		slab.add_child(shape)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = part[0]
		cube.material = material
		mesh.mesh = cube
		mesh.position = part[1]
		slab.add_child(mesh)
	slab.position = GAP_CENTRE
	add_child(slab)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Turns the camera toward a heading and a pitch; true when it is there.
func _turn(yaw: float, pitch: float, delta: float) -> bool:
	var by_yaw := clampf(
		wrapf(yaw - _rig.yaw, -180.0, 180.0), -TURN_SPEED * delta, TURN_SPEED * delta
	)
	var by_pitch := clampf(pitch - _rig.pitch, -TURN_SPEED * delta, TURN_SPEED * delta)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
	return absf(wrapf(yaw - _rig.yaw, -180.0, 180.0)) < 1.0 and absf(pitch - _rig.pitch) < 1.0


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)
