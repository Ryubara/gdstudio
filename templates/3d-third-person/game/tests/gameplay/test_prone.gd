# Prone and the crawl, through simulated input in the real physics world: the prone key and the
# pad lie the character down, the capsule and the camera's target go down, it crawls slowly,
# fits under a gap only a lying body fits, refuses to get up under it and gets up through
# crouch once there is room. The numbers are in `ProneTuning` (`prone_tuning.tres`).
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _prone: ProneTuning
var _tuning: CharacterTuning


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_player.prone_tuning = (
		(load("res://gameplay/player/prone_tuning.tres") as ProneTuning).duplicate()
	)
	_tuning = _player.tuning
	_prone = _player.prone_tuning
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _capsule() -> CapsuleShape3D:
	return (_player.get_node("%Body") as CollisionShape3D).shape as CapsuleShape3D


func _ticks(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 2


func _tap(code: Key) -> void:
	InputSim.key(code, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(code, false)
	await InputSim.ticks(get_tree(), 1)


func _lie_down() -> void:
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), _ticks(_prone.enter_time))


func test_the_prone_key_lies_down_lowering_the_capsule_and_the_camera_target() -> void:
	var target := _player.get_node("%CameraTarget") as Node3D
	await _lie_down()
	assert_bool(_player.prone).is_true()
	assert_float(_player.prone_amount).is_equal(1.0)
	assert_int(_player.state).is_equal(Player.State.PRONE)
	assert_float(_capsule().height).is_equal_approx(_prone.height, 0.001)
	assert_float(_capsule().radius).is_equal_approx(_prone.radius, 0.001)
	assert_float(target.position.y).is_equal_approx(_prone.camera_height, 0.001)
	# The feet stay on the ground: the capsule's bottom is at the character's origin.
	var body := _player.get_node("%Body") as CollisionShape3D
	assert_float(body.position.y - _capsule().height / 2.0).is_equal_approx(0.0, 0.001)
	assert_float(_player.global_position.y).is_less(0.05)


func test_going_down_takes_the_enter_time() -> void:
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), int(_prone.enter_time * Engine.physics_ticks_per_second / 2))
	assert_float(_player.prone_amount).is_between(0.2, 0.8)
	assert_float(_capsule().height).is_between(_prone.height + 0.05, _tuning.height - 0.05)


func test_the_pad_lies_down_and_gets_up_too() -> void:
	InputSim.pad_button(JOY_BUTTON_DPAD_DOWN, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.pad_button(JOY_BUTTON_DPAD_DOWN, false)
	await InputSim.ticks(get_tree(), _ticks(_prone.enter_time))
	assert_bool(_player.prone).is_true()
	InputSim.pad_button(JOY_BUTTON_DPAD_DOWN, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.pad_button(JOY_BUTTON_DPAD_DOWN, false)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time + _tuning.crouch_time))
	assert_bool(_player.prone).is_false()
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)


func test_a_crawl_is_slower_than_a_crouch_walk() -> void:
	await _lie_down()
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	assert_float(_player.ground_speed()).is_equal_approx(_prone.crawl_speed, 0.03)
	assert_float(_player.ground_speed()).is_less(_tuning.crouch_speed)
	assert_int(_player.state).is_equal(Player.State.PRONE)
	var animation := _player.get_node("Animation") as CharacterAnimation
	await get_tree().process_frame
	assert_str(String(animation.body_state())).is_equal("prone")


func test_it_does_not_crawl_while_it_goes_down() -> void:
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), int(_prone.enter_time * Engine.physics_ticks_per_second) - 4)
	assert_float(_player.ground_speed()).is_less(0.6)


func test_it_crawls_under_a_gap_only_a_lying_body_fits_and_refuses_to_get_up_there() -> void:
	# 3 m of slab whose underside is 0.8 m up, from z = -1 to z = -4: the crouched capsule
	# (1.1 m) does not fit, the lying one (0.6 m) does.
	_arena.add_block(Vector2(0.0, -2.5), Vector3(3.0, 0.4, 3.0), 0.8 + 0.4)
	_player.teleport(Vector3(0.0, 0.0, 0.5))
	await _lie_down()
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 120)
	InputSim.key(KEY_W, false)
	await InputSim.ticks(get_tree(), 20)
	assert_float(_player.global_position.z).is_between(-3.8, -1.2)
	# Asked to get up under the slab, it stays down.
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time))
	assert_bool(_player.prone).is_true()
	assert_float(_player.prone_amount).is_equal(1.0)
	assert_float(_capsule().height).is_equal_approx(_prone.height, 0.001)
	assert_float(_player.global_position.y).is_less(0.05)
	# Crawling out (prone is let go of, so it gets up as soon as there is room).
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 260)
	InputSim.key(KEY_W, false)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time + _tuning.crouch_time))
	assert_float(_player.global_position.z).is_less(-4.3)
	assert_bool(_player.prone).is_false()
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)


