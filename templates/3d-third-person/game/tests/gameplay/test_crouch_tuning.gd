# The Crouch group of the tuning is live: each number is changed on a player that is already running
# (as the inspector and the remote inspector do) and its effect is read. The defaults are pinned in
# test_player_tuning_live.gd, the Aim numbers are read in test_aim_tuning.gd.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _tuning: CharacterTuning


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_tuning = _player.tuning
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _height() -> float:
	return ((_player.get_node("%Body") as CollisionShape3D).shape as CapsuleShape3D).height


func test_crouch_height_resizes_the_crouched_capsule_at_once() -> void:
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 30)
	_tuning.crouch_height = 0.9
	assert_float(_height()).is_equal_approx(0.9, 0.001)
	_tuning.crouch_height = 1.3
	assert_float(_height()).is_equal_approx(1.3, 0.001)


func test_crouch_speed_is_the_crouch_walking_speed() -> void:
	InputSim.key(KEY_C, true)
	InputSim.key(KEY_W, true)
	_tuning.crouch_speed = 0.8
	await InputSim.ticks(get_tree(), 40)
	assert_float(_player.ground_speed()).is_equal_approx(0.8, 0.05)
	_tuning.crouch_speed = 2.4
	await InputSim.ticks(get_tree(), 40)
	assert_float(_player.ground_speed()).is_equal_approx(2.4, 0.05)


func test_crouch_time_is_how_long_going_down_takes() -> void:
	_tuning.crouch_time = 0.6
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 18)
	# 0.3 s of 0.6 s: the capsule is part of the way.
	assert_float(_height()).is_between(1.15, 1.75)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_height()).is_equal_approx(_tuning.crouch_height, 0.001)
	_tuning.crouch_time = 0.0
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 3)
	assert_float(_height()).is_equal_approx(1.8, 0.001)


func test_the_camera_heights_move_the_target_standing_and_crouched() -> void:
	var target := _player.get_node("%CameraTarget") as Node3D
	_tuning.camera_height = 1.7
	assert_float(target.position.y).is_equal_approx(1.7, 0.001)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 30)
	_tuning.crouch_camera_height = 0.7
	assert_float(target.position.y).is_equal_approx(0.7, 0.001)


func test_crouch_toggle_changes_how_the_button_works_at_once() -> void:
	_tuning.crouch_toggle = true
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_player.crouching).is_true()
	_tuning.crouch_toggle = false
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.crouching).is_false()
