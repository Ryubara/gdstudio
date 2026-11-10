class_name Weapon
extends Node3D
## A hitscan weapon with a magazine and a reserve. The server owns the ammo; a client asks to fire.

## A round left the muzzle.
signal fired(ammo_left: int)
## The magazine was refilled.
signal reloaded(ammo: int, reserve: int)
## The trigger was pulled on an empty magazine.
signal dry_fired

## Metres a shot reaches.
const RANGE_M := 80.0

## Shot interval, reload time, magazine and reserve.
@export var tuning: WeaponTuning

## Rounds in the magazine.
var ammo: int = 0
## Rounds carried outside the magazine.
var reserve: int = 0

var _cooldown := 0.0
var _reload_left := 0.0
var _muzzle: Marker3D


func _ready() -> void:
	_muzzle = get_node_or_null("Muzzle")
	ammo = tuning.magazine_size
	reserve = tuning.starting_reserve


func _process(_delta: float) -> void:
	var text := "Ammo: %d / %d" % [ammo, reserve]
	for label: Label in get_tree().get_nodes_in_group("ammo_label"):
		label.text = text


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= 0.016
		if _reload_left <= 0.0:
			_finish_reload()


## Pull the trigger. Returns true when a round was fired.
func fire() -> bool:
	if _reload_left > 0.0 or _cooldown > 0.0:
		return false
	if ammo <= 0:
		dry_fired.emit()
		return false
	ammo -= 1
	_cooldown = tuning.shot_interval
	var origin := _muzzle.global_position
	fired.emit(ammo)
	_hit_scan(origin)
	return true


## Start a reload when the magazine is not full and there is reserve to put in it.
func reload() -> void:
	if _reload_left > 0.0 or ammo >= tuning.magazine_size or reserve <= 0:
		return
	_reload_left = tuning.reload_seconds


## Add rounds to the reserve, up to the cap.
func add_ammo(amount: int) -> void:
	reserve = mini(reserve + amount, tuning.reserve_cap)


func _finish_reload() -> void:
	var needed := tuning.magazine_size - ammo
	ammo += needed
	reserve -= needed
	reloaded.emit(ammo, reserve)


func _hit_scan(origin: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin - global_basis.z * RANGE_M)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var target: Object = hit.collider
	if target.has_method("take_damage"):
		target.take_damage(tuning.damage)
