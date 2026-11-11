## Plays the hit and interact components for a clip, from the player's own camera: two range
## targets dropped by real shots through their `Health` (one takes two), then a lever that is a
## plain `Node3D` with an `Interactable` child and no script of its own, pulled with the interact
## button. The player aims with the camera's `orbit()` (what the mouse does) and presses the
## actions, so every shot and every use is a real one.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/components_tour.tscn --seconds 14`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const TARGET := "res://gameplay/target/target.tscn"
## Where the player stands, the two targets and the lever (an open stretch of the map).
const STAND := Vector3(-3.0, 0.0, 9.0)
const NEAR_TARGET := Vector3(-4.4, 0.0, 15.0)
const FAR_TARGET := Vector3(-1.6, 0.0, 15.0)
const LEVER := Vector3(-3.0, 0.0, 10.0)
## Camera turn speed, degrees a second, and how near the crosshair must be before a shot.
const TURN_SPEED := 160.0
const ON_TARGET := 0.3

## Each step: `shoot` a target `shots` times, `look` at the lever, `use` it, or `wait`.
const TOUR: Array[Dictionary] = [
	{"do": "wait", "seconds": 1.0},
	{"do": "shoot", "target": "near", "shots": 1},
	{"do": "wait", "seconds": 1.0},
	{"do": "shoot", "target": "far", "shots": 2},
	{"do": "wait", "seconds": 1.5},
	{"do": "look", "seconds": 2.0},
	{"do": "use"},
	{"do": "wait", "seconds": 2.5},
]

var _index := 0
var _clock := 0.0
var _fired := 0
var _cooldown := 0.0
var _targets := {}
var _held: Array[StringName] = []
var _handle: MeshInstance3D

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_player.teleport(STAND, 0.0)
	_targets["near"] = _add_target(NEAR_TARGET)
	_targets["far"] = _add_target(FAR_TARGET)
	Health.of(_targets["far"]).max_value = 60.0
	Health.of(_targets["far"]).reset()
	_add_lever()


func _add_target(spot: Vector3) -> Target:
	var board := (load(TARGET) as PackedScene).instantiate() as Target
	board.position = spot
	board.rotation.y = PI
	board.reset_time = 0.0
	_player.get_parent().add_child(board)
	return board


# A lever as a person would build it in the editor: a `Node3D` holding a post, a handle and an
# `Interactable` with a shape. The tour, not a script on the lever, answers its signal.
func _add_lever() -> void:
	var lever := Node3D.new()
	lever.name = "Lever"
	lever.position = LEVER
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.3, 1.0, 0.3)
	post.mesh = post_mesh
	post.position.y = 0.5
	lever.add_child(post)
	_handle = MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.08, 0.6, 0.08)
	_handle.mesh = handle_mesh
	_handle.position = Vector3(0.0, 1.0, 0.0)
	_handle.rotation.x = deg_to_rad(-40.0)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.9, 0.2, 0.15)
	_handle.material_override = paint
	lever.add_child(_handle)
	var usable := Interactable.new()
	usable.prompt = "Pull"
	usable.position.y = 1.0
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	usable.add_child(shape)
	lever.add_child(usable)
	usable.interacted.connect(_on_lever_pulled)
	_player.get_parent().add_child(lever)


func _on_lever_pulled(_by: Node3D) -> void:
	_handle.rotation.x = deg_to_rad(40.0)
	(_handle.material_override as StandardMaterial3D).albedo_color = Color(0.2, 0.85, 0.3)


# Each drawn frame, not each physics tick: the crosshair is read from the camera, which moves
# once a frame.
func _process(delta: float) -> void:
	if _index >= TOUR.size():
		_hold([])
		_finish()
		return
	var step := TOUR[_index]
	var done := false
	match step["do"]:
		"wait":
			_hold([])
			_clock += delta
			done = _clock >= float(step["seconds"])
		"shoot":
			done = _shoot(step, delta)
		"look":
			_hold([])
			_aim_at(LEVER + Vector3(0.0, 0.6, 0.0), delta)
			_clock += delta
			done = _clock >= float(step["seconds"])
		"use":
			_hold([&"interact"])
			done = true
	if done:
		_index += 1
		_clock = 0.0
		_fired = 0


# Turns the crosshair onto the target's board and fires its shots, one each time the weapon is
# ready and the crosshair is on; true when the last has left.
func _shoot(step: Dictionary, delta: float) -> bool:
	var target := _targets[step["target"]] as Target
	var board := target.get_node("%Board") as Node3D
	var on := _aim_at(board.global_position, delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if on and _cooldown <= 0.0 and _player.aim_amount >= 0.99:
		_hold([&"aim", &"fire"])
		_fired += 1
		_cooldown = 0.45
	else:
		_hold([&"aim"])
	return _fired >= int(step["shots"]) and _cooldown < 0.4


# Turns the camera so the crosshair's ray points at `point`; true when it is within `ON_TARGET`
# degrees.
func _aim_at(point: Vector3, delta: float) -> bool:
	var camera := get_viewport().get_camera_3d()
	var middle := get_viewport().get_visible_rect().size / 2.0
	var now := camera.project_ray_normal(middle)
	var want := (point - camera.project_ray_origin(middle)).normalized()
	var yaw_error := rad_to_deg(wrapf(_yaw_of(want) - _yaw_of(now), -PI, PI))
	var pitch_error := -rad_to_deg(asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(now.y, -1.0, 1.0)))
	var most := TURN_SPEED * delta
	_rig.orbit(
		Vector2(-clampf(yaw_error * 0.5, -most, most), clampf(pitch_error * 0.5, -most, most))
	)
	return absf(yaw_error) < ON_TARGET and absf(pitch_error) < ON_TARGET


func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)


func _finish() -> void:
	set_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
