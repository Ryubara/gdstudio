# The Aim group of the tuning is live: each number is changed on a player that is already running
# and its effect is read (the aim itself is in test_aim.gd).
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _camera: Camera3D
var _tuning: PlayerTuning


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_tuning = _player.tuning
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func test_aim_move_scale_is_the_share_of_the_walk_kept_while_aiming() -> void:
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	InputSim.key(KEY_W, true)
	_tuning.aim_move_scale = 0.4
	await InputSim.ticks(get_tree(), 60)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.walk_speed * 1.5 * 0.4, 0.05)
	_tuning.aim_move_scale = 1.0
	await InputSim.ticks(get_tree(), 60)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.walk_speed * 1.5, 0.05)


func test_aim_turn_speed_is_how_fast_the_body_comes_round_to_the_camera() -> void:
	_camera.rotation.y = deg_to_rad(90.0)
	_tuning.aim_turn_speed = 2.0
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 30)
	# Half a second at 2 rad/s (less, as it eases): well short of the quarter turn it was asked.
	var model := _player.get_node("Model") as Node3D
	assert_float(absf(angle_difference(model.rotation.y, deg_to_rad(-90.0)))).is_greater(0.4)
	_tuning.aim_turn_speed = 40.0
	await InputSim.ticks(get_tree(), 20)
	assert_float(absf(angle_difference(model.rotation.y, deg_to_rad(-90.0)))).is_less(0.05)


func test_aim_pose_time_is_how_long_the_arm_takes_to_come_up() -> void:
	_tuning.aim_pose_time = 0.6
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 18)
	assert_float(_player.aim_amount).is_between(0.3, 0.7)
	_tuning.aim_pose_time = 0.05
	await InputSim.ticks(get_tree(), 6)
	assert_float(_player.aim_amount).is_equal(1.0)


func test_aim_hold_time_is_how_long_firing_keeps_the_aim_up() -> void:
	_tuning.aim_hold_time = 0.3
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await InputSim.ticks(get_tree(), 10)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_bool(_player.aiming).is_true()
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_player.aiming).is_true()
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.aiming).is_false()
	_tuning.aim_hold_time = 2.0
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await InputSim.ticks(get_tree(), 4)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await InputSim.ticks(get_tree(), 60)
	assert_bool(_player.aiming).is_true()
