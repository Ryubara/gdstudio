# Every number of the tuning is live (the ground, the jump and the air here; the world and the
# body in test_player_tuning_world.gd): each one is changed on a player that is already running (as
# the inspector and the remote inspector do) and its effect is read. The defaults are pinned too,
# so a new number fails here until it has both.
extends GdUnitTestSuite

const TICKS := 60
const TUNING := "res://gameplay/player/player_tuning.tres"

var _arena: PlayArena
var _player: Player
var _tuning: CharacterTuning


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	# A copy: the file is a cached resource that other suites read.
	_player.tuning = (load(TUNING) as CharacterTuning).duplicate()
	_tuning = _player.tuning
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func _apex(ticks: int) -> float:
	var top := 0.0
	for _tick in ticks:
		await get_tree().physics_frame
		top = maxf(top, _player.global_position.y)
	return top


func test_every_number_has_its_default_pinned() -> void:
	var pins := {
		&"walk_speed": 1.7,
		&"run_speed": 4.0,
		&"sprint_speed": 6.5,
		&"acceleration": 28.0,
		&"deceleration": 36.0,
		&"turn_speed": 12.0,
		&"walk_below_push": 0.45,
		&"least_walk_share": 0.5,
		&"run_above_walk": 0.35,
		&"jump_height": 1.25,
		&"jump_rise_time": 0.4,
		&"fall_gravity_scale": 1.35,
		&"terminal_speed": 40.0,
		&"short_jump_scale": 0.5,
		&"coyote_time": 0.12,
		&"jump_buffer_time": 0.14,
		&"air_control": 0.45,
		&"max_slope": 48.0,
		&"step_height": 0.32,
		&"snap_length": 0.35,
		&"step_probe_margin": 0.06,
		&"crouch_height": 1.1,
		&"crouch_speed": 1.5,
		&"crouch_time": 0.2,
		&"crouch_toggle": false,
		&"camera_height": 1.55,
		&"crouch_camera_height": 0.9,
		&"dead_camera_rise": 0.25,
		&"aim_move_scale": 0.6,
		&"aim_walk_cap": 1.5,
		&"aim_turn_speed": 18.0,
		&"aim_pose_time": 0.15,
		&"fire_buffer_time": 0.3,
		&"shot_aim_amount": 0.5,
		&"push_strength": 0.85,
		&"push_mass": 40.0,
		&"push_boost": 1.5,
		&"push_least_share": 0.15,
		&"push_contact": 1.15,
		&"push_hold": 0.25,
		&"interact_time": 0.7,
		&"interact_reach": 1.6,
		&"hit_stun_time": 0.45,
		&"knockback_speed": 5.0,
		&"land_clip_speed": 4.5,
		&"land_time": 0.3,
		&"stand_speed": 0.15,
		&"radius": 0.34,
		&"height": 1.8,
		&"fall_limit": -25.0,
	}
	var file := load(TUNING) as CharacterTuning
	assert_array(ExportPins.differences(file, pins)).is_empty()
	assert_array(ExportPins.wrong_values(file, pins)).is_empty()


func test_walk_run_and_sprint_speed_change_the_speed_at_once() -> void:
	InputSim.key(KEY_X, true)
	InputSim.key(KEY_W, true)
	_tuning.walk_speed = 3.0
	await _ticks(40)
	assert_float(_player.ground_speed()).is_equal_approx(3.0, 0.1)
	InputSim.key(KEY_X, false)
	_tuning.run_speed = 5.5
	await _ticks(40)
	assert_float(_player.ground_speed()).is_equal_approx(5.5, 0.1)
	InputSim.key(KEY_SHIFT, true)
	_tuning.sprint_speed = 8.0
	await _ticks(40)
	assert_float(_player.ground_speed()).is_equal_approx(8.0, 0.1)


func test_acceleration_sets_how_fast_it_gets_up_to_speed() -> void:
	_tuning.acceleration = 6.0
	InputSim.key(KEY_W, true)
	await _ticks(10)
	assert_float(_player.ground_speed()).is_equal_approx(1.0, 0.15)
	_tuning.acceleration = 80.0
	await _ticks(3)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.run_speed, 0.1)


