# Prone by commands alone, as a server, a bot or an AI drives it: a body with no input and no
# model lies down and crawls from the command's `prone` bit, its look is held to the prone
# limits, and a snapshot taken while it goes down puts it back on the same path.
extends GdUnitTestSuite

var _arena: PlayArena


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


# The body alone (what a server loads), stepped by whoever holds it.
func _bare_body(spot: Vector3) -> Character:
	var body := load("res://gameplay/character/character.tscn").instantiate() as Character
	body.position = spot
	_arena.add_child(body)
	body.set_physics_process(false)
	return body


func _run(body: Character, command: PlayerCommand, count: int, trace: Array = []) -> void:
	var stepped := command.clone()
	for tick in count:
		await get_tree().physics_frame
		body.step(stepped, CommandDriver.tick_seconds())
		stepped.clear_edges()
		trace.append(body.global_position)
		trace.append(body.velocity)


func _prone_walk(direction: Vector3) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.set_from_world(direction)
	command.prone = true
	return command


func test_a_body_with_no_input_or_model_lies_down_and_crawls_by_command() -> void:
	var body := _bare_body(Vector3.ZERO)
	await get_tree().physics_frame
	var still := PlayerCommand.new()
	still.prone = true
	await _run(body, still, 40)
	assert_bool(body.prone).is_true()
	assert_int(body.state).is_equal(Character.State.PRONE)
	assert_float(body.body_height()).is_equal_approx(body.prone_tuning.height, 0.001)
	await _run(body, _prone_walk(Vector3.RIGHT), 60)
	assert_float(body.ground_speed()).is_greater(body.prone_tuning.crawl_speed * 0.75)
	assert_float(body.ground_speed()).is_less(body.prone_tuning.crawl_speed + 0.01)
	await _run(body, PlayerCommand.new(), 80)
	assert_bool(body.prone).is_false()
	assert_float(body.body_height()).is_equal_approx(body.tuning.height, 0.001)


func test_the_look_is_held_to_the_prone_limits() -> void:
	var body := _bare_body(Vector3.ZERO)
	await get_tree().physics_frame
	var command := PlayerCommand.new()
	command.prone = true
	command.pitch = 1.2
	await _run(body, command, 40)
	assert_float(rad_to_deg(body.view_pitch)).is_equal_approx(body.prone_tuning.look_up_limit, 0.01)
	command.pitch = -1.2
	await _run(body, command, 2)
	assert_float(rad_to_deg(body.view_pitch)).is_equal_approx(
		-body.prone_tuning.look_down_limit, 0.01
	)
	var ray := body.aim_ray()
	assert_float(rad_to_deg(asin(ray[1].y))).is_equal_approx(
		-body.prone_tuning.look_down_limit, 0.01
	)
	# Standing, the same look is not held.
	command.prone = false
	await _run(body, command, 80)
	assert_float(body.view_pitch).is_equal_approx(-1.2, 0.0001)


func test_a_snapshot_taken_while_it_goes_down_puts_it_back_on_the_same_path() -> void:
	var body := _bare_body(Vector3.ZERO)
	await get_tree().physics_frame
	var command := _prone_walk(Vector3.FORWARD)
	await _run(body, command, 12)
	assert_bool(body.prone_amount > 0.0 and body.prone_amount < 1.0).is_true()
	var kept := body.state_snapshot()
	assert_array(kept.prone).has_size(3)
	var first: Array = []
	await _run(body, command, 90, first)
	body.restore(kept)
	var second: Array = []
	await _run(body, command, 90, second)
	assert_int(second.size()).is_equal(first.size())
	for index in first.size():
		assert_vector(second[index]).is_equal(first[index])


func test_two_bodies_lie_down_apart() -> void:
	var one := _bare_body(Vector3(-2.0, 0.0, 0.0))
	var two := _bare_body(Vector3(2.0, 0.0, 0.0))
	await get_tree().physics_frame
	var down := PlayerCommand.new()
	down.prone = true
	var up := PlayerCommand.new()
	for tick in 40:
		await get_tree().physics_frame
		one.step(down, CommandDriver.tick_seconds())
		two.step(up, CommandDriver.tick_seconds())
	assert_bool(one.prone).is_true()
	assert_bool(two.prone).is_false()


func test_a_prone_command_goes_over_the_wire() -> void:
	var command := PlayerCommand.new()
	command.prone = true
	var decoded := CommandCodec.decode(CommandCodec.encode(command))
	assert_object(decoded).is_not_null()
	assert_bool(decoded.prone).is_true()
	assert_bool(PlayerCommand.new().copy_from(command).prone).is_true()
	command.clear()
	assert_bool(command.prone).is_false()


# Every prone setting is pinned, with the default the research picked (the template docs give
# the sources), on a fresh resource and in the player's file.
func test_every_prone_setting_is_pinned() -> void:
	var pins := {
		&"crawl_speed": 1.0,
		&"backward_share": 0.7,
		&"sideways_share": 0.8,
		&"acceleration": 10.0,
		&"deceleration": 12.0,
		&"turn_speed": 3.0,
		&"move_while_changing": false,
		&"enter_time": 0.5,
		&"exit_time": 0.7,
		&"air_time": 0.15,
		&"height": 0.6,
		&"radius": 0.28,
		&"camera_height": 0.55,
		&"aim_allowed": true,
		&"fire_allowed": true,
		&"spread_share": 0.5,
		&"aim_move_share": 0.5,
		&"aim_turn_speed": 6.0,
		&"look_up_limit": 12.0,
		&"look_down_limit": 40.0,
		&"input_mode": ProneTuning.InputMode.TOGGLE,
		&"crouch_hold_time": 0.5,
		&"jump_gets_up": true,
		&"sprint_gets_up": true,
	}
	for tuning: ProneTuning in [
		ProneTuning.new(), load("res://gameplay/player/prone_tuning.tres") as ProneTuning
	]:
		assert_array(ExportPins.differences(tuning, pins)).is_empty()
		assert_array(ExportPins.wrong_values(tuning, pins)).is_empty()
