## Shows the poses an armed enemy takes in a fight, from the player's own camera (gdstudio #1345):
## a target that fires its pistol dry and reloads, and one that aims while the player shoots it in
## the chest at four a second (its hit clip and its flinch). The targets are
## `character_dressed.tscn` on the enemy's body (`form_male.glb`) with a controller that sends the
## aim (and the fire) bits; the player aims with the camera's `orbit()` and presses `aim` and
## `fire`, so every shot is a real one. Each frame it prints `HANDS {json}` when a target's gun
## hand rises over its head or its hands cross over the chest, read from the drawn skeleton.
##
## `gds capture frames --project game --scene res://tools/capture/enemy_pose_tour.tscn --seconds 12`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const DRESSED := "res://gameplay/character/character_dressed.tscn"
const ENEMY_MODEL := "res://assets/characters/prototype/form_male.glb"
const STAND := Vector3(-3.0, 0.0, 9.0)
const RELOAD_TARGET := Vector3(-5.6, 0.0, 12.0)
const HIT_TARGET := Vector3(-3.6, 0.0, 12.6)
const TURN_SPEED := 160.0
const ON_TARGET := 0.4
## Seconds between the player's shots (four a second).
const SHOT_GAP := 0.25
## Metres the gun hand may be over the head bone, and the left hand past the chest's middle.
const HAND_OVER_HEAD := 0.05
const HAND_CROSSED := 0.12

const TOUR: Array[Dictionary] = [
	{"do": "wait", "seconds": 1.0, "aim": false},
	{"do": "look", "target": "hit"},
	{"do": "wait", "seconds": 0.5, "aim": true},
	{"do": "shoot", "target": "hit", "shots": 6},
	{"do": "wait", "seconds": 1.5, "aim": true},
]

var _index := 0
var _clock := 0.0
var _fired := 0
var _cooldown := 0.0
var _targets := {}
var _held: Array[StringName] = []
var _odd := {}

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


## Aims at `yaw` on every tick and, with `shooting`, pulls the trigger every `gap` ticks.
class Aimer:
	extends CharacterController

	var shooting := false
	var gap := 12
	var _tick := 0

	func _init(yaw: float, fire: bool) -> void:
		_command.aim = true
		_command.yaw = yaw
		shooting = fire

	func sample() -> PlayerCommand:
		_tick += 1
		var pull := shooting and _tick % gap == 0
		_command.fire = pull
		_command.fire_pressed = pull
		return _command


func _ready() -> void:
	Health.of(_player).invulnerable = true
	_player.teleport(STAND, 0.0)
	_targets["reload"] = _add_target(RELOAD_TARGET, true)
	_targets["hit"] = _add_target(HIT_TARGET, false)


func _add_target(spot: Vector3, fire: bool) -> Character:
	var body := (load(DRESSED) as PackedScene).instantiate() as Character
	(body.get_node("Model") as CharacterModel).variant = load(ENEMY_MODEL) as PackedScene
	_player.get_parent().add_child(body)
	# Facing across the player's view, a little towards it: the arms read from the side.
	var yaw := PI * 0.5 if fire else -PI * 0.75
	body.teleport(spot, yaw)
	Health.of(body).max_value = 1000.0
	Health.of(body).value = 1000.0
	var aimer := Aimer.new(yaw + PI, fire)
	body.add_child(aimer)
	body.controller = aimer
	var skeleton := (body.get_node("Model") as CharacterModel).skeleton()
	skeleton.skeleton_updated.connect(_watch_hands.bind(body, skeleton))
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


# The drawn pose (after every modifier): a gun hand over the head or crossed hands, once a time.
func _watch_hands(body: Character, skeleton: Skeleton3D) -> void:
	var bones := {}
	for bone: StringName in [&"head", &"hand_r", &"hand_l", &"spine_03"]:
		var index := skeleton.find_bone(bone)
		if index < 0:
			return
		bones[bone] = (
			body.global_transform.affine_inverse()
			* (skeleton.global_transform * skeleton.get_bone_global_pose(index).origin)
		)
	var found := PackedStringArray()
	if bones[&"hand_r"].y > bones[&"head"].y + HAND_OVER_HEAD:
		found.append("gun_hand_up")
	# The body faces +z: its left is +x.
	var middle: float = bones[&"spine_03"].x
	if bones[&"hand_l"].x < middle - HAND_CROSSED and bones[&"hand_r"].x > middle + HAND_CROSSED:
		found.append("crossed")
	var odd := ",".join(found)
	if _odd.get(body, "") == odd:
		return
	_odd[body] = odd
	var animation := body.get_node("Animation") as CharacterAnimation
	var line := {
		"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01),
		"who": "reload" if body == _targets.get("reload") else "hit",
		"odd": odd,
		"acting": animation.is_acting(),
		"action": String(animation.last_action()),
		"reloading": animation.is_reloading(),
	}
	print("HANDS ", JSON.stringify(line))


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
