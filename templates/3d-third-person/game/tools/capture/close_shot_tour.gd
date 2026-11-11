## Plays close shots for a clip, from the player's own camera (gdstudio #1251): a character 2 m
## ahead, standing, shot with the crosshair on the right edge of its head, then just to the left
## of its head (the shot goes on to the wall behind, under the crosshair), then crouched 3 m
## ahead and shot on the right edge of its head again. The target is `character_dressed.tscn`
## with health enough for every shot; the player aims with the camera's `orbit()` (what the mouse
## does) until the crosshair is on the point and presses `aim` and `fire`, so every shot is a
## real one. Before the fix the shots on the head's edge flew past it, up and to the right.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/close_shot_tour.tscn --seconds 14`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const DRESSED := "res://gameplay/character/character_dressed.tscn"
## Where the player stands (an open stretch of the map), facing +Z.
const STAND := Vector3(-3.0, 0.0, 9.0)
## Camera turn speed, degrees a second, and how near the crosshair must be before a shot.
const TURN_SPEED := 160.0
const ON_TARGET := 0.15

## Each step: `place` the target `distance` m ahead (`crouched` or not), `shoot` with the
## crosshair at the head's middle moved `right` m across the view, `shots` times, or `wait`.
const TOUR: Array[Dictionary] = [
	{"do": "place", "distance": 2.0, "crouched": false},
	{"do": "wait", "seconds": 1.0},
	{"do": "shoot", "right": 0.08, "shots": 3},
	{"do": "wait", "seconds": 0.6},
	{"do": "shoot", "right": -0.2, "shots": 2},
	{"do": "wait", "seconds": 0.6},
	{"do": "place", "distance": 3.0, "crouched": true},
	{"do": "wait", "seconds": 1.2},
	{"do": "shoot", "right": 0.08, "shots": 3},
	{"do": "wait", "seconds": 1.2},
]

var _index := 0
var _clock := 0.0
var _fired := 0
var _cooldown := 0.0
var _target: Character
var _crouch: ScriptedController
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_player.teleport(STAND, 0.0)
	_target = (load(DRESSED) as PackedScene).instantiate() as Character
	_player.get_parent().add_child(_target)
	_crouch = ScriptedController.new()
	_target.add_child(_crouch)
	_target.controller = _crouch
	Health.of(_target).max_value = 100000.0
	Health.of(_target).value = 100000.0
	# A wall behind the target, so a shot that passes it leaves its mark.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 4.0, 0.3)
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var look := BoxMesh.new()
	look.size = box.size
	var paint := StandardMaterial3D.new()
	# Dark, so the marks and the impacts' puffs read on it.
	paint.albedo_color = Color(0.18, 0.19, 0.22)
	look.material = paint
	mesh.mesh = look
	wall.add_child(mesh)
	wall.position = STAND + Vector3(0.0, 2.0, 6.0)
	_player.get_parent().add_child(wall)


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
		"place":
			_target.teleport(STAND + Vector3(0.0, 0.0, float(step["distance"])), PI)
			_crouch.next.crouch = step["crouched"]
			done = true
		"wait":
			_hold([&"aim"])
			_clock += delta
			done = _clock >= float(step["seconds"])
		"shoot":
			done = _shoot(step, delta)
	if done:
		_index += 1
		_clock = 0.0
		_fired = 0


# Turns the crosshair onto the step's point and fires its shots, one each time the weapon is
# ready and the crosshair is on; true when the last has left.
func _shoot(step: Dictionary, delta: float) -> bool:
	var zones := _target.get_node("HitZones") as HitZones
	zones.follow_bones()
	var camera := get_viewport().get_camera_3d()
	var point: Vector3 = (
		zones.zone(&"head").global_position + camera.global_basis.x * float(step["right"])
	)
	var on := _aim_at(point, delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if on and _cooldown <= 0.0 and _player.aim_amount >= 0.99:
		_hold([&"aim", &"fire"])
		_fired += 1
		_cooldown = 0.6
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
	# Half the error a frame: the camera's follow lags a little, and a full turn overshoots.
	var turn_yaw := clampf(yaw_error * 0.5, -most, most)
	_rig.orbit(Vector2(-turn_yaw, clampf(pitch_error * 0.5, -most, most)))
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