func test_standing_or_crouched_it_cannot_enter_that_gap() -> void:
	_arena.add_block(Vector2(0.0, -2.5), Vector3(3.0, 0.4, 3.0), 0.8 + 0.4)
	_player.teleport(Vector3(0.0, 0.0, 0.5))
	InputSim.key(KEY_C, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 120)
	assert_float(_player.global_position.z).is_greater(-1.0)


func test_getting_up_goes_through_crouch() -> void:
	await _lie_down()
	var states: Array[int] = []
	_player.state_changed.connect(func(now: Player.State) -> void: states.append(now))
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time + _tuning.crouch_time))
	assert_array(states).is_equal([Player.State.CROUCH, Player.State.IDLE])
	assert_bool(_player.crouching).is_false()


func test_getting_up_with_crouch_held_stays_crouched() -> void:
	await _lie_down()
	InputSim.key(KEY_C, true)
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time + _tuning.crouch_time))
	assert_bool(_player.prone).is_false()
	assert_bool(_player.crouching).is_true()
	assert_float(_capsule().height).is_equal_approx(_tuning.crouch_height, 0.001)


func test_hold_mode_lies_down_only_while_the_key_is_held() -> void:
	_prone.input_mode = ProneTuning.InputMode.HOLD
	InputSim.key(KEY_Z, true)
	await InputSim.ticks(get_tree(), _ticks(_prone.enter_time))
	assert_bool(_player.prone).is_true()
	InputSim.key(KEY_Z, false)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time))
	assert_bool(_player.prone).is_false()


func test_holding_crouch_lies_down_in_hold_crouch_mode_and_a_press_gets_up() -> void:
	_prone.input_mode = ProneTuning.InputMode.HOLD_CROUCH
	InputSim.pad_button(JOY_BUTTON_B, true)
	await InputSim.ticks(get_tree(), _ticks(_prone.crouch_hold_time * 0.5))
	assert_bool(_player.prone).is_false()
	assert_bool(_player.crouching).is_true()
	await InputSim.ticks(get_tree(), _ticks(_prone.crouch_hold_time * 0.5 + _prone.enter_time))
	assert_bool(_player.prone).is_true()
	InputSim.pad_button(JOY_BUTTON_B, false)
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_player.prone).is_true()
	InputSim.pad_button(JOY_BUTTON_B, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.pad_button(JOY_BUTTON_B, false)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time + _tuning.crouch_time))
	assert_bool(_player.prone).is_false()


func test_the_hold_of_crouch_does_nothing_in_toggle_mode() -> void:
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), _ticks(_prone.crouch_hold_time + _prone.enter_time))
	assert_bool(_player.prone).is_false()
	assert_bool(_player.crouching).is_true()


func test_a_jump_press_gets_up_instead_of_jumping() -> void:
	await _lie_down()
	var jumps: Array[int] = []
	_player.jumped.connect(func() -> void: jumps.append(1))
	await _tap(KEY_SPACE)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time + _tuning.crouch_time))
	assert_bool(_player.prone).is_false()
	assert_array(jumps).is_empty()


func test_a_live_change_of_the_lying_height_fits_the_capsule_at_once() -> void:
	await _lie_down()
	_prone.height = 0.7
	await InputSim.ticks(get_tree(), 1)
	assert_float(_capsule().height).is_equal_approx(0.7, 0.001)


func test_it_says_when_it_lies_down_and_gets_up() -> void:
	var changes: Array[bool] = []
	_player.prone_changed.connect(func(now: bool) -> void: changes.append(now))
	await _lie_down()
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time))
	assert_array(changes).is_equal([true, false])


func test_dying_lying_down_and_getting_up_again_stands() -> void:
	await _lie_down()
	_player.die()
	await InputSim.ticks(get_tree(), 4)
	_player.revive()
	await InputSim.ticks(get_tree(), _ticks(_tuning.crouch_time))
	assert_bool(_player.prone).is_false()
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)
