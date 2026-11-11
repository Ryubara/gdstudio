class_name AiNoiseMaker
extends Node
## Makes the noises its parent character makes, on the level's `AiNoise` board, for the AI to
## hear: a footstep every `stride` metres it moves on the ground (louder the faster, quieter
## crouched or lying down), a landing, a shot when its weapon fires and an impact where the shot
## lands (with no source: a listener near it hears "something", not the shooter there). A child
## of `character.tscn`, so the player, an AI character and a server's body all make them; with no
## board in the tree (or on a client of a remote server) it does nothing.
##
## It reads the body's movement, never the animation, so a server with no model hears the same
## steps as a desktop game. It checks every `check_ticks` physics ticks, not every tick.

## Makes noises. Off: the character is silent to the AI.
@export var enabled := true
@export_group("Footsteps")
## Metres on the ground between two footstep noises.
@export_range(0.1, 5.0, 0.05, "suffix:m") var stride := 1.4
## The ground speed whose footsteps have loudness 1 (a run); a walk is quieter.
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var loud_speed := 4.5
## The loudest a footstep gets, at a sprint.
@export_range(0.0, 4.0, 0.05) var max_loudness := 1.4
## The quietest a footstep that sounds at all is.
@export_range(0.0, 1.0, 0.01) var min_loudness := 0.15
## Footsteps while crouched are this share as loud.
@export_range(0.0, 1.0, 0.01) var crouch_share := 0.4
## A crawl lying down is this share as loud.
@export_range(0.0, 1.0, 0.01) var prone_share := 0.2
## Physics ticks between two looks at how far the body moved.
@export_range(1, 30) var check_ticks := 6
@export_group("Weapon")
## The loudness of a shot (1: the `shot` radius of the board).
@export_range(0.0, 4.0, 0.05) var shot_loudness := 1.0
## The loudness of the impact where a shot lands.
@export_range(0.0, 4.0, 0.05) var impact_loudness := 1.0
## The landing speed (m/s) whose landing has loudness 1.
@export_range(0.5, 30.0, 0.5, "suffix:m/s") var loud_landing := 8.0

var _character: Character
var _last := Vector3.ZERO
var _walked := 0.0
var _ticks := 0
var _weapon: Weapon


func _ready() -> void:
	_character = get_parent() as Character
	if _character == null or Engine.is_editor_hint():
		set_physics_process(false)
		return
	_last = _character.global_position
	_ticks = _character.get_instance_id() % check_ticks
	_character.landed.connect(_on_landed)
	_watch_weapon(_character.weapon)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks < check_ticks:
		return
	_ticks = 0
	var at := _character.global_position
	var moved := Vector2(at.x - _last.x, at.z - _last.z).length()
	_last = at
	if not enabled or not _character.is_on_floor() or _character.is_dead():
		_walked = 0.0
		return
	if _character.weapon != _weapon:
		_watch_weapon(_character.weapon)
	_walked += moved
	if _walked < stride:
		return
	_walked = fmod(_walked, stride)
	AiNoise.emit(self, AiNoise.FOOTSTEP, at, footstep_loudness(), _character)


## How loud a footstep of the character is now: its ground speed over `loud_speed`, between
## `min_loudness` and `max_loudness`, times the crouch or prone share.
func footstep_loudness() -> float:
	var loudness := clampf(_character.ground_speed() / loud_speed, min_loudness, max_loudness)
	if _character.prone:
		loudness *= prone_share
	elif _character.crouching:
		loudness *= crouch_share
	return loudness


func _watch_weapon(weapon: Weapon) -> void:
	if _weapon != null and is_instance_valid(_weapon):
		if _weapon.fired.is_connected(_on_fired):
			_weapon.fired.disconnect(_on_fired)
			_weapon.hit_scanned.disconnect(_on_hit_scanned)
	_weapon = weapon
	if _weapon != null:
		_weapon.fired.connect(_on_fired)
		_weapon.hit_scanned.connect(_on_hit_scanned)


func _on_landed(impact_speed: float) -> void:
	if enabled:
		var loudness := clampf(impact_speed / loud_landing, 0.0, max_loudness)
		AiNoise.emit(self, AiNoise.LANDING, _character.global_position, loudness, _character)


func _on_fired(projectile: Projectile) -> void:
	if not enabled:
		return
	AiNoise.emit(self, AiNoise.SHOT, _weapon.global_position, shot_loudness, _character)
	if projectile != null and not projectile.impacted.is_connected(_on_impacted):
		projectile.impacted.connect(_on_impacted, CONNECT_ONE_SHOT)


func _on_hit_scanned(hit: Dictionary) -> void:
	if enabled and hit.has("position"):
		AiNoise.emit(self, AiNoise.IMPACT, hit["position"], impact_loudness)


func _on_impacted(_collider: Node, point: Vector3, _normal: Vector3) -> void:
	if enabled:
		AiNoise.emit(self, AiNoise.IMPACT, point, impact_loudness)
