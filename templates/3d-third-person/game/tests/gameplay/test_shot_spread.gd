# The spread grows only over shots fired in a row and falls back once firing stops (gdstudio
# #1411). The rifle's definition on a `Weapon` alone, ticked by hand as a character ticks it: a
# first shot from rest leaves along the aim, each shot of a held trigger widens the cone by one
# `spread_build_shots` share up to `spread`, the cone does not fall between a held trigger's shots,
# it falls over `spread_recovery_time` once the trigger is let go, and the step state carries it.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const RIFLE := "res://gameplay/weapon/rifle.tres"
const TICK := 1.0 / 60.0

var _world: Node3D
var _weapon: Weapon
var _muzzle: Marker3D


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_weapon = load(WEAPON).instantiate() as Weapon
	_weapon.self_ticking = false
	_weapon.effects = false
	_world.add_child(_weapon)
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0.0, 1.0, 0.0)
	_world.add_child(_muzzle)
	_weapon.muzzle = _muzzle
	var definition := (load(RIFLE) as WeaponDef).duplicate() as WeaponDef
	definition.auto_reload = false
	definition.magazine_size = 100
	_weapon.definition = definition
	_weapon.make_ready()
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_world)


# Holds the trigger for `ticks` ticks (a pull, then the weapon's tick, as `Character.step` does):
# for each shot, the cone it was fired with and how far it left off the aim (degrees).
func _hold(ticks: int) -> Array[Vector2]:
	var shots: Array[Vector2] = []
	var straight := -_muzzle.global_basis.z
	for _tick in ticks:
		var cone := _weapon.spread_now
		if _weapon.pull() == Weapon.Pull.FIRED:
			shots.append(Vector2(cone, rad_to_deg(_weapon.last_heading.angle_to(straight))))
		_weapon.tick(TICK)
	return shots


func _rest(ticks: int) -> void:
	for _tick in ticks:
		_weapon.tick(TICK)


func test_a_first_shot_leaves_along_the_aim_and_the_spread_grows_shot_by_shot() -> void:
	var definition := _weapon.definition
	assert_float(definition.first_shot_spread).is_equal(0.0)
	var shots := _hold(90)
	assert_int(shots.size()).is_greater_equal(9)
	assert_float(shots[0].x).is_equal(0.0)
	assert_float(shots[0].y).is_less(0.0001)
	var build := definition.spread_build_shots
	for index in shots.size():
		# Never falls between a held trigger's shots: one share more a shot, up to the most.
		var cone := definition.spread * minf(float(index) / build, 1.0)
		assert_float(shots[index].x).is_equal_approx(cone, 0.0001)
		assert_float(shots[index].y).is_less_equal(cone + 0.0001)
	var turned := shots.slice(1).filter(func(shot: Vector2) -> bool: return shot.y > 0.05)
	assert_array(turned).is_not_empty()


func test_the_spread_falls_back_once_firing_stops() -> void:
	var definition := _weapon.definition
	_hold(60)
	assert_float(_weapon.spread_now).is_equal_approx(definition.spread, 0.0001)
	# 60 ticks end as the last shot's cooldown does: half the recovery from here, about half the cone.
	assert_bool(_weapon.is_cooling_down()).is_false()
	_rest(roundi(definition.spread_recovery_time / TICK / 2.0))
	assert_float(_weapon.spread_now).is_between(definition.spread * 0.4, definition.spread * 0.6)
	_rest(ceili(ShotSpread.rest_time(definition) / TICK))
	assert_float(_weapon.spread_now).is_equal(0.0)
	var shots := _hold(1)
	assert_float(shots[0].y).is_less(0.0001)


func test_a_short_pause_keeps_part_of_the_spread() -> void:
	_hold(60)
	_rest(6)
	var cone := _weapon.spread_now
	assert_float(cone).is_greater(0.5)
	assert_float(cone).is_less(_weapon.definition.spread)


func test_the_step_state_carries_the_spread() -> void:
	_hold(12)
	var kept: Array = []
	_weapon.save_step_state(kept)
	var cone := _weapon.spread_now
	assert_float(cone).is_greater(0.0)
	_weapon.make_ready()
	assert_float(_weapon.spread_now).is_equal(0.0)
	_weapon.load_step_state(kept)
	assert_float(_weapon.spread_now).is_equal_approx(cone, 0.0001)


func test_a_first_shot_spread_of_its_own_is_kept_from_rest() -> void:
	_weapon.definition.first_shot_spread = 0.5
	var shots := _hold(1)
	assert_float(shots[0].x).is_equal_approx(0.5, 0.0001)
	assert_float(shots[0].y).is_less_equal(0.5001)
