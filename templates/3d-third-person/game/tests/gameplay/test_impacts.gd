# The marks of the bullet impacts, from real shots: a mark sits at the hit point facing the surface
# normal on a wall, a floor, a pushed crate and a moving platform; it rides the body it landed on
# and goes with it; the cap takes the oldest; the lifetime fades and removes marks (0 keeps them).
extends GdUnitTestSuite

const PROP := "res://gameplay/physics_prop/physics_prop.tscn"
const PLATFORM := "res://gameplay/moving_platform/moving_platform.tscn"
const FLAT := Vector3.ONE * 0.001

var _arena: PlayArena
var _impacts: Impacts
var _wall: StaticBody3D


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	_impacts = ImpactShots.impacts_of(_arena)
	_wall = _arena.add_block(Vector2(0.0, -5.0), Vector3(10.0, 4.0, 0.5), 4.0)
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _shoot(from: Vector3, toward: Vector3) -> void:
	await ImpactShots.shoot(get_tree(), _arena, from, toward)


# A shot at the wall from the south, at height 1.5 and across `x`.
func _shoot_wall(x: float) -> void:
	await _shoot(Vector3(x, 1.5, 0.0), Vector3(x, 1.5, -10.0))


# A shot straight down onto the floor at `x`.
func _shoot_floor(x: float) -> void:
	await _shoot(Vector3(x, 3.0, 0.0), Vector3(x, 0.0, 0.0))


func _ticks(count: int) -> void:
	for _tick in count:
		await get_tree().physics_frame


func _crate_at(spot: Vector3) -> PhysicsProp:
	var crate := load(PROP).instantiate() as PhysicsProp
	crate.position = spot
	_arena.add_child(crate)
	await get_tree().physics_frame
	return crate


func _mark_count_in_tree() -> int:
	return get_tree().root.find_children("*", "ImpactMark", true, false).size()


func test_a_shot_on_a_wall_leaves_a_mark_at_the_hit_facing_the_normal() -> void:
	await _shoot(Vector3(1.0, 1.5, 0.0), Vector3(1.0, 1.5, -10.0))
	assert_int(_impacts.mark_count()).is_equal(1)
	var mark := _impacts.marks()[0]
	assert_object(mark.get_parent()).is_same(_wall)
	# The wall's face is at z = -4.75; the mark sits a little off it.
	var at := mark.global_position
	assert_float(at.x).is_equal_approx(1.0, 0.01)
	assert_float(at.y).is_equal_approx(1.5, 0.01)
	assert_float(at.z).is_equal_approx(-4.75 + _impacts.surface_offset, 0.002)
	assert_vector(mark.global_basis.z.normalized()).is_equal_approx(Vector3.BACK, FLAT)


func test_a_shot_on_the_floor_leaves_a_mark_facing_up() -> void:
	await _shoot_floor(2.0)
	assert_int(_impacts.mark_count()).is_equal(1)
	var mark := _impacts.marks()[0]
	assert_float(mark.global_position.y).is_equal_approx(_impacts.surface_offset, 0.002)
	assert_vector(mark.global_basis.z.normalized()).is_equal_approx(Vector3.UP, FLAT)


func test_a_slanted_hit_turns_the_mark_to_the_surface_not_to_the_shot() -> void:
	# A shot that comes in from the side hits the wall's face at an angle: the mark still faces +Z.
	await _shoot(Vector3(-3.0, 1.0, 0.0), Vector3(2.0, 2.0, -10.0))
	var mark := _impacts.marks()[0]
	assert_vector(mark.global_basis.z.normalized()).is_equal_approx(Vector3.BACK, FLAT)


func test_a_pushed_crate_carries_its_marks() -> void:
	var start := Vector3(3.0, 0.5, -2.0)
	var crate := await _crate_at(start)
	await _shoot(Vector3(3.0, 0.5, 3.0), start)
	assert_int(_impacts.mark_count()).is_equal(1)
	var mark := _impacts.marks()[0]
	assert_object(mark.get_parent()).is_same(crate)
	assert_str(mark.surface_name).is_equal("wood")
	var local := mark.position
	var world_before := mark.global_position
	await _ticks(40)
	assert_float(crate.global_position.distance_to(start)).is_greater(0.3)
	assert_float(mark.global_position.distance_to(world_before)).is_greater(0.3)
	assert_vector(mark.position).is_equal_approx(local, FLAT * 0.1)
	# It is still on the crate's face: the mark's point in the crate's space.
	assert_float(absf(crate.to_local(mark.global_position).z)).is_equal_approx(0.5, 0.01)


