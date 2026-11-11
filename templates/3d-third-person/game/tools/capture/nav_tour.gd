## Films the AI navigator on the proof course with its debug drawing on (the path, the point it
## steers to, and the stuck rung or the refusal over the head), in three shots:
##
## 1. From above, over the pathing section: one character walks the Across route (from the doorway
##    to the far corner) and two others the ramp and the gap with its link.
## 2. From the player's camera: eight characters cross the doorway with the door that opens for
##    them, through the two moving obstacles.
## 3. From the player's camera: a character meets a block that is not in the navigation mesh and
##    climbs the stuck ladder (a sidestep) round it.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/nav_tour.tscn --seconds 26`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const CHARACTER := "res://gameplay/ai/ai_character.tscn"
## The pathing section's origin in the world (`world/world.tscn`).
const SECTION := Vector3(25.0, 0.0, -6.0)
## Seconds into the clip each shot starts, and the end.
const CROWD_AT := 9.0
const STUCK_AT := 17.0
const END := 25.5
## The top camera: over the section's middle, the width it shows (metres).
const ABOVE := Vector3(45.0, 60.0, -6.0)
const ABOVE_SIZE := 46.0
## Where the player stands and looks (degrees) for the crowd and the stuck shots.
const CROWD_STAND := Vector3(31.0, 0.0, -6.5)
const CROWD_YAW := -28.0
const STUCK_STAND := Vector3(32.0, 0.0, 13.0)
const STUCK_YAW := -61.0
## Camera pitch, degrees, while filming from the player.
const PITCH := -14.0

var _clock := 0.0
var _walkers: Array[AiCharacter] = []
var _above: Camera3D
var _yaw := 0.0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _world: Node = $Main/World


func _ready() -> void:
	_above = Camera3D.new()
	_above.projection = Camera3D.PROJECTION_ORTHOGONAL
	_above.size = ABOVE_SIZE
	_above.position = ABOVE
	_above.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(_above)
	_above.make_current()
	_player.teleport(Vector3(-8.0, 0.0, 10.0), PI)
	_shot_above.call_deferred()


func _physics_process(delta: float) -> void:
	var was := _clock
	_clock += delta
	if _clock >= CROWD_AT:
		_face()
	if _crossed(was, CROWD_AT):
		_shot_crowd()
	if _crossed(was, STUCK_AT):
		_shot_stuck()
	if _crossed(was, END):
		_finish()


func _shot_above() -> void:
	await get_tree().create_timer(0.5).timeout
	for route: String in ["Across", "Ramp", "Gap"]:
		var start := _marker(route, "Start")
		var walker := _walker(start)
		(walker.navigator as AiNavigator).go_to(_marker(route, "End"))


func _shot_crowd() -> void:
	_clear()
	_above.clear_current()
	_player.teleport(CROWD_STAND, deg_to_rad(CROWD_YAW) + PI)
	_yaw = CROWD_YAW
	var goal := _marker("Door", "End")
	for index in 8:
		var row := float(index / 4)
		var column := float(index % 4)
		var spot := SECTION + Vector3(4.0 + row * 1.4, 0.0, -13.0 + column * 1.3)
		var walker := _walker(spot)
		var offset := Vector3(row * 1.2, 0.0, (column - 1.5) * 1.2)
		var navigator := walker.navigator as AiNavigator
		navigator.avoidance = AiNavAvoidance.Mode.SEPARATION
		navigator.go_to(goal + offset, 0.6)


func _shot_stuck() -> void:
	_clear()
	_player.teleport(STUCK_STAND, deg_to_rad(STUCK_YAW) + PI)
	_yaw = STUCK_YAW
	var block := RigidBody3D.new()
	block.freeze = true
	block.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.6, 1.4)
	shape.shape = box
	block.add_child(shape)
	var look := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	look.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.45, 0.15)
	look.material_override = paint
	block.add_child(look)
	block.position = Vector3(37.5, 0.8, 10.0)
	_world.add_child(block)
	var walker := _walker(Vector3(33.5, 0.0, 10.0))
	(walker.navigator as AiNavigator).go_to(Vector3(45.0, 0.0, 10.0), 0.7)


func _walker(spot: Vector3) -> AiCharacter:
	var walker := (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	walker.debug = true
	_world.add_child(walker)
	walker.teleport(spot + Vector3.UP * 0.05, PI / 2.0)
	(walker.navigator as AiNavigator).debug = true
	_walkers.append(walker)
	return walker


func _clear() -> void:
	for walker in _walkers:
		walker.queue_free()
	_walkers.clear()


func _marker(route: String, end: String) -> Vector3:
	var path := "PathingSection/Routes/%s/%s" % [route, end]
	return (_world.get_node(path) as Node3D).global_position


func _crossed(was: float, at: float) -> bool:
	return was < at and _clock >= at


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds the player's camera at the shot's heading and pitch, a few degrees a frame.
func _face() -> void:
	var by_yaw := clampf(wrapf(_yaw - _rig.yaw, -180.0, 180.0), -6.0, 6.0)
	var by_pitch := clampf(PITCH - _rig.pitch, -2.0, 2.0)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
