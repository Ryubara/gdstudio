# `Player.step(command, delta)`, the one door a body is moved through: what it does with a
# command that is hostile or repeated, what it leaves to its owner (where to start again after a
# fall) and that it needs no model. The bodies here are stepped by hand, with no input at all.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _players: Array[Player] = []


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	CommandDriver.take(_player)
	_players = [_player]
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _run(command: PlayerCommand, count: int) -> void:
	await CommandDriver.run(get_tree(), _players, command, count)


func test_a_command_walks_the_body_where_its_view_and_push_say() -> void:
	var command := PlayerCommand.new()
	command.yaw = deg_to_rad(90.0)  # Looking along -X.
	command.move = Vector2(0.0, 1.0)
	await _run(command, 60)
	assert_float(_player.global_position.x).is_less(-2.0)
	assert_float(absf(_player.global_position.z)).is_less(0.05)
	assert_int(_player.state).is_equal(Player.State.RUN)
	# The command it used is kept, and where it looked.
	assert_vector(_player.last_command.move).is_equal(Vector2(0.0, 1.0))
	assert_float(_player.view_yaw).is_equal(deg_to_rad(90.0))


func test_a_number_that_is_not_finite_is_stepped_as_asking_for_nothing() -> void:
	var command := CommandDriver.walking(Vector3.FORWARD)
	command.yaw = NAN
	command.aim = true
	command.jump_pressed = true
	await _run(command, 20)
	assert_bool(is_finite(_player.facing)).is_true()
	assert_bool(_player.global_position.is_finite()).is_true()
	assert_float(_player.global_position.length()).is_less(0.05)
	assert_bool(_player.aiming).is_false()
	command.yaw = 0.0
	command.move = Vector2(INF, 0.0)
	await _run(command, 20)
	assert_float(_player.global_position.length()).is_less(0.05)


func test_a_push_longer_than_one_is_no_faster_than_one() -> void:
	var command := PlayerCommand.new()
	command.move = Vector2(1.0, 1.0) * 5.0
	await _run(command, 90)
	assert_float(_player.ground_speed()).is_equal_approx(_player.tuning.run_speed, 0.01)
	assert_float(_player.last_command.move.length()).is_equal_approx(1.0, 0.0001)


func test_thirty_repeats_of_a_command_with_its_presses_cleared_jump_once() -> void:
	var jumps: Array[int] = [0]
	_player.jumped.connect(func() -> void: jumps[0] += 1)
	var command := PlayerCommand.new()
	command.jump = true
	command.jump_pressed = true
	# `CommandDriver.run` steps the presses once and clears them, as whoever repeats a command.
	await _run(command, 30)
	await _run(PlayerCommand.new(), 60)
	assert_int(jumps[0]).is_equal(1)
	# The presses kept on every repeat: the body jumps again as soon as it lands.
	for tick in 150:
		await get_tree().physics_frame
		_player.step(command, CommandDriver.tick_seconds())
	assert_int(jumps[0]).is_greater(2)


func test_clear_edges_and_merge_keep_a_press_exactly_once() -> void:
	var first := PlayerCommand.new()
	first.jump_pressed = true
	first.interact_pressed = true
	first.has_shot = true
	first.origin = Vector3(1.0, 2.0, 3.0)
	first.shot_yaw = 0.5
	var second := PlayerCommand.new()
	second.fire_pressed = true
	second.move = Vector2(0.0, 1.0)
	second.merge_edges_from(first)
	assert_bool(second.jump_pressed and second.interact_pressed and second.fire_pressed).is_true()
	assert_bool(second.ragdoll_pressed).is_false()
	assert_bool(second.has_shot).is_true()
	assert_vector(second.origin).is_equal(Vector3(1.0, 2.0, 3.0))
	second.sprint = true
	second.yaw = 1.0
	second.clear_edges()
	assert_bool(second.jump_pressed or second.interact_pressed or second.fire_pressed).is_false()
	assert_bool(second.has_shot).is_false()
	assert_vector(second.origin).is_equal(Vector3.ZERO)
	# What is held stays.
	assert_bool(second.sprint).is_true()
	assert_vector(second.move).is_equal(Vector2(0.0, 1.0))
	assert_float(second.yaw).is_equal(1.0)