func test_a_moving_platform_carries_its_marks() -> void:
	var platform := load(PLATFORM).instantiate() as MovingPlatform
	platform.position = Vector3(-3.0, 1.0, 2.0)
	platform.wait_time = 0.0
	_arena.add_child(platform)
	await _ticks(2)
	await _shoot(Vector3(-3.0, 4.0, 2.0), Vector3(-3.0, 0.0, 2.0))
	assert_int(_impacts.mark_count()).is_equal(1)
	var mark := _impacts.marks()[0]
	assert_object(mark.get_parent()).is_same(platform)
	assert_str(mark.surface_name).is_equal("metal")
	var offset := mark.global_position - platform.global_position
	var platform_before := platform.global_position
	await _ticks(30)
	assert_float(platform.global_position.distance_to(platform_before)).is_greater(0.5)
	assert_vector(mark.global_position - platform.global_position).is_equal_approx(
		offset, FLAT * 0.1
	)


func test_a_mark_on_a_freed_body_goes_with_it() -> void:
	var start := Vector3(3.0, 0.5, -2.0)
	var crate := await _crate_at(start)
	await _shoot(Vector3(3.0, 0.5, 3.0), start)
	assert_int(_impacts.mark_count()).is_equal(1)
	crate.queue_free()
	await _ticks(2)
	assert_int(_impacts.mark_count()).is_equal(0)
	assert_int(_mark_count_in_tree()).is_equal(0)
	# And the pool takes a new mark as if nothing had happened.
	await _shoot_wall(0.0)
	assert_int(_impacts.mark_count()).is_equal(1)


func test_the_cap_takes_the_oldest_mark_first() -> void:
	_impacts.max_marks = 3
	for step in 5:
		await _shoot_floor(-4.0 + step * 2.0)
	assert_int(_impacts.mark_count()).is_equal(3)
	assert_int(_mark_count_in_tree()).is_equal(3)
	var xs: Array[float] = []
	for mark in _impacts.marks():
		xs.append(snappedf(mark.global_position.x, 0.01))
	# The first two (x = -4 and -2) are gone: the newest took their places.
	assert_array(xs).is_equal([0.0, 2.0, 4.0])


func test_lowering_the_cap_takes_the_extra_marks_off_at_once() -> void:
	for step in 4:
		await _shoot_floor(-3.0 + step * 2.0)
	assert_int(_impacts.mark_count()).is_equal(4)
	_impacts.max_marks = 2
	assert_int(_impacts.mark_count()).is_equal(2)
	assert_float(_impacts.marks()[0].global_position.x).is_equal_approx(1.0, 0.01)
	_impacts.max_marks = 0
	assert_int(_impacts.mark_count()).is_equal(0)
	await _shoot_floor(0.0)
	assert_int(_impacts.mark_count()).is_equal(0)


func test_a_mark_fades_at_the_end_of_its_lifetime_and_is_then_freed() -> void:
	_impacts.mark_lifetime = 1.0
	_impacts.mark_fade_time = 0.5
	await _shoot_wall(0.0)
	var mark := _impacts.marks()[0]
	assert_float(mark.fade()).is_equal(1.0)
	mark.age = 0.6
	await get_tree().physics_frame
	assert_float(mark.fade()).is_between(0.05, 0.95)
	mark.age = 0.8
	await get_tree().physics_frame
	assert_float(mark.fade()).is_less(0.5)
	mark.age = 0.999
	await _ticks(3)
	assert_int(_impacts.mark_count()).is_equal(0)
	assert_int(_mark_count_in_tree()).is_equal(0)


func test_a_lifetime_of_zero_keeps_a_mark_until_a_newer_one_needs_its_place() -> void:
	_impacts.mark_lifetime = 0.0
	await _shoot_wall(0.0)
	var mark := _impacts.marks()[0]
	mark.age = 100000.0
	await _ticks(3)
	assert_int(_impacts.mark_count()).is_equal(1)
	assert_float(mark.fade()).is_equal(1.0)


func test_a_fade_time_of_zero_removes_a_mark_without_fading_it() -> void:
	_impacts.mark_lifetime = 1.0
	_impacts.mark_fade_time = 0.0
	await _shoot_wall(0.0)
	var mark := _impacts.marks()[0]
	mark.age = 0.95
	await get_tree().physics_frame
	assert_float(mark.fade()).is_equal(1.0)
	assert_int(_impacts.mark_count()).is_equal(1)


func test_marks_off_leaves_none_and_clear_takes_them_all_off() -> void:
	_impacts.marks_enabled = false
	await _shoot_wall(0.0)
	assert_int(_impacts.mark_count()).is_equal(0)
	_impacts.marks_enabled = true
	await _shoot_wall(0.0)
	await _shoot_wall(1.0)
	assert_int(_impacts.mark_count()).is_equal(2)
	_impacts.clear_marks()
	assert_int(_impacts.mark_count()).is_equal(0)
