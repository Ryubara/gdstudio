# The lean tick (gdstudio #1059): a body whose controller asks for it (`lean_step`, an AI's) skips
# the modules that have nothing to do on a tick it only walks or stands, and ends every tick in
# exactly the state the full tick leaves: two bodies, one lean and one not, step one stream of
# commands that walks, climbs a kerb, runs, sprints, jumps, crouches, aims and fires, lies down,
# slides and stands, and their snapshots, capsules, spread and signals match on every tick. Only an
# AI's controller asks for it: the human's, the base controller and a server-stepped body do not.
extends GdUnitTestSuite

const BODY := "res://gameplay/character/character.tscn"
const PLAYER := "res://gameplay/player/player.tscn"
const AI := "res://gameplay/ai/ai_character.tscn"
const START_Z := 12.0

var _bodies: Array[Character] = []
var _signals: Array[Array] = [[], []]
var _differences: Array[String] = []
var _ticks := 0
var _lean_ticks := 0
var _lean_climbs := 0


func before_test() -> void:
	InputSim.release_all()
	_bodies.clear()
	_signals = [[], []]
	_differences.clear()
	_ticks = 0
	_lean_ticks = 0
	_lean_climbs = 0


# A body on a floor of its own world with a 0.2 m kerb across its way, facing -Z, stepped by hand.
func _body_in_a_world(lean: bool, index: int) -> Character:
	var world: SubViewport = auto_free(SubViewport.new())
	world.own_world_3d = true
	world.size = Vector2i(64, 64)
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(world)
	var arena := PlayArena.new()
	world.add_child(arena)
	arena.add_block(Vector2(0.0, START_Z - 3.0), Vector3(8.0, 0.2, 1.0), 0.2)
	var body := load(BODY).instantiate() as Character
	body.position = Vector3(0.0, 0.0, START_Z)
	var controller := CharacterController.new()
	controller.lean_step = lean
	body.add_child(controller)
	body.controller = controller
	arena.add_child(body)
	body.facing = PI
	body.set_physics_process(false)
	body.jumped.connect(_on_signal.bind(index, &"jumped"))
	for signal_name in [&"landed", &"state_changed", &"crouch_changed", &"aim_changed"]:
		body.connect(signal_name, _on_signal.bind(index, signal_name).unbind(1))
	return body


func _on_signal(index: int, signal_name: StringName) -> void:
	_signals[index].append("%d %s" % [_ticks, signal_name])


func _compare() -> void:
	var a := _bodies[0].state_snapshot()
	var b := _bodies[1].state_snapshot()
	var same := (
		a.position == b.position
		and a.velocity == b.velocity
		and a.values == b.values
		and a.weapon == b.weapon
		and a.vault == b.vault
		and a.loadout == b.loadout
		and a.prone == b.prone
		and a.slide == b.slide
		and _bodies[0].body_height() == _bodies[1].body_height()
		and _bodies[0].weapon.spread_share == _bodies[1].weapon.spread_share
	)
	if not same and _differences.size() < 5:
		_differences.append(
			(
				"tick %d: lean %s %s state %d / full %s %s state %d"
				% [
					_ticks,
					a.position,
					a.velocity,
					_bodies[0].state,
					b.position,
					b.velocity,
					_bodies[1].state
				]
			)
		)


func _run(command: PlayerCommand, count: int) -> void:
	for _tick in count:
		await get_tree().physics_frame
		_ticks += 1
		var lean := _bodies[0]
		# What the lean body decides this tick (`step` copies the command in the same way first).
		lean.last_command.copy_from(command)
		lean.last_command.move = command.move.limit_length(1.0)
		var took := lean.state != Character.State.DEAD and CharacterLean.can_take(lean)
		var height := lean.global_position.y
		for body in _bodies:
			body.step(command, CommandDriver.tick_seconds())
		if took:
			_lean_ticks += 1
			# The step climber lifted it on a lean tick (the kerb is 0.2 m).
			if lean.global_position.y - height > 0.1:
				_lean_climbs += 1
		command.clear_edges()
		_compare()


