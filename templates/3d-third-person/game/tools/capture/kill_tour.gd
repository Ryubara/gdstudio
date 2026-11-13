## Films kills from the player's own camera (gdstudio #1343): four far grunts (the director's
## Reduced tier) run at the player, are hit once and then killed by a rifle round on four
## consecutive ticks, one on each tick of the director's step cycle; then a near grunt is killed by
## a pistol round on the chest and another by a rifle round on the forearm. Before the fix one of
## the four far bodies left at four times its run's speed and the forearm kill flung the arm.
##
## The hits are the weapons' own records (`HitRecord.shot` with the definition's damage and
## impulse) given along the line from the player, so each kill lands on the tick it is meant to.
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/kill_tour.tscn --seconds 7`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const CHARACTER := "res://gameplay/ai/ai_character.tscn"
const PISTOL := "res://gameplay/weapon/pistol.tres"
const RIFLE := "res://gameplay/weapon/rifle.tres"
## A flat floor built high above the map (a long clear view, nothing to walk into).
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
## Where the player stands, looking along -Z.
const STAND := Vector3(0.0, 300.05, 32.0)
## The far grunts' row, 32 m out, and the near grunts' spots.
const FAR_Z := 0.0
const FAR_X: Array[float] = [-3.75, -1.25, 1.25, 3.75]
const NEAR: Array[Vector3] = [Vector3(-3.5, 300.05, 27.0), Vector3(3.5, 300.05, 27.0)]
## Seconds into the clip of each beat.
const FAR_HIT := 1.0
const FAR_KILL := 1.6
const PISTOL_KILL := 4.0
const RIFLE_KILL := 4.8
const END := 7.0
## The camera's pitch (degrees) and its field of view while filming the far row, then the near.
const PITCH := 2.0
const FAR_FOV := 28.0
const NEAR_FOV := 60.0

var _clock := 0.0
var _tick := 0
var _kill_tick := -1
var _far: Array[AiCharacter] = []
var _near: Array[AiCharacter] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 80.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_player.teleport(STAND, PI)
	Health.of(_player).invulnerable = true
	for x in FAR_X:
		_far.append(_add(Vector3(x, FLOOR_AT.y + 0.05, FAR_Z)))
	for spot in NEAR:
		_near.append(_add(spot))


func _add(spot: Vector3) -> AiCharacter:
	var character := (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	_player.get_parent().add_child(character)
	character.teleport(spot, 0.0)
	character.ragdoll_body.max_active = 8
	return character


func _physics_process(delta: float) -> void:
	var was := _clock
	_clock += delta
	_tick += 1
	_face()
	for grunt in _far:
		if not grunt.is_dead() and _clock < FAR_KILL + 0.2:
			grunt.ai_controller().walk_direction = Vector3.BACK
			grunt.ai_controller().walk_strength = 1.0
	if _crossed(was, FAR_HIT):
		for grunt in _far:
			_shoot(grunt, RIFLE, &"spine_03", 10.0)
	if _crossed(was, FAR_KILL):
		_kill_tick = _tick
	if _kill_tick >= 0 and _tick - _kill_tick < _far.size():
		_shoot(_far[_tick - _kill_tick], RIFLE, &"spine_03", 500.0)
	if _crossed(was, PISTOL_KILL):
		_shoot(_near[0], PISTOL, &"spine_03", 500.0)
	if _crossed(was, RIFLE_KILL):
		_shoot(_near[1], RIFLE, &"lowerarm_l", 500.0)
	if _crossed(was, END):
		_finish()


# Gives `grunt` the record a round of the weapon at `path` makes on `bone`, from the player's eye,
# with `damage` in place of the weapon's (10 wounds, 500 kills).
func _shoot(grunt: AiCharacter, path: String, bone: StringName, damage: float) -> void:
	var weapon := load(path) as WeaponDef
	var skeleton := grunt.model.skeleton() if grunt.model != null else null
	var point := grunt.global_position + Vector3.UP * 1.3
	if skeleton != null:
		point = (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
		)
	var eye := _player.global_position + Vector3.UP * 1.5
	var along := (point - eye).normalized()
	grunt.take_hit(HitRecord.shot(damage, &"", bone, point, along, weapon.impulse, _player))


func _crossed(was: float, at: float) -> bool:
	return was < at and _clock >= at


# Holds the camera along -Z at a small pitch, a few degrees a frame, zoomed on the far row first.
func _face() -> void:
	var by_yaw := clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0)
	var by_pitch := clampf(PITCH - _rig.pitch, -2.0, 2.0)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		camera.fov = FAR_FOV if _clock < PISTOL_KILL - 0.6 else NEAR_FOV


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
