## Films the AI reactions (kit #968) from the player's own camera, with each character's debug
## overlay on (the situation, the play state and the last event with its answer above the head,
## and the task layers above that), in three shots in the empty middle room of the pathing
## section:
##
## 1. A guard walks its patrol between two stops; an intruder (a body of the player's faction)
##    walks in, the guard notices it and fights (Engaged, `engage`), the intruder slips out through
##    the doorway, the guard chases (`chase`), searches round the place (`search`) and goes back to
##    its patrol.
## 2. A hurt guard (Careful) sees the intruder, runs to a cover spot beside a box, crouches and
##    peeks to shoot (`cover`: to, hide, peek).
## 3. A civilian with some courage sees a grunt at arm's reach and flees (Fleeing, `flee`); a hurt
##    one beside it cowers (Safe, `cower`).
##
## The player is put in the grunts' faction for the tour, so the guards watch the intruder, not the
## camera. Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/reactions_tour.tscn --seconds 40`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const GUARD := "res://gameplay/ai/ai_guard.tscn"
const CIVILIAN := "res://gameplay/ai/ai_civilian.tscn"
const CHARACTER := "res://gameplay/ai/ai_character.tscn"
## Where the player stands for every shot (the room's south end), looking along -Z.
const STAND := Vector3(31.0, 0.0, 6.0)
## Seconds into the clip each shot starts, and the end.
const COVER_AT := 22.0
const FLEE_AT := 32.0
const END := 41.0
## Camera pitch, degrees.
const PITCH := -14.0
## The overlay's pixel size in the tour (the shipped one is for a camera nearer).
const LABEL_PIXEL := 0.007
## The task layers' height above the feet at that size, clear of the overlay under it.
const TASKS_HEIGHT := 3.6
## Shot 1: the patrol stops; the intruder walks in from behind the camera, then is gone.
const STOP_A := Vector3(34.0, 0.0, -7.0)
const STOP_B := Vector3(34.0, 0.0, -1.0)
const GUARD_AT := Vector3(34.0, 0.0, -7.0)
const INTRUDER_START := Vector3(34.0, 0.0, 9.0)
const INTRUDER_IN := Vector3(35.0, 0.0, 2.5)
const GONE := Vector3(80.0, 0.0, 40.0)
const INTRUDE_AT := 3.0
const LEAVE_AT := 7.5
## Shot 2: the hurt guard, the box and the cover spot behind it, the intruder north of it.
const HURT_GUARD_AT := Vector3(36.0, 0.0, 2.0)
const BOX_AT := Vector3(34.0, 0.5, -3.0)
const COVER_SPOT := Vector3(34.0, 0.0, -1.9)
const INTRUDER_FAR := Vector3(34.5, 0.0, -10.0)
## Shot 3: the two civilians and their grunts.
const BRAVE_AT := Vector3(33.0, 0.0, 0.0)
const HURT_AT := Vector3(37.0, 0.0, 0.0)

var _clock := 0.0
var _actors: Array[Node] = []
var _intruder: AiCharacter
var _intruder_goal := Vector3.INF

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_player.teleport(STAND, PI)
	(_player.get_node("AiFactionMember") as AiFactionMember).faction = &"enemy"
	Health.of(_player).invulnerable = true
	_patrol_shot()


func _physics_process(delta: float) -> void:
	var was := _clock
	_clock += delta
	_face()
	_walk_intruder(delta)
	if _crossed(was, INTRUDE_AT):
		_intruder_goal = INTRUDER_IN
	if _crossed(was, LEAVE_AT) and _intruder != null:
		_intruder_goal = Vector3.INF
		_intruder.ai_controller().walk_direction = Vector3.ZERO
		_intruder.teleport(GONE, PI)
	if _crossed(was, COVER_AT):
		_clear()
		_cover_shot()
	if _crossed(was, FLEE_AT):
		_clear()
		_flee_shot()
	if _crossed(was, END):
		_finish()


