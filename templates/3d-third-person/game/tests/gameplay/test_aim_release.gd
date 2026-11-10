# Nothing of aiming or firing outlasts the buttons: the frame after aim and fire are let go the
# character is back to its normal walk speed, turn and locomotion clips, whether it aimed, fired
# or both, standing or walking; only the arm lowers over `aim_pose_time`. Simulated input in the
# real physics world.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _animation: PlayerAnimation
var _camera: Camera3D
var _tuning: PlayerTuning


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_tuning = _player.tuning
	_animation = _player.get_node("Animation")
	# A camera 3 m behind the character looking along -Z, at the height of its hands.
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _aim(held: bool) -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, held)


func _fire(held: bool) -> void:
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, held)


func _shots() -> Array[Projectile]:
	var shots: Array[Projectile] = []
	_player.weapon.fired.connect(func(shot: Projectile) -> void: shots.append(shot))
	return shots


# Lets go of everything and waits for the next physics frame only.
func _release_all() -> void:
	InputSim.release_all()
	await get_tree().physics_frame


func _assert_normal_move() -> void:
	assert_bool(_player.aiming).is_false()
	assert_bool(_player.aim_held).is_false()
	assert_bool(_player.fire_held).is_false()
	assert_float(_player._target_speed(1.0)).is_equal(_tuning.run_speed)
	assert_float(_player._target_speed(0.3)).is_equal(_tuning.walk_speed * 0.5)


func test_aim_then_fire_then_letting_go_of_both_is_normal_on_the_next_frame() -> void:
	var changes: Array[bool] = []
	_player.aim_changed.connect(func(now: bool) -> void: changes.append(now))
	var shots := _shots()
	_aim(true)
	await InputSim.ticks(get_tree(), 20)
	_fire(true)
	await InputSim.ticks(get_tree(), 20)
	assert_array(shots).has_size(1)
	assert_bool(_player.aiming).is_true()
	assert_float(_player._target_speed(1.0)).is_less(_tuning.run_speed)
	await _release_all()
	_assert_normal_move()
	assert_array(changes).is_equal([true, false])


func test_fire_alone_hip_fire_is_normal_on_the_next_frame() -> void:
	var shots := _shots()
	_fire(true)
	await InputSim.ticks(get_tree(), 30)
	assert_array(shots).has_size(1)
	assert_bool(_player.aiming).is_true()
	assert_bool(_player.aim_held).is_false()
	await _release_all()
	_assert_normal_move()


func test_letting_go_of_aim_with_fire_still_held_stays_aiming_until_fire_is_let_go() -> void:
	_aim(true)
	_fire(true)
	await InputSim.ticks(get_tree(), 20)
	_aim(false)
	await get_tree().physics_frame
	assert_bool(_player.aiming).is_true()
	_fire(false)
	await get_tree().physics_frame
	_assert_normal_move()


func test_walking_aim_fire_release_gets_the_normal_speed_back_at_once() -> void:
	var aim_speed := minf(_tuning.run_speed, _tuning.walk_speed * 1.5) * _tuning.aim_move_scale
	InputSim.key(KEY_W, true)
	_aim(true)
	await InputSim.ticks(get_tree(), 30)
	_fire(true)
	await InputSim.ticks(get_tree(), 20)
	assert_float(_player.ground_speed()).is_equal_approx(aim_speed, 0.1)
	await _release_all()
	_assert_normal_move()
	# W is let go too; hold it again: it accelerates to the run speed, not to the aim walk.
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 20)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.run_speed, 0.1)


func test_walking_on_through_the_release_speeds_up_and_the_body_plays_the_normal_clip() -> void:
	InputSim.key(KEY_W, true)
	_aim(true)
	_fire(true)
	await InputSim.ticks(get_tree(), 40)
	assert_str(String(_animation.body_state())).is_equal("ground")
	_aim(false)
	_fire(false)
	var aimed_speed := _player.ground_speed()
	await InputSim.ticks(get_tree(), 6)
	assert_float(_player.ground_speed()).is_greater(aimed_speed + 0.5)
	await InputSim.ticks(get_tree(), 10)
	assert_int(_player.state).is_equal(Player.State.RUN)
	assert_str(String(_animation.body_state())).is_equal("ground")
	assert_bool(_animation.is_acting()).is_false()


func test_the_body_turns_back_to_the_walk_heading_on_the_next_frame() -> void:
	_camera.rotation.y = deg_to_rad(90.0)  # looks along -X
	_aim(true)
	_fire(true)
	await InputSim.ticks(get_tree(), 30)
	var aimed := _player.facing
	await _release_all()
	# Walking back (S is toward the camera, +X here) turns toward the walk, not the camera.
	InputSim.key(KEY_S, true)
	await InputSim.ticks(get_tree(), 20)
	assert_float(absf(angle_difference(_player.facing, aimed))).is_greater(1.0)


func test_only_the_arm_lowers_after_the_release_over_the_aim_pose_time() -> void:
	_aim(true)
	_fire(true)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_player.aim_amount).is_equal(1.0)
	await _release_all()
	_assert_normal_move()
	var amounts: Array[float] = [_player.aim_amount]
	var frames := int(ceil(_tuning.aim_pose_time * Engine.physics_ticks_per_second)) + 1
	for _frame in frames:
		await get_tree().physics_frame
		amounts.append(_player.aim_amount)
	assert_float(amounts[0]).is_less(1.0)
	for index in range(1, amounts.size()):
		assert_float(amounts[index]).is_less_equal(amounts[index - 1])
	assert_float(_player.aim_amount).is_equal(0.0)
	assert_float(_animation.pistol_weights().y).is_equal_approx(0.0, 0.05)


func test_a_short_click_still_shoots_once_and_leaves_nothing_behind() -> void:
	var shots := _shots()
	_fire(true)
	await InputSim.ticks(get_tree(), 8)
	_fire(false)
	await InputSim.ticks(get_tree(), 3)
	assert_array(shots).has_size(1)
	_assert_normal_move()
