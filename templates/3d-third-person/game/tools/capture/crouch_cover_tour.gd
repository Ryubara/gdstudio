## A body that walks to its cover, stops and crouches there, as an AI in cover does, seen from the
## player's own camera while the player shoots at its drawn chest (gdstudio #1412). Before the fix
## the crouch asked during the stop clip was undone on the same frame: the body stood drawn upright
## over its crouched capsule, and every shot at its chest flew over the capsule to the wall. Each
## shot prints `SHOT {json}` (hit or not, the zone) and each second `POSE {json}` (the body's state,
## the tree's state, the drawn head's height and the capsule's).
##
## `gds godot -- --path game --debug-collisions --write-movie <folder>/f.png --fixed-fps 60
## res://tools/capture/crouch_cover_tour.tscn` (60 frames a second, see `CROUCH_AFTER_TICKS`).
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const DRESSED := "res://gameplay/character/character_dressed.tscn"
const ENEMY_MODEL := "res://assets/characters/prototype/form_male.glb"
const STAND := Vector3(-3.0, 0.0, 9.0)
const TARGET_FROM := Vector3(-6.0, 0.0, 13.0)
const TURN_SPEED := 160.0
const ON_TARGET := 0.4
const SHOT_GAP := 0.4
## Seconds the target walks before it stops and crouches.
const WALK_SECONDS := 1.6
## Ticks between the stop and the crouch (the stop clip still plays then). Capture it at 60 frames
## a second: at 15 the body is still before a frame can start the stop clip.
const CROUCH_AFTER_TICKS := 12

var _target: Character
var _walker: Walker
var _clock := 0.0
var _cooldown := 0.0
var _fired := 0
var _hits := 0
var _held: Array[StringName] = []
var _last_pose := -1

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


## Walks along +x, then stops and, a few ticks later, crouches and stays down.
class Walker:
	extends CharacterController

	var walk_ticks := 0
	var crouch_after := 3
	var _tick := 0

	func _init(yaw: float) -> void:
		_command.yaw = yaw

	func sample() -> PlayerCommand:
		_tick += 1
		var walking := _tick <= walk_ticks
		_command.move = Vector2(0.0, 1.0) if walking else Vector2.ZERO
		_command.walk = walking
		_command.crouch = _tick > walk_ticks + crouch_after
		return _command


func _ready() -> void:
	Health.of(_player).invulnerable = true
	_player.teleport(STAND, 0.0)
	_target = (load(DRESSED) as PackedScene).instantiate() as Character
	(_target.get_node("Model") as CharacterModel).variant = load(ENEMY_MODEL) as PackedScene
	_player.get_parent().add_child(_target)
	_target.teleport(TARGET_FROM, PI * 0.5)
	Health.of(_target).max_value = 100000.0
	Health.of(_target).value = 100000.0
	_walker = Walker.new(PI * 0.5 + PI)
	_walker.walk_ticks = roundi(WALK_SECONDS * Engine.physics_ticks_per_second)
	_walker.crouch_after = CROUCH_AFTER_TICKS
	_target.add_child(_walker)
	_target.controller = _walker
	_target.hit_received.connect(_on_hit)


func _process(delta: float) -> void:
	_clock += delta
	_print_pose()
	var chest := _chest()
	var on := _aim_at(chest, delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	var crouched := _clock > WALK_SECONDS + 1.0
	if crouched and on and _cooldown <= 0.0 and _player.aim_amount >= 0.99 and _fired < 8:
		_hold([&"aim", &"fire"])
		_fired += 1
		_cooldown = SHOT_GAP
		_report_shot.call_deferred(_hits)
	else:
		_hold([&"aim"])
	if _fired >= 8 and _cooldown <= 0.0:
		_finish()


func _on_hit(_record: HitRecord) -> void:
	_hits += 1


# A shot's result two ticks after the trigger (a pistol round is fast at this range).
func _report_shot(hits_before: int) -> void:
	for _tick in 8:
		await get_tree().physics_frame
	var line := {"shot": _fired, "hit": _hits > hits_before}
	print("SHOT ", JSON.stringify(line))


func _print_pose() -> void:
	var second := floori(_clock)
	if second == _last_pose:
		return
	_last_pose = second
	var skeleton := (_target.get_node("Model") as CharacterModel).skeleton()
	var head := skeleton.get_bone_global_pose(skeleton.find_bone(&"Head")).origin
	var line := {
		"t": second,
		"state": Character.State.keys()[_target.state],
		"tree": String((_target.get_node("Animation") as CharacterAnimation).body_state()),
		"head": snappedf((skeleton.global_transform * head).y - _target.global_position.y, 0.01),
		"capsule": snappedf(CharacterCapsule.height(_target), 0.01),
	}
	print("POSE ", JSON.stringify(line))


func _chest() -> Vector3:
	var zones := _target.get_node("HitZones") as HitZones
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
	_hold([])
	print("CROUCH_COVER ", JSON.stringify({"shots": _fired, "hits": _hits}))
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
