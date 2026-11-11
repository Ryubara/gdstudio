## Plays hits on bodies in a low stance for a clip, from the player's own camera (gdstudio #1292):
## a crouched target, then a lying one, each takes several chest shots at four a second. The hit
## clip is made standing, so it plays on their upper body only and both stay down; before the fix
## each shot stood them up for the stun. The targets are `character_dressed.tscn` held in their
## stance by a controller that sends the crouch or prone bit; the player aims with the camera's
## `orbit()` and presses `aim` and `fire`, so every shot is a real one.
##
## `gds capture frames --project game --scene res://tools/capture/stance_hit_tour.tscn --seconds 14`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const DRESSED := "res://gameplay/character/character_dressed.tscn"
## A body lies down only with a prone tuning; the dressed body has none of its own.
const PRONE_TUNING := "res://gameplay/player/prone_tuning.tres"
const STAND := Vector3(-3.0, 0.0, 9.0)
const CROUCH_TARGET := Vector3(-2.6, 0.0, 12.2)
const PRONE_TARGET := Vector3(-5.0, 0.0, 12.4)
const TURN_SPEED := 160.0
const ON_TARGET := 0.4
## Seconds between shots (four a second).
const SHOT_GAP := 0.25

const TOUR: Array[Dictionary] = [
	{"do": "look", "target": "crouch"},
	{"do": "wait", "seconds": 0.6, "aim": true},
	{"do": "shoot", "target": "crouch", "shots": 4},
	{"do": "wait", "seconds": 1.0, "aim": true},
	{"do": "shoot", "target": "prone", "shots": 4},
	{"do": "wait", "seconds": 1.2, "aim": true},
]

var _index := 0
var _clock := 0.0
var _fired := 0
var _cooldown := 0.0
var _targets := {}
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


## Holds a body in a stance: the crouch or the prone bit on every tick, nothing else.
class Stance:
	extends CharacterController

	func _init(prone: bool) -> void:
		_command.crouch = not prone
		_command.prone = prone


func _ready() -> void:
	_player.teleport(STAND, 0.0)
	_targets["crouch"] = _add_target(CROUCH_TARGET, false)
	_targets["prone"] = _add_target(PRONE_TARGET, true)


func _add_target(spot: Vector3, prone: bool) -> Character:
	var body := (load(DRESSED) as PackedScene).instantiate() as Character
	_player.get_parent().add_child(body)
	body.teleport(spot, PI * 0.5)
	Health.of(body).max_value = 1000.0
	Health.of(body).value = 1000.0
	if prone:
		body.prone_tuning = load(PRONE_TUNING) as ProneTuning
	var stance := Stance.new(prone)
	body.add_child(stance)
	body.controller = stance
	return body


func _process(delta: float) -> void:
	if _index >= TOUR.size():
		_hold([])
		_finish()
		return
	var step := TOUR[_index]
	var done := false
	match step["do"]:
		"wait":
			_hold([&"aim"] if step["aim"] else [])
			_clock += delta
			done = _clock >= float(step["seconds"])
		"shoot":
			done = _shoot(step, delta)
		"look":
			_hold([&"aim"])
			done = _aim_at(_chest(_targets[step["target"]]), delta)
	if done:
		_index += 1
		_clock = 0.0
		_fired = 0


func _shoot(step: Dictionary, delta: float) -> bool:
	var on := _aim_at(_chest(_targets[step["target"]]), delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if on and _cooldown <= 0.0 and _player.aim_amount >= 0.99:
		_hold([&"aim", &"fire"])
		_fired += 1
		_cooldown = SHOT_GAP
	else:
		_hold([&"aim"])
	return _fired >= int(step["shots"]) and _cooldown <= 0.0


func _chest(target: Character) -> Vector3:
	var zones := target.get_node("HitZones") as HitZones
	zones.follow_bones()
	return zones.zone(&"chest").global_position


func _aim_at(point: Vector3, delta: float) -> bool:
	var camera := get_viewport().get_camera_3d()
	var middle := get_viewport().get_visible_rect().size / 2.0
	var now := camera.project_ray_normal(middle)
	var want := (point - camera.project_ray_origin(middle)).normalized()
	var yaw_error := rad_to_deg(wrapf(_yaw_of(want) - _yaw_of(now), -PI, PI))
	var pitch_error := -rad_to_deg(asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(now.y, -1.0, 1.0)))
	var most := TURN_SPEED * delta
	var turn_yaw := clampf(yaw_error * 0.5, -most, most)
	_rig.orbit(Vector2(-turn_yaw, clampf(pitch_error * 0.5, -most, most)))
	return absf(yaw_error) < ON_TARGET and absf(pitch_error) < ON_TARGET


func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


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
