## Fires the pistol down at a crouched character from the player's own camera, for a clip of the
## shot's kick (kit #1280): the target crouches close ahead, the player turns the crosshair onto
## its chest with the camera's `orbit()` (what the mouse does), holds `aim` and taps `fire` at the
## pistol's fire rate, keeping the crosshair on the chest between shots. With the shot's clip added
## to the aim (`WeaponDef.shoot_additive`), each shot kicks the gun up a little from the target;
## with it replacing the aim, each shot swung the gun up past level.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/shot_kick_tour.tscn --seconds 7`
## `SHOT_REPLACE=1` plays the shot over the aim instead (the pistol as it was), for the before.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const DRESSED := "res://gameplay/character/character_dressed.tscn"
## Where the player stands (an open stretch of the map), facing +Z.
const STAND := Vector3(-3.0, 0.0, 4.0)
## How far ahead the target crouches, in metres.
const TARGET_DISTANCE := 2.2
## Seconds to settle before the first shot, the shots, and the gaps between taps.
const SETTLE := 1.5
const SHOTS := 8
const TAP_GAP := 0.26
## Camera turn speed, degrees a second.
const TURN_SPEED := 160.0

var _clock := 0.0
var _fired := 0
var _next_tap := 0.0
var _target: Character
var _crouch: ScriptedController
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	if OS.get_environment("SHOT_REPLACE") == "1":
		# The shared definition itself: a copy set on the weapon would be a weapon switch.
		_player.weapon.definition.shoot_additive = false
	_player.teleport(STAND, 0.0)
	_target = (load(DRESSED) as PackedScene).instantiate() as Character
	_player.get_parent().add_child(_target)
	_crouch = ScriptedController.new()
	_target.add_child(_crouch)
	_target.controller = _crouch
	_crouch.next.crouch = true
	Health.of(_target).max_value = 100000.0
	Health.of(_target).value = 100000.0
	_target.teleport(STAND + Vector3(0.0, 0.0, TARGET_DISTANCE), PI)
	# The hit clip is a standing one, which stands a crouched target up for the stun time (kit
	# #1292); the crouch idle in its place keeps the target where the gun points.
	(_target.get_node("Animation") as CharacterAnimation).hit_clip = CharacterClips.CROUCH_IDLE


func _process(delta: float) -> void:
	_clock += delta
	_player.weapon.make_ready()
	var zones := _target.get_node("HitZones") as HitZones
	zones.follow_bones()
	_aim_at(zones.zone(&"chest").global_position, delta)
	if _clock < SETTLE or _fired >= SHOTS:
		_hold([&"aim"] if _fired < SHOTS or _clock < _next_tap + 1.5 else [])
		if _fired >= SHOTS and _clock > _next_tap + 2.0:
			get_tree().quit()
		return
	if _clock >= _next_tap:
		_hold([&"aim", &"fire"])
		_fired += 1
		_next_tap = _clock + TAP_GAP
	else:
		_hold([&"aim"])


# Turns the camera so the crosshair's ray points at `point`, half the error a frame (the camera's
# follow lags a little, and a full turn overshoots).
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


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)
