# Two characters in one world: the keys move, crouch, aim, shoot and kill only the one that has
# the player's input. Before the body was stepped by a command both read the same keys, so a
# second instance of `player.tscn` walked in step with the first and died with it.
#
# Written so that it also loads on a build without the command step (it names no new class), and
# fails there by what the bodies do.
extends GdUnitTestSuite

var _arena: PlayArena
var _human: Player
var _other: Player


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_human = _arena.add_player(Vector3(-3.0, 0.0, 0.0))
	_other = _arena.add_player(Vector3(3.0, 0.0, 0.0))
	# The second body has no input of its own: nobody controls it.
	var input := _other.get_node_or_null("PlayerInput")
	if input != null:
		_other.set(&"controller", null)
		input.free()
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.3, 4.0)
	_arena.add_child(camera)
	camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func test_the_move_keys_walk_only_the_character_with_the_input() -> void:
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	InputSim.key(KEY_W, false)
	assert_float(_human.global_position.z).is_less(-2.0)
	assert_float(_other.global_position.distance_to(Vector3(3.0, 0.0, 0.0))).is_less(0.05)
	assert_int(_other.state).is_equal(Player.State.IDLE)


func test_jump_and_crouch_are_the_humans_alone() -> void:
	var jumps: Array[int] = [0]
	_other.jumped.connect(func() -> void: jumps[0] += 1)
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 6)
	InputSim.key(KEY_SPACE, false)
	assert_float(_human.global_position.y).is_greater(0.1)
	assert_int(jumps[0]).is_equal(0)
	await InputSim.ticks(get_tree(), 60)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_human.crouching).is_true()
	assert_bool(_other.crouching).is_false()


func test_aim_and_fire_are_the_humans_alone() -> void:
	var shots: Array[int] = [0, 0]
	_human.weapon.fired.connect(func(_shot: Projectile) -> void: shots[0] += 1)
	_other.weapon.fired.connect(func(_shot: Projectile) -> void: shots[1] += 1)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_human.aiming).is_true()
	assert_bool(_other.aiming).is_false()
	assert_float(_other.aim_amount).is_equal(0.0)
	assert_int(shots[0]).is_equal(1)
	assert_int(shots[1]).is_equal(0)


func test_the_ragdoll_key_kills_only_the_character_with_the_input() -> void:
	InputSim.key(KEY_Y, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_Y, false)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_human.is_dead()).is_true()
	assert_bool(_other.is_dead()).is_false()