func test_a_copy_has_every_field_and_clear_keeps_only_the_view() -> void:
	var command := PlayerCommand.new()
	var number := 1
	for property in command.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		number += 1
		match property["type"]:
			TYPE_BOOL:
				command.set(property["name"], true)
			TYPE_INT:
				command.set(property["name"], number)
			TYPE_FLOAT:
				command.set(property["name"], number * 0.01)
			TYPE_VECTOR2:
				command.set(property["name"], Vector2(number, -number) * 0.01)
			TYPE_VECTOR3:
				command.set(property["name"], Vector3(number, 2.0, -number))
	var copy := command.clone()
	var fields := 0
	for property in command.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			fields += 1
			(
				assert_that(copy.get(property["name"]))
				. override_failure_message(property["name"])
				. is_equal(command.get(property["name"]))
			)
	assert_int(fields).is_equal(20)
	copy.clear()
	assert_float(copy.yaw).is_equal(command.yaw)
	assert_float(copy.pitch).is_equal(command.pitch)
	assert_vector(copy.move).is_equal(Vector2.ZERO)
	assert_bool(copy.sprint or copy.aim or copy.fire or copy.jump or copy.crouch).is_false()
	assert_bool(copy.prone).is_false()
	assert_bool(copy.walk or copy.has_shot or copy.jump_pressed).is_false()


func test_a_world_direction_and_a_look_make_the_view_and_the_push() -> void:
	var command := PlayerCommand.new()
	for step in 8:
		var walk := Vector3.FORWARD.rotated(Vector3.UP, step * TAU / 8.0 + 0.2)
		for look: Vector3 in [Vector3.ZERO, Vector3(1.0, 0.5, 0.3), Vector3(-2.0, -1.0, 4.0)]:
			command.set_from_world(walk * 3.0, look, 0.5)
			assert_vector(command.world_move()).is_equal_approx(walk * 0.5, Vector3.ONE * 0.0001)
			if look != Vector3.ZERO:
				var seen := CommandDriver.walking(Vector3.ZERO, look)
				var ray := CommandCodec.direction_from_angles(seen.yaw, seen.pitch)
				assert_vector(ray).is_equal_approx(look.normalized(), Vector3.ONE * 0.0001)
			else:
				assert_float(command.yaw).is_equal(0.0)
	command.set_from_world(Vector3.ZERO)
	assert_vector(command.move).is_equal(Vector2.ZERO)


func test_the_ragdoll_press_is_a_testing_aid_a_server_turns_off() -> void:
	var press := PlayerCommand.new()
	press.ragdoll_pressed = true
	_player.ragdoll_by_command = false
	await _run(press, 3)
	assert_bool(_player.is_dead()).is_false()
	_player.ragdoll_by_command = true
	await _run(press, 3)
	assert_bool(_player.is_dead()).is_true()
	await _run(press, 3)
	assert_bool(_player.is_dead()).is_false()


func test_a_fall_out_of_the_map_says_fell_once_and_the_owner_decides() -> void:
	var other := _arena.add_player(Vector3(4.0, 0.0, 0.0))
	CommandDriver.take(other)
	_players = [_player, other]
	# This test is the owner of both: neither starts again by itself.
	_player.fell.disconnect(_player.respawn)
	other.fell.disconnect(other.respawn)
	var falls: Array[int] = [0, 0]
	_player.fell.connect(func() -> void: falls[0] += 1)
	other.fell.connect(func() -> void: falls[1] += 1)
	await _run(PlayerCommand.new(), 4)
	var below := Vector3(0.0, _player.tuning.fall_limit - 1.0, 0.0)
	_player.teleport(below)
	await _run(PlayerCommand.new(), 30)
	assert_array(falls).is_equal([1, 0])
	# It waits where it is until it is put somewhere.
	assert_vector(_player.global_position).is_equal(below)
	_player.teleport(Vector3(0.0, 0.0, 2.0))
	await _run(PlayerCommand.new(), 30)
	assert_array(falls).is_equal([1, 0])
	assert_float(_player.global_position.y).is_between(-0.05, 0.05)
	_player.teleport(below)
	await _run(PlayerCommand.new(), 5)
	assert_array(falls).is_equal([2, 0])


