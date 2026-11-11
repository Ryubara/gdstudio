## Films two factions in a fight with the band overlay on, from the player's own camera: three
## grunts (faction `enemy`) and three allies (`ally`) face each other across the lane, a civilian
## stands between, and each ring under a character shows how it feels about the player (red
## Hostile, orange Unfriendly, grey Neutral, green Friendly, blue Allied). The two sides aim and
## trade shots through their `HitZones` (each picks the nearest character it is Hostile toward,
## asking `AiFactions` as an AI's fire decision will), a grunt dies into its ragdoll, and then the
## player keeps shooting the nearest ally: its faction's ring turns from blue to red as the attacks
## are reported, and the allies are Hostile to the player.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/factions_tour.tscn --seconds 9`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const CHARACTER := "res://gameplay/ai/ai_character.tscn"
const GRUNT := "res://gameplay/ai/profiles/grunt.tres"
const ALLY := "res://gameplay/ai/profiles/ally.tres"
const CIVILIAN := "res://gameplay/ai/profiles/civilian.tres"
## Where the player stands (looking along -Z, right of the lane so its body hides nobody), the
## two rows facing each other across the lane and the civilian between them.
const STAND := Vector3(-5.0, 0.0, 19.5)
const GRUNT_X := -3.6
const ALLY_X := -9.0
const ROW_Z: Array[float] = [11.0, 12.6, 14.2]
const CIVILIAN_AT := Vector3(-6.3, 0.0, 11.0)
## Seconds into the clip of each beat, and between blows.
const FIGHT_STARTS := 1.0
const FIGHT_ENDS := 4.6
const GRUNT_DIES := 3.4
const PLAYER_STARTS := 5.0
const BLOW_SECONDS := 0.7
const PLAYER_BLOW_SECONDS := 0.55
const END := 8.5
## Damage of a blow in the fight, as a share of health.
const BLOW_SHARE := 0.08
## Camera pitch, in degrees, while filming.
const PITCH := 6.0

var _clock := 0.0
var _since_blow := 0.0
var _since_player_blow := 0.0
var _grunts: Array[AiCharacter] = []
var _allies: Array[AiCharacter] = []
var _everyone: Array[AiCharacter] = []
var _factions: AiFactions

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_player.teleport(STAND, PI)
	for z in ROW_Z:
		_grunts.append(_spawn(GRUNT, Vector3(GRUNT_X, 0.0, z), -PI / 2.0))
		_allies.append(_spawn(ALLY, Vector3(ALLY_X, 0.0, z), PI / 2.0))
	_spawn(CIVILIAN, CIVILIAN_AT, 0.0)
	_factions = AiFactions.find(self)
	_factions.show_bands = true


func _spawn(profile: String, spot: Vector3, heading: float) -> AiCharacter:
	var character := (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	character.profile = load(profile) as AiProfile
	character.debug = true
	_player.get_parent().add_child(character)
	character.teleport(spot, heading)
	_everyone.append(character)
	return character


func _physics_process(delta: float) -> void:
	var was := _clock
	_clock += delta
	_face()
	if _clock >= FIGHT_STARTS and _clock < FIGHT_ENDS:
		_since_blow += delta
		_aim_all()
		if _since_blow >= BLOW_SECONDS:
			_since_blow = 0.0
			_trade_blows()
	if _crossed(was, FIGHT_ENDS):
		for character in _everyone:
			character.ai_controller().release()
	if _crossed(was, GRUNT_DIES):
		_hit(_grunts[1], _allies[1], Health.of(_grunts[1]).max_value)
	if _clock >= PLAYER_STARTS:
		_since_player_blow += delta
		if _since_player_blow >= PLAYER_BLOW_SECONDS:
			_since_player_blow = 0.0
			var ally := _allies[2]
			Health.of(ally).value = Health.of(ally).max_value
			_hit(ally, _player, 1.0)
	if _crossed(was, END):
		_finish()


# Each living character turns its aim toward the nearest character it is Hostile toward.
func _aim_all() -> void:
	for character in _everyone:
		var controller := character.ai_controller()
		var target := _target_of(character)
		if target == null or character.is_dead():
			controller.release()
			continue
		var toward := target.global_position - character.global_position
		toward.y = 0.0
		controller.look_direction = toward.normalized()
		controller.aim = true


# Each living character with a Hostile target it may hurt lands one blow.
func _trade_blows() -> void:
	for character in _everyone:
		var target := _target_of(character)
		if target != null and not character.is_dead():
			_hit(target, character, Health.of(target).max_value * BLOW_SHARE)


func _target_of(character: AiCharacter) -> AiCharacter:
	var best: AiCharacter = null
	var best_distance := INF
	for other in _everyone:
		if other == character or other.is_dead():
			continue
		if not _factions.is_hostile_between(character, other):
			continue
		var distance := character.global_position.distance_squared_to(other.global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


# A shot at the chest through the target's hit zones, so `AiFactions.can_hurt` and the reports
# apply; no knockback, so the rows hold their places.
func _hit(target: Character, source: Node3D, amount: float) -> void:
	var zones := target.find_children("*", "HitZones", true, false)
	if zones.is_empty():
		return
	var chest := target.global_position + Vector3.UP * 1.3
	var along := chest - (source.global_position + Vector3.UP * 1.3)
	(zones[0] as HitZones).deliver(HitRecord.shot(amount, &"", &"", chest, along, 0.0, source))


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


# Holds the camera along -Z at a small pitch, a few degrees a frame.
func _face() -> void:
	var by_yaw := clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0)
	var by_pitch := clampf(PITCH - _rig.pitch, -2.0, 2.0)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