func test_the_lean_tick_ends_every_tick_where_the_full_tick_does() -> void:
	_bodies.append(_body_in_a_world(true, 0))
	_bodies.append(_body_in_a_world(false, 1))
	await InputSim.ticks(get_tree(), 4)
	await _run(PlayerCommand.new(), 10)
	var forward := CommandDriver.walking(Vector3.FORWARD)
	forward.walk = true
	# Over the kerb at a walk, then a run.
	await _run(forward, 90)
	forward.walk = false
	await _run(forward, 40)
	forward.sprint = true
	await _run(forward, 40)
	forward.sprint = false
	var aside := CommandDriver.walking(Vector3.RIGHT)
	await _run(aside, 30)
	aside.jump = true
	aside.jump_pressed = true
	await _run(aside, 20)
	aside.jump = false
	await _run(aside, 50)
	aside.crouch = true
	await _run(aside, 30)
	aside.crouch = false
	await _run(aside, 40)
	var aim := CommandDriver.walking(Vector3.ZERO, Vector3(4.0, 0.0, -6.0))
	aim.aim = true
	await _run(aim, 30)
	aim.fire = true
	aim.fire_pressed = true
	await _run(aim, 10)
	aim.fire = false
	aim.aim = false
	await _run(aim, 40)
	var lie := CommandDriver.walking(Vector3.BACK)
	lie.prone = true
	await _run(lie, 60)
	lie.prone = false
	await _run(lie, 80)
	var slide := CommandDriver.walking(Vector3.LEFT)
	slide.sprint = true
	await _run(slide, 40)
	slide.crouch = true
	await _run(slide, 30)
	slide.crouch = false
	slide.sprint = false
	await _run(slide, 40)
	var press := PlayerCommand.new()
	press.interact_pressed = true
	press.reload_pressed = true
	await _run(press, 40)

	assert_array(_differences).is_empty()
	assert_array(_signals[0]).is_equal(_signals[1])
	assert_int(_ticks).is_equal(720)
	# Both ticks were taken, each for a good share of the stream.
	assert_int(_lean_ticks).is_greater(300)
	assert_int(_ticks - _lean_ticks).is_greater(200)
	assert_int(_lean_climbs).is_greater_equal(1)


func test_only_an_ais_controller_asks_for_the_lean_tick() -> void:
	assert_bool(auto_free(CharacterController.new()).lean_step).is_false()
	var player: Player = auto_free(load(PLAYER).instantiate())
	assert_bool(player.controller.lean_step).is_false()
	var ai: AiCharacter = auto_free(load(AI).instantiate())
	assert_bool(ai.controller.lean_step).is_true()
	assert_bool(auto_free(AiController.new()).lean_step).is_true()


func test_the_ai_controller_gives_the_command_its_channels_say_on_every_call() -> void:
	var controller: AiController = auto_free(AiController.new())
	controller.walk_direction = Vector3.FORWARD
	var first := controller.sample().clone()
	# Unchanged channels: the same command again.
	var again := controller.sample()
	assert_vector(again.move).is_equal(first.move)
	assert_float(again.yaw).is_equal(first.yaw)
	# Each channel that changes is in the next command.
	controller.walk_strength = 0.5
	assert_float(controller.sample().move.length()).is_equal_approx(0.5, 0.0001)
	controller.walk_direction = Vector3.RIGHT
	var right := controller.sample()
	assert_vector(right.world_move()).is_equal_approx(Vector3.RIGHT * 0.5, Vector3.ONE * 0.0001)
	controller.look_direction = Vector3.LEFT
	assert_float(controller.sample().yaw).is_equal_approx(PI / 2.0, 0.0001)
	controller.aim = true
	assert_bool(controller.sample().aim).is_true()
	# A fire that starts is a press in exactly one command, then held.
	controller.fire = true
	var presses := 0
	for _call in 4:
		var command := controller.sample()
		assert_bool(command.fire).is_true()
		presses += 1 if command.fire_pressed else 0
	assert_int(presses).is_equal(1)
	controller.release()
	var still := controller.sample()
	assert_bool(still.fire or still.aim or still.fire_pressed).is_false()
	assert_vector(still.move).is_equal(Vector2.ZERO)