func _patrol_shot() -> void:
	_marker(AiMarker.Kind.PATROL, STOP_A, 0.0)
	_marker(AiMarker.Kind.PATROL, STOP_B, 0.0)
	_add(GUARD, GUARD_AT, PI)
	_intruder = _body(INTRUDER_START, &"player")


func _cover_shot() -> void:
	# The cover spot behind the box faces the intruder (its -Z toward -Z, the north end).
	_box(BOX_AT)
	_marker(AiMarker.Kind.COVER, COVER_SPOT, 0.0)
	var guard := _add(GUARD, HURT_GUARD_AT, PI)
	var health := Health.of(guard)
	health.value = health.max_value * 0.45
	_intruder = _body(INTRUDER_FAR, &"player")
	_intruder_goal = Vector3.INF


func _flee_shot() -> void:
	var brave := _add(CIVILIAN, BRAVE_AT, 0.0)
	brave.profile.courage = 0.4
	var hurt := _add(CIVILIAN, HURT_AT, 0.0)
	var health := Health.of(hurt)
	health.value = health.max_value * 0.3
	_body(BRAVE_AT + Vector3(0.0, 0.0, -1.8), &"enemy")
	_body(HURT_AT + Vector3(0.0, 0.0, -1.8), &"enemy")
	_intruder = null


# A shipped kind with its overlay on.
func _add(scene: String, spot: Vector3, heading: float) -> AiCharacter:
	var character := (load(scene) as PackedScene).instantiate() as AiCharacter
	character.profile = character.profile.duplicate() as AiProfile
	character.debug = true
	_player.get_parent().add_child(character)
	character.debug_label.pixel_size = LABEL_PIXEL
	var tasks := character.get_node("TaskLabel") as Label3D
	tasks.pixel_size = LABEL_PIXEL
	tasks.position.y = TASKS_HEIGHT
	character.teleport(spot, heading)
	_actors.append(character)
	return character


# A body with no brain in `faction`, that takes no damage (the tour's intruder and grunts).
func _body(spot: Vector3, faction: StringName) -> AiCharacter:
	var character := (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	character.name = "Intruder" if faction == &"player" else "Grunt"
	_player.get_parent().add_child(character)
	(character.get_node("AiFactionMember") as AiFactionMember).faction = faction
	(character.senses as AiSenses).sight = false
	(character.senses as AiSenses).hearing = false
	Health.of(character).invulnerable = true
	character.teleport(spot, PI)
	_actors.append(character)
	return character


# A box to hide behind (a body on the World layer, so the eyes do not see through it).
func _box(spot: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.0, 0.6)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	body.add_child(mesh)
	body.position = spot
	_player.get_parent().add_child(body)
	_actors.append(body)


func _marker(kind: AiMarker.Kind, spot: Vector3, facing: float) -> void:
	var marker := AiMarker.new()
	marker.kind = kind
	marker.wait_seconds = 1.0
	marker.position = spot
	marker.rotation.y = facing
	_player.get_parent().add_child(marker)
	_actors.append(marker)


# The intruder walks straight to its goal on its movement channel (nobody drives it but the tour).
func _walk_intruder(_delta: float) -> void:
	if _intruder == null or not is_instance_valid(_intruder) or _intruder_goal == Vector3.INF:
		return
	var controller := _intruder.ai_controller()
	var to := _intruder_goal - _intruder.global_position
	to.y = 0.0
	if to.length() < 0.3:
		controller.walk_direction = Vector3.ZERO
		return
	controller.walk_direction = to.normalized()
	controller.walk_strength = 0.6


func _clear() -> void:
	for actor in _actors:
		if is_instance_valid(actor):
			actor.queue_free()
	_actors.clear()
	_intruder = null


func _crossed(was: float, at: float) -> bool:
	return was < at and _clock >= at


# Holds the camera along -Z at a small pitch, a few degrees a frame.
func _face() -> void:
	var by_yaw := clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0)
	var by_pitch := clampf(PITCH - _rig.pitch, -2.0, 2.0)
	_rig.orbit(Vector2(-by_yaw, by_pitch))


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
