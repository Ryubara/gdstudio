# The character through simulated input: keys and a pad button go through the engine's input
# path and the project's InputMap, and the real physics world moves the body. The animation
# state is read after each.
extends GdUnitTestSuite

const TICKS := 60

var _arena: PlayArena
var _player: Player


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _angle_between(a: float, b: float) -> float:
	return absf(angle_difference(a, b))


func test_it_walks_runs_and_sprints_at_the_speeds_in_the_tuning() -> void:
	var tuning := _player.tuning
	InputSim.key(KEY_X, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_player.ground_speed()).is_equal_approx(tuning.walk_speed, 0.1)
	assert_int(_player.state).is_equal(Player.State.WALK)
	InputSim.key(KEY_X, false)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_player.ground_speed()).is_equal_approx(tuning.run_speed, 0.1)
	assert_int(_player.state).is_equal(Player.State.RUN)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_player.ground_speed()).is_equal_approx(tuning.sprint_speed, 0.1)


func test_it_turns_to_the_way_it_moves_and_stops_when_the_keys_are_let_go() -> void:
	InputSim.key(KEY_D, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_angle_between(_player.facing, atan2(1.0, 0.0))).is_less(0.1)
	assert_float(_player.velocity.x).is_greater(3.0)
	InputSim.key(KEY_D, false)
	# A jog's stop covers its clip's 1.96 m in 1.13 s (gdstudio #1415).
	await InputSim.ticks(get_tree(), 75)
	assert_float(_player.ground_speed()).is_less(0.05)
	assert_int(_player.state).is_equal(Player.State.IDLE)


func test_a_pad_stick_moves_it_by_how_far_it_is_pushed() -> void:
	InputSim.pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	await InputSim.ticks(get_tree(), 30)
	var full := _player.ground_speed()
	assert_float(full).is_equal_approx(_player.tuning.run_speed, 0.15)
	InputSim.pad_axis(JOY_AXIS_LEFT_Y, -0.5)
	await InputSim.ticks(get_tree(), 40)
	# A half push is a walk: slower than the full push, and above standing.
	assert_float(_player.ground_speed()).is_between(0.5, _player.tuning.walk_speed)
	assert_int(_player.state).is_equal(Player.State.WALK)


func test_a_jump_rises_the_tuned_height_and_lands() -> void:
	var landings: Array[float] = []
	var jumps := [0]
	_player.landed.connect(func(speed: float) -> void: landings.append(speed))
	_player.jumped.connect(func() -> void: jumps[0] += 1)
	InputSim.key(KEY_SPACE, true)
	var top := 0.0
	var states := {}
	for _tick in TICKS * 2:
		await get_tree().physics_frame
		top = maxf(top, _player.global_position.y)
		states[_player.state] = true
	InputSim.key(KEY_SPACE, false)
	assert_int(jumps[0]).is_equal(1)
	assert_float(top).is_equal_approx(_player.tuning.jump_height, 0.12)
	assert_bool(states.has(Player.State.JUMP)).is_true()
	assert_bool(states.has(Player.State.FALL)).is_true()
	assert_array(landings).has_size(1)
	assert_float(landings[0]).is_greater(3.0)
	assert_bool(_player.is_on_floor()).is_true()


func test_a_jump_let_go_early_is_a_hop() -> void:
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 3)
	InputSim.key(KEY_SPACE, false)
	var top := 0.0
	for _tick in TICKS:
		await get_tree().physics_frame
		top = maxf(top, _player.global_position.y)
	assert_float(top).is_less(_player.tuning.jump_height * 0.7)
	assert_float(top).is_greater(0.1)


func test_a_pad_button_jumps() -> void:
	InputSim.pad_button(JOY_BUTTON_A, true)
	await InputSim.ticks(get_tree(), 6)
	InputSim.pad_button(JOY_BUTTON_A, false)
	assert_float(_player.global_position.y).is_greater(0.15)
	assert_int(_player.state).is_equal(Player.State.JUMP)