func test_a_body_with_no_model_steps_turns_and_teleports() -> void:
	_player.model.queue_free()
	_player.model = null
	await _run(CommandDriver.walking(Vector3.RIGHT), 60)
	assert_float(_player.global_position.x).is_greater(2.0)
	assert_float(angle_difference(_player.facing, deg_to_rad(90.0))).is_equal_approx(0.0, 0.05)
	var look := CommandDriver.walking(Vector3.ZERO, Vector3.LEFT)
	look.aim = true
	await _run(look, 60)
	assert_float(angle_difference(_player.facing, deg_to_rad(-90.0))).is_equal_approx(0.0, 0.05)
	_player.teleport(Vector3(1.0, 0.0, 1.0), 0.5)
	assert_float(_player.facing).is_equal(0.5)


func test_a_body_nobody_controls_and_nobody_steps_still_stands_on_the_floor() -> void:
	var idle := _arena.add_player(Vector3(-4.0, 1.0, 0.0))
	idle.controller.queue_free()
	idle.controller = null
	await InputSim.ticks(get_tree(), 60)
	assert_float(idle.global_position.y).is_between(-0.05, 0.05)
	assert_int(idle.state).is_equal(Player.State.IDLE)


func test_holding_fire_stays_inside_the_up_budget() -> void:
	# What a client would send: a command a tick and two pings a second, each in a WebSocket
	# frame of 6 bytes, with the fire button held the whole time. The budget is 2 KB/s up.
	var frame := 6
	var rates: Dictionary[String, float] = {}
	for automatic: bool in [false, true]:
		var human := _arena.add_player(Vector3(0.0, 0.0, 6.0 if automatic else 3.0))
		human.weapon.automatic = automatic
		var camera := Camera3D.new()
		camera.position = Vector3(0.0, 1.3, 9.0)
		_arena.add_child(camera)
		camera.make_current()
		await InputSim.ticks(get_tree(), 4)
		InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
		var bytes := 0
		var seconds := 3
		for tick in seconds * NetLimits.TICK_RATE:
			await get_tree().physics_frame
			bytes += CommandCodec.encode(human.last_command).size() + frame
		InputSim.release_all()
		human.queue_free()
		camera.queue_free()
		await InputSim.ticks(get_tree(), 2)
		var rate := float(bytes) / seconds + NetLimits.PING_RATE * (NetWire.PING_SIZE + frame)
		rates["automatic" if automatic else "one shot a press"] = rate
		assert_float(rate).is_less(2000.0)
	print("up bytes a second with fire held: ", rates)
	# No shot block at all is 60 * (15 + 6) + 2 * 13 = 1286: the block rides on a few ticks a
	# shot, not on every tick the button is held (which would be 2006).
	assert_float(rates["one shot a press"]).is_less(1320.0)
	assert_float(rates["automatic"]).is_less(1400.0)


func test_the_step_takes_the_physics_step_as_its_delta() -> void:
	# The engine moves the body by its own step whatever number is passed, so `step` asserts
	# (in a debug build) that the two are one; this is the check it makes.
	await get_tree().physics_frame
	assert_bool(_player._is_physics_step(CommandDriver.tick_seconds())).is_true()
	assert_bool(_player._is_physics_step(CommandDriver.tick_seconds() / 2.0)).is_false()
	assert_bool(_player._is_physics_step(0.0)).is_false()
	assert_bool(_player._is_physics_step(1.0 / 30.0)).is_false()


# Every script of the character (`gameplay/character/`: the body, its model, animation, ragdoll,
# footsteps and the rest) and of the weapon reads no input and no camera: a server or an AI drives
# the same files. Only the human's `PlayerInput` (in `gameplay/player/`) reads them.
func test_the_character_and_its_weapon_read_no_input_and_no_camera() -> void:
	var reads := RegEx.new()
	reads.compile("\\bInput\\.|\\bget_camera_3d\\(|\\bget_viewport\\(")
	var found: Array[String] = []
	var sources: Array[String] = []
	for folder in ["res://gameplay/character", "res://gameplay/weapon"]:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".gd"):
				sources.append(folder + "/" + file)
	for needed in ["character/character.gd", "character/character_ragdoll.gd", "weapon/weapon.gd"]:
		assert_bool(sources.has("res://gameplay/" + needed)).is_true()
	for path in sources:
		var source := FileAccess.get_file_as_string(path)
		assert_int(source.length()).is_greater(100)
		var number := 0
		for line in source.split("\n"):
			number += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			if reads.search(code) != null:
				found.append("%s:%d: %s" % [path.get_file(), number, code])
	assert_array(found).is_empty()
