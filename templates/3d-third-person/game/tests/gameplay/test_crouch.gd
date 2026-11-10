# Crouching, through simulated input in the real physics world: the capsule and the camera's target
# go down, the character walks slower, keeps crouched under a low ceiling and stands up when it has
# room. The numbers are in the Crouch group of the tuning (their live changes are in
# test_crouch_tuning.gd).
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _tuning: PlayerTuning


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_tuning = _player.tuning
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _capsule() -> CapsuleShape3D:
	return (_player.get_node("%Body") as CollisionShape3D).shape as CapsuleShape3D


func test_holding_crouch_lowers_the_capsule_and_the_camera_target() -> void:
	var target := _player.get_node("%CameraTarget") as Node3D
	assert_float(_capsule().height).is_equal_approx(1.8, 0.001)
	assert_float(target.position.y).is_equal_approx(1.55, 0.001)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.crouching).is_true()
	assert_int(_player.state).is_equal(Player.State.CROUCH)
	assert_float(_capsule().height).is_equal_approx(_tuning.crouch_height, 0.001)
	assert_float(target.position.y).is_equal_approx(_tuning.crouch_camera_height, 0.001)
	# The feet stay on the ground: the capsule's bottom is at the character's origin.
	var body := _player.get_node("%Body") as CollisionShape3D
	assert_float(body.position.y - _capsule().height / 2.0).is_equal_approx(0.0, 0.001)


func test_the_pad_crouches_too() -> void:
	InputSim.pad_button(JOY_BUTTON_B, true)
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_player.crouching).is_true()
	InputSim.pad_button(JOY_BUTTON_B, false)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.crouching).is_false()


# Ctrl is left free: the editor's embedded game window takes Ctrl+W as its own
# shortcut, so a W pressed while crouching on Ctrl never reached the game.
func test_the_control_key_does_not_crouch() -> void:
	InputSim.key(KEY_CTRL, true)
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_player.crouching).is_false()


func test_it_stands_up_when_the_button_is_let_go_and_there_is_room() -> void:
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 30)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.crouching).is_false()
	assert_float(_capsule().height).is_equal_approx(1.8, 0.001)
	assert_int(_player.state).is_equal(Player.State.IDLE)


func test_a_crouch_walk_is_slower_and_plays_the_crouch_state() -> void:
	InputSim.key(KEY_C, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.crouch_speed, 0.05)
	assert_int(_player.state).is_equal(Player.State.CROUCH)
	var animation := _player.get_node("Animation") as PlayerAnimation
	assert_str(String(animation.body_state())).is_equal("crouch")


func test_sprint_does_not_work_while_crouched_and_the_jump_stays_down() -> void:
	InputSim.key(KEY_C, true)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_player.ground_speed()).is_less(_tuning.crouch_speed + 0.1)
	assert_bool(_player.is_sprinting()).is_false()
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 20)
	assert_float(_player.global_position.y).is_less(0.05)


func test_letting_go_under_a_low_ceiling_keeps_it_crouched_until_it_walks_out() -> void:
	# A slab 4 m square whose underside is 1.3 m up, centred on the character.
	_arena.add_block(Vector2.ZERO, Vector3(4.0, 0.4, 4.0), 1.7)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 30)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_player.has_room_to_stand()).is_false()
	assert_bool(_player.crouching).is_true()
	assert_float(_capsule().height).is_equal_approx(_tuning.crouch_height, 0.001)
	# Walking out from under the slab (its edge is 2 m ahead) stands the character up.
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 150)
	InputSim.key(KEY_W, false)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_player.global_position.z).is_less(-2.3)
	assert_bool(_player.crouching).is_false()
	assert_float(_capsule().height).is_equal_approx(1.8, 0.001)


func test_a_tunnel_too_low_to_stand_in_is_crouch_walked_through() -> void:
	# 3 m of ceiling at 1.25 m, from z = -1 to z = -4.
	_arena.add_block(Vector2(0.0, -2.5), Vector3(3.0, 0.4, 3.0), 1.25 + 0.4)
	_player.teleport(Vector3(0.0, 0.0, 1.0))
	InputSim.key(KEY_C, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 280)
	assert_float(_player.global_position.z).is_less(-4.5)
	assert_bool(_player.crouching).is_true()


func test_a_standing_character_cannot_enter_a_tunnel_that_low() -> void:
	_arena.add_block(Vector2(0.0, -2.5), Vector3(3.0, 0.4, 3.0), 1.25 + 0.4)
	_player.teleport(Vector3(0.0, 0.0, 1.0))
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 120)
	assert_float(_player.global_position.z).is_greater(-1.0)


func test_toggle_mode_switches_crouch_on_and_off_with_a_press() -> void:
	_tuning.crouch_toggle = true
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.crouching).is_true()
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.crouching).is_false()


func test_it_says_when_it_crouches_and_stands() -> void:
	var changes: Array[bool] = []
	_player.crouch_changed.connect(func(now: bool) -> void: changes.append(now))
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 10)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 10)
	assert_array(changes).is_equal([true, false])
