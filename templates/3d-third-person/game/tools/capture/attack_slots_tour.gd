## Films the attack slots (kit #1203) from the player's own camera, with each guard's debug
## overlay on, in the empty middle room of the pathing section: eight guards on an arc see an
## intruder (a body of the player's faction that takes no damage) and only `SLOTS` of them aim
## and fire; the rest stand with their guns down (`engage`, held) and wait. At `KILL_AT` one of the
## firing guards dies, and a held guard takes its slot and opens fire.
##
## The player is put in the guards' faction for the tour, so they fight the intruder, not the
## camera. Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/attack_slots_tour.tscn
## --seconds 16`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const GUARD := "res://gameplay/ai/ai_guard.tscn"
const CHARACTER := "res://gameplay/ai/ai_character.tscn"
## Slots a target in the tour (fewer than the shipped counts, so most of the arc waits).
const SLOTS := 3
const GUARDS := 8
## Where the player stands (the room's south end), looking along -Z, and the intruder before it.
const STAND := Vector3(31.0, 0.0, 7.0)
const INTRUDER_AT := Vector3(31.0, 0.0, 3.0)
## The arc of guards round the intruder, to the north.
const RADIUS := 8.0
const ARC := deg_to_rad(90.0)
## Seconds into the clip a firing guard dies, and the end.
const KILL_AT := 8.0
const END := 16.0
## Camera pitch, degrees.
const PITCH := -12.0
## The overlay's pixel size in the tour (the shipped one is for a camera nearer).
const LABEL_PIXEL := 0.007
## The task layers' height above the feet at that size, clear of the overlay under it.
const TASKS_HEIGHT := 3.6

var _clock := 0.0
var _guards: Array[AiCharacter] = []
var _director: AiDirector

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_player.teleport(STAND, PI)
	(_player.get_node("AiFactionMember") as AiFactionMember).faction = &"enemy"
	Health.of(_player).invulnerable = true
	_director = AiDirector.find(get_tree())
	_director.desktop_attack_slots = SLOTS
	_director.web_attack_slots = SLOTS
	_intruder()
	for index in GUARDS:
		var angle := -ARC / 2.0 + ARC * index / (GUARDS - 1)
		var spot := INTRUDER_AT + Vector3(sin(angle), 0.0, -cos(angle)) * RADIUS
		_guards.append(_add(spot, -angle))


func _physics_process(delta: float) -> void:
	var was := _clock
	_clock += delta
	_face()
	if was < KILL_AT and _clock >= KILL_AT:
		for guard in _guards:
			if _director.slots.holds(guard):
				guard.die()
				break
	if was < END and _clock >= END:
		_finish()


# A guard with its overlay on, facing `heading`.
func _add(spot: Vector3, heading: float) -> AiCharacter:
	var character := (load(GUARD) as PackedScene).instantiate() as AiCharacter
	character.profile = character.profile.duplicate() as AiProfile
	character.debug = true
	_player.get_parent().add_child(character)
	character.debug_label.pixel_size = LABEL_PIXEL
	var tasks := character.get_node("TaskLabel") as Label3D
	tasks.pixel_size = LABEL_PIXEL
	tasks.position.y = TASKS_HEIGHT
	character.teleport(spot, heading)
	return character


# The intruder: a body with no brain in the player's faction that takes no damage.
func _intruder() -> void:
	var character := (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	character.name = "Intruder"
	_player.get_parent().add_child(character)
	(character.get_node("AiFactionMember") as AiFactionMember).faction = &"player"
	(character.senses as AiSenses).sight = false
	(character.senses as AiSenses).hearing = false
	Health.of(character).invulnerable = true
	character.teleport(INTRUDER_AT, PI)


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
