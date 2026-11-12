## Plays the hit zones for a clip, from the player's own camera: a headshot that kills (the head
## snaps back and the body falls along the shot), a body shot that kills on the third hit, two
## hits that do not kill on a target walking past (it flinches and walks on), then shots into the
## body lying on the ground. The targets are `character_dressed.tscn` (the body with its model,
## no input); the player aims with the camera's `orbit()` (what the mouse does) until the
## crosshair is on the part and presses `aim` and `fire`, so every shot is a real one.
##
## Record it with Movie Maker through the kit, once for each mannequin (`HIT_MODEL=male` puts the
## male on the targets; the female is the default):
## `gds capture frames --project game --scene res://tools/capture/hit_tour.tscn --seconds 30`
## `HIT_HITSCAN=1` fires the pistol hitscan (a copy of its definition with `WeaponDef.hitscan` on,
## gdstudio #1252): the same shots with no round in the air, the impact at once.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const DRESSED := "res://gameplay/character/character_dressed.tscn"
const MALE := "res://assets/characters/mannequin/mannequin_male.glb"
## Where the player stands, and where the targets stand and walk (an open stretch of the map).
const STAND := Vector3(-3.0, 0.0, 9.0)
const HEAD_TARGET := Vector3(-4.6, 0.0, 15.5)
const BODY_TARGET := Vector3(-1.4, 0.0, 15.5)
const WALK_FROM := Vector3(-7.5, 0.0, 17.5)
const WALK_TO := Vector3(1.5, 0.0, 17.5)
## Camera turn speed, degrees a second, and how near the crosshair must be before a shot.
const TURN_SPEED := 160.0
const ON_TARGET := 0.25

## Each step: `aim` at a target's `zone` (or, lying, its ragdoll `bone`) then shoot it `shots`
## times, or `wait` `seconds` with the aim held or not.
const TOUR: Array[Dictionary] = [
	{"do": "wait", "seconds": 1.0, "aim": false},
	{"do": "shoot", "target": "head", "zone": &"head", "shots": 1},
	{"do": "wait", "seconds": 2.2, "aim": true},
	{"do": "shoot", "target": "body", "zone": &"chest", "shots": 3},
	{"do": "wait", "seconds": 2.0, "aim": true},
	{"do": "walk"},
	{"do": "wait", "seconds": 0.8, "aim": true},
	{"do": "shoot", "target": "walker", "zone": &"chest", "shots": 1},
	{"do": "wait", "seconds": 0.7, "aim": true},
	{"do": "shoot", "target": "walker", "zone": &"arm_l", "shots": 1},
	{"do": "wait", "seconds": 1.0, "aim": true},
	{"do": "shoot", "target": "head", "bone": &"spine_03", "shots": 1},
	{"do": "wait", "seconds": 0.6, "aim": true},
	{"do": "shoot", "target": "head", "bone": &"thigh_l", "shots": 1},
	{"do": "wait", "seconds": 0.6, "aim": true},
	{"do": "shoot", "target": "head", "bone": &"Head", "shots": 1},
	{"do": "wait", "seconds": 1.5, "aim": true},
]

var _index := 0
var _clock := 0.0
var _fired := 0
var _cooldown := 0.0
var _targets := {}
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	if OS.get_environment("HIT_HITSCAN") == "1":
		var pistol := _player.loadout.slots[0].duplicate() as WeaponDef
		pistol.hitscan = true
		_player.loadout.slots[0] = pistol
		_player.weapon.definition = pistol
	_player.teleport(STAND, 0.0)
	_targets["head"] = _add_target(HEAD_TARGET)
	_targets["body"] = _add_target(BODY_TARGET)
	_targets["walker"] = _add_target(WALK_FROM)
	Health.of(_targets["walker"]).max_value = 1000.0
	Health.of(_targets["walker"]).value = 1000.0


func _add_target(spot: Vector3) -> Character:
	var body := (load(DRESSED) as PackedScene).instantiate() as Character
	if OS.get_environment("HIT_MODEL") == "male":
		var slot := body.get_node("Model")
		var old := slot.get_node("Mannequin")
		slot.remove_child(old)
		old.free()
		slot.add_child((load(MALE) as PackedScene).instantiate())
	_player.get_parent().add_child(body)
	body.teleport(spot, PI)
	return body


# Each drawn frame, not each physics tick: the crosshair is read from the camera, which moves
# once a frame (at a capture's 10 frames a second six ticks would turn it six times too far).
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
		"walk":
			var walker := _targets["walker"] as Character
			var route := RouteController.new()
			route.points = PackedVector3Array([WALK_TO])
			walker.add_child(route)
			walker.controller = route
			done = true
		"shoot":
			done = _shoot(step, delta)
	if done:
		_index += 1
		_clock = 0.0
		_fired = 0


# Turns the crosshair onto the step's part and fires its shots, one each time the weapon is
# ready and the crosshair is on; true when the last has left.
func _shoot(step: Dictionary, delta: float) -> bool:
	var target := _targets[step["target"]] as Character
	var point := _point_of(target, step)
	var on := _aim_at(point, delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if on and _cooldown <= 0.0 and _player.aim_amount >= 0.99:
		_hold([&"aim", &"fire"])
		_fired += 1
		_cooldown = 0.45
	else:
		_hold([&"aim"])
	return _fired >= int(step["shots"]) and _cooldown < 0.4


func _point_of(target: Character, step: Dictionary) -> Vector3:
	if step.has("bone"):
		var bone := target.ragdoll_body.body(step["bone"])
		return bone.global_position if bone != null else target.global_position
	var zones := target.get_node("HitZones") as HitZones
	zones.follow_bones()
	return zones.zone(step["zone"]).global_position


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