func test_deceleration_sets_how_fast_it_stops() -> void:
	InputSim.key(KEY_W, true)
	await _ticks(40)
	InputSim.key(KEY_W, false)
	_tuning.deceleration = 6.0
	await _ticks(10)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.run_speed - 1.0, 0.15)


func test_turn_speed_sets_how_fast_it_faces_where_it_goes() -> void:
	_tuning.turn_speed = 1.0
	InputSim.key(KEY_D, true)
	await _ticks(6)
	var slow := absf(angle_difference(_player.facing, PI / 2.0))
	InputSim.key(KEY_D, false)
	_player.facing = PI
	_tuning.turn_speed = 40.0
	InputSim.key(KEY_D, true)
	await _ticks(6)
	var fast := absf(angle_difference(_player.facing, PI / 2.0))
	assert_float(slow).is_greater(1.0)
	assert_float(fast).is_less(0.3)


func test_jump_height_and_rise_time_change_the_jump_at_once() -> void:
	_tuning.jump_height = 2.0
	InputSim.key(KEY_SPACE, true)
	var top := await _apex(TICKS)
	assert_float(top).is_equal_approx(2.0, 0.15)
	InputSim.key(KEY_SPACE, false)
	await _ticks(TICKS)
	_tuning.jump_height = 1.0
	_tuning.jump_rise_time = 0.2
	InputSim.key(KEY_SPACE, true)
	var ticks_up := 0
	var last := _player.global_position.y
	for _tick in TICKS:
		await get_tree().physics_frame
		if _player.global_position.y > last:
			ticks_up += 1
		last = _player.global_position.y
		if _player.state == Player.State.FALL:
			break
	assert_int(ticks_up).is_less(18)
	assert_int(ticks_up).is_greater(8)


func test_fall_gravity_scale_makes_the_fall_heavier() -> void:
	_tuning.fall_gravity_scale = 1.0
	_player.teleport(Vector3(0.0, 8.0, 0.0))
	await _ticks(15)
	var plain := -_player.velocity.y
	_tuning.fall_gravity_scale = 2.0
	_player.teleport(Vector3(0.0, 8.0, 0.0))
	await _ticks(15)
	var heavy := -_player.velocity.y
	assert_float(heavy / plain).is_equal_approx(2.0, 0.2)


func test_terminal_speed_caps_the_fall() -> void:
	_tuning.terminal_speed = 3.0
	_player.teleport(Vector3(0.0, 20.0, 0.0))
	await _ticks(45)
	assert_float(-_player.velocity.y).is_equal_approx(3.0, 0.01)


func test_short_jump_scale_sets_how_small_a_tapped_jump_is() -> void:
	_tuning.short_jump_scale = 0.3
	InputSim.key(KEY_SPACE, true)
	await _ticks(3)
	InputSim.key(KEY_SPACE, false)
	var small := await _apex(TICKS)
	await _ticks(TICKS)
	_tuning.short_jump_scale = 0.9
	InputSim.key(KEY_SPACE, true)
	await _ticks(3)
	InputSim.key(KEY_SPACE, false)
	var bigger := await _apex(TICKS)
	assert_float(bigger).is_greater(small * 2.0)


func test_coyote_time_is_read_where_it_is_used() -> void:
	_tuning.coyote_time = 0.5
	await _ticks(2)
	assert_float(_player._coyote).is_equal_approx(0.5, 0.001)


func test_the_jump_buffer_is_read_where_it_is_used() -> void:
	_player.teleport(Vector3(0.0, 6.0, 0.0))
	await _ticks(20)
	_tuning.jump_buffer_time = 0.3
	InputSim.key(KEY_SPACE, true)
	await _ticks(2)
	assert_float(_player._jump_buffer).is_greater(0.2)
	InputSim.key(KEY_SPACE, false)


func test_air_control_sets_how_much_it_steers_in_the_air() -> void:
	_tuning.air_control = 0.0
	_player.teleport(Vector3(0.0, 3.0, 0.0))
	await _ticks(2)
	InputSim.key(KEY_D, true)
	await _ticks(5)
	assert_float(_player.velocity.x).is_equal_approx(0.0, 0.01)
	_tuning.air_control = 1.0
	await _ticks(3)
	assert_float(_player.velocity.x).is_greater(0.5)