func test_a_jump_is_still_allowed_a_moment_after_leaving_an_edge() -> void:
	_arena.add_block(Vector2(0.0, 2.0), Vector3(4.0, 2.0, 4.0), 1.0)
	_player.teleport(Vector3(0.0, 1.0, 0.2))
	await InputSim.ticks(get_tree(), 4)
	var jumps := [0]
	_player.jumped.connect(func() -> void: jumps[0] += 1)
	InputSim.key(KEY_W, true)
	for _tick in TICKS:
		await get_tree().physics_frame
		if not _player.is_on_floor():
			break
	assert_bool(_player.is_on_floor()).is_false()
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 3)
	assert_int(jumps[0]).is_equal(1)


func test_a_jump_pressed_just_before_landing_happens_on_landing() -> void:
	var jumps := [0]
	_player.jumped.connect(func() -> void: jumps[0] += 1)
	_player.teleport(Vector3(0.0, 0.4, 0.0))
	await InputSim.ticks(get_tree(), 5)
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_SPACE, false)
	await InputSim.ticks(get_tree(), 20)
	assert_int(jumps[0]).is_equal(1)


func test_it_steers_less_in_the_air_than_on_the_ground() -> void:
	_player.teleport(Vector3(0.0, 3.0, 0.0))
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_D, true)
	await InputSim.ticks(get_tree(), 5)
	var in_air := _player.velocity.x
	assert_bool(_player.is_on_floor()).is_false()
	InputSim.key(KEY_D, false)
	assert_float(in_air).is_greater(0.2)
	assert_float(in_air).is_less(_player.tuning.acceleration * 5.0 / 60.0 * 0.8)


func test_it_walks_up_a_low_step_and_stops_at_a_high_one() -> void:
	_arena.add_block(Vector2(0.0, -3.0), Vector3(4.0, 0.3, 1.0), 0.3)
	_arena.add_block(Vector2(8.0, -3.0), Vector3(4.0, 0.9, 1.0), 0.9)
	InputSim.key(KEY_W, true)
	var top := 0.0
	for _tick in TICKS:
		await get_tree().physics_frame
		top = maxf(top, _player.global_position.y)
	assert_float(top).is_equal_approx(0.3, 0.04)
	assert_float(_player.global_position.z).is_less(-3.6)
	InputSim.key(KEY_W, false)
	_player.teleport(Vector3(8.0, 0.0, 0.0))
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), TICKS)
	assert_float(_player.global_position.z).is_greater(-2.4)
	assert_float(_player.global_position.y).is_less(0.05)


func test_it_walks_up_a_slope_within_the_limit_and_not_one_past_it() -> void:
	var ramp := _arena.add_block(Vector2(0.0, -6.0), Vector3(4.0, 0.4, 10.0), 0.0)
	ramp.rotation_degrees.x = 30.0
	_player.teleport(Vector3(0.0, 0.0, -4.0))
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), TICKS * 2)
	assert_float(_player.global_position.y).is_greater(1.5)
	InputSim.key(KEY_W, false)
	_player.teleport(Vector3(20.0, 0.0, -4.0))
	var steep := _arena.add_block(Vector2(20.0, -6.0), Vector3(4.0, 0.4, 10.0), 0.0)
	steep.rotation_degrees.x = 62.0
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), TICKS * 2)
	assert_float(_player.global_position.y).is_less(0.8)


func test_a_moving_platform_carries_it_with_no_input() -> void:
	var platform := (
		load("res://gameplay/moving_platform/moving_platform.tscn").instantiate() as MovingPlatform
	)
	platform.travel = Vector3(0.0, 0.0, 6.0)
	platform.speed = 2.0
	platform.wait_time = 0.0
	platform.position = Vector3(10.0, 0.5, 0.0)
	_arena.add_child(platform)
	await InputSim.ticks(get_tree(), 2)
	_player.teleport(Vector3(10.0, 1.0, 0.0))
	await InputSim.ticks(get_tree(), 6)
	var start_z := _player.global_position.z
	await InputSim.ticks(get_tree(), 90)
	assert_bool(_player.is_on_floor()).is_true()
	assert_float(_player.global_position.z - start_z).is_equal_approx(3.0, 0.5)
	assert_float(_player.global_position.y).is_equal_approx(1.0, 0.05)
