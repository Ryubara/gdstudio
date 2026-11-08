# The pushable cubes: heavy and grippy, pushed at a walk so the push animation reads for as long
# as the character walks into them. A cube moves at the speed its `push_speed` says, stops when
# the character stops, and the spheres of the map are pushed as before.
extends GdUnitTestSuite

const PROP := "res://gameplay/physics_prop/physics_prop.tscn"
const LEVEL := "res://world/prototype/prototype_level.tscn"

var _arena: PlayArena
var _player: Player


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _cube(speed: float, weight := 60.0) -> PhysicsProp:
	var cube := load(PROP).instantiate() as PhysicsProp
	cube.weight = weight
	cube.grip = 0.5
	cube.bounciness = 0.0
	cube.push_speed = speed
	cube.position = Vector3(0.0, 0.5, -1.2)
	_arena.add_child(cube)
	return cube


func _mean_speed(cube: PhysicsProp, ticks: int) -> float:
	var total := 0.0
	for _tick in ticks:
		await get_tree().physics_frame
		total += cube.linear_velocity.z
	return total / ticks


func test_the_map_has_a_short_run_of_heavy_cubes_with_room_to_push() -> void:
	var level := load(LEVEL).instantiate() as Node3D
	add_child(level)
	var cubes := level.get_node("PushCubes").get_children()
	assert_int(cubes.size()).is_between(3, 6)
	for cube: PhysicsProp in cubes:
		assert_int(cube.shape).is_equal(PhysicsProp.Shape.BOX)
		assert_float(cube.weight).is_equal(60.0)
		assert_float(cube.grip).is_equal(0.5)
		assert_float(cube.push_speed).is_equal(1.2)
		assert_float(cube.global_position.y).is_equal_approx(0.5, 0.001)
	level.free()


func test_a_cube_is_pushed_at_its_push_speed_and_the_character_walks_that_slowly() -> void:
	var cube := _cube(1.2)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 30)
	var pushing := 0
	var speeds := 0.0
	for _tick in 60:
		await get_tree().physics_frame
		speeds += cube.linear_velocity.z
		if _player.state == Player.State.PUSH:
			pushing += 1
	# The cube is given 1.2 m/s each tick and the friction takes some back between pushes.
	assert_float(speeds / 60.0).is_between(-1.25, -0.85)
	assert_float(_player.ground_speed()).is_less(1.5)
	assert_int(pushing).is_greater(55)
	var animation := _player.get_node("Animation") as PlayerAnimation
	assert_str(String(animation.body_state())).is_equal("push")


func test_a_push_lasts_for_as_far_as_the_character_walks() -> void:
	var cube := _cube(1.2)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	var pushing := 0
	for _tick in 240:
		await get_tree().physics_frame
		if _player.state == Player.State.PUSH:
			pushing += 1
	# Four seconds of walking: the cube moved about 4.8 m and the character pushed all along.
	assert_int(pushing).is_greater(215)
	assert_float(cube.global_position.z).is_less(-3.5)


func test_a_cube_stops_soon_after_the_character_does() -> void:
	var cube := _cube(1.2)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	InputSim.key(KEY_W, false)
	var stopped_at := cube.global_position.z
	await InputSim.ticks(get_tree(), 30)
	assert_float(cube.linear_velocity.length()).is_less(0.05)
	assert_float(absf(cube.global_position.z - stopped_at)).is_less(0.4)


func test_a_prop_with_no_push_speed_is_pushed_as_it_always_was() -> void:
	var crate := _cube(0.0, 10.0)
	crate.grip = 0.6
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	# The player's own run speed pushes it: faster than any cube's walk.
	assert_float(absf(crate.linear_velocity.z)).is_greater(2.0)
	assert_float(_player.ground_speed()).is_greater(2.0)


func test_push_speed_is_live() -> void:
	var cube := _cube(1.2)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	cube.push_speed = 0.6
	await InputSim.ticks(get_tree(), 40)
	assert_float(await _mean_speed(cube, 30)).is_between(-0.65, -0.35)
	cube.push_speed = 2.0
	await InputSim.ticks(get_tree(), 40)
	assert_float(await _mean_speed(cube, 30)).is_between(-2.1, -1.5)


func test_weight_and_grip_change_how_far_a_shove_goes() -> void:
	var light := _cube(0.0, 20.0)
	light.grip = 0.2
	light.position.x = -4.0
	var heavy := _cube(0.0, 200.0)
	heavy.grip = 1.0
	heavy.position.x = 4.0
	await InputSim.ticks(get_tree(), 4)
	light.apply_central_impulse(Vector3(0.0, 0.0, -40.0))
	heavy.apply_central_impulse(Vector3(0.0, 0.0, -40.0))
	await InputSim.ticks(get_tree(), 120)
	assert_float(absf(light.global_position.z + 1.2)).is_greater(
		absf(heavy.global_position.z + 1.2)
	)
