## A body that crouches and stands up again, seen from the player's own camera while the player
## shoots at its drawn head as it rises (gdstudio #1431). Standing up, the pose is upright at once
## while the capsule grows over `crouch_time`: before the shot hull, a shot at the head in that
## time flew over the capsule to the wall; with it the head is hit. Each shot prints `SHOT {json}`
## (hit or not, the zone, the head's height over the capsule when the round arrived) and the end
## `STAND_UP {json}`.
##
## `gds godot -- --path game --debug-collisions --write-movie <folder>/f.png --fixed-fps 60
## res://tools/capture/stand_up_tour.tscn`. It lives in tools/, which the export leaves out, and
## nothing in the game refers to it.
extends Node

const DRESSED := "res://gameplay/character/character_dressed.tscn"
const ENEMY_MODEL := "res://assets/characters/prototype/form_male.glb"
const STAND := Vector3(-3.0, 0.0, 9.0)
const TARGET_AT := Vector3(-3.0, 0.0, 6.5)
const TURN_SPEED := 160.0
const ON_TARGET := 0.4
## Ticks of one round: crouched, then standing.
const CROUCHED_TICKS := 70
const STANDING_TICKS := 50
## Ticks after the body lets go of the crouch that the trigger is pulled: the pose is upright on
## the second (the aim point is on the head), and the round flies the 2.5 m at the pistol's 45 m/s
## in about three ticks, while the capsule is still growing.
const FIRE_AFTER_TICKS := 2
const ROUNDS := 6

var _target: Character
var _crouch: Crouch
var _tick := 0
var _fired := 0
var _hits := 0
var _zones: Array[String] = []
var _held: Array[StringName] = []
var _standing_head := Vector3.INF

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


## Crouches and stands in turn, facing the player.
class Crouch:
	extends CharacterController

	var down := false

	func _init(yaw: float) -> void:
		_command.yaw = yaw

	func sample() -> PlayerCommand:
		_command.move = Vector2.ZERO
		_command.crouch = down
		return _command


func _ready() -> void:
	Health.of(_player).invulnerable = true
	_player.teleport(STAND, 0.0)
	_target = (load(DRESSED) as PackedScene).instantiate() as Character
	(_target.get_node("Model") as CharacterModel).variant = load(ENEMY_MODEL) as PackedScene
	_player.get_parent().add_child(_target)
	_target.teleport(TARGET_AT, 0.0)
	Health.of(_target).max_value = 100000.0
	Health.of(_target).value = 100000.0
	_crouch = Crouch.new(0.0)
	_target.add_child(_crouch)
	_target.controller = _crouch
	_target.hit_received.connect(_on_hit)


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick < 40:
		return
	var round_tick := (_tick - 40) % (CROUCHED_TICKS + STANDING_TICKS)
	if _tick == 40:
		_standing_head = _head()
	_crouch.down = round_tick < CROUCHED_TICKS
	var fire := round_tick == CROUCHED_TICKS + FIRE_AFTER_TICKS and _fired < ROUNDS
	if fire and _player.aim_amount >= 0.99:
		_hold([&"aim", &"fire"])
		_fired += 1
		_report_shot.call_deferred(_hits)
	else:
		_hold([&"aim"])
	if _fired >= ROUNDS and round_tick == CROUCHED_TICKS + STANDING_TICKS - 1:
		_finish()


func _process(delta: float) -> void:
	if _standing_head.is_finite():
		_aim_at(_standing_head, delta)


func _on_hit(record: HitRecord) -> void:
	_hits += 1
	_zones.append(String(record.zone))


# A shot's result once the round has had time to arrive.
func _report_shot(hits_before: int) -> void:
	# The head over the capsule as the round arrives (three ticks at this range).
	var over := 0.0
	for wait in 12:
		await get_tree().physics_frame
		if wait == 3:
			over = _head().y - _target.global_position.y - CharacterCapsule.height(_target)
	var line := {
		"shot": _fired,
		"hit": _hits > hits_before,
		"zone": _zones[-1] if _hits > hits_before else "",
		"head_over_capsule": snappedf(over, 0.01),
	}
	print("SHOT ", JSON.stringify(line))


func _head() -> Vector3:
	var zones := _target.get_node("HitZones") as HitZones
	zones.follow_bones()
	return zones.zone(&"head").global_position


func _aim_at(point: Vector3, delta: float) -> void:
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
	set_physics_process(false)
	set_process(false)
	_hold([])
	print("STAND_UP ", JSON.stringify({"shots": _fired, "hits": _hits}))
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
