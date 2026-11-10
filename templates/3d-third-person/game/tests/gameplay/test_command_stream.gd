# One stream of commands steps two characters in two worlds of their own, one with a camera that
# looks somewhere else and one with no camera at all: the bodies are in the same place, move at
# the same speed and are in the same state on every tick. A body that read a key or a camera
# would differ between the two. Nothing is pressed: the commands are the only input.
extends GdUnitTestSuite

var _worlds: Array[SubViewport] = []
var _players: Array[Player] = []
var _shots: Array[int] = [0, 0]
var _differences: Array[String] = []
var _ticks := 0


func before_test() -> void:
	InputSim.release_all()
	_worlds.clear()
	_players.clear()
	_differences.clear()
	_shots = [0, 0]
	_ticks = 0
	for index in 2:
		var world: SubViewport = auto_free(SubViewport.new())
		world.own_world_3d = true
		world.size = Vector2i(64, 64)
		world.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(world)
		var arena := PlayArena.new()
		world.add_child(arena)
		# A slab whose underside is 1.3 m up, from z = -16 to z = -20: too low to stand under.
		arena.add_block(Vector2(0.0, -18.0), Vector3(4.0, 0.4, 4.0), 1.7)
		var player := arena.add_player(Vector3.ZERO)
		CommandDriver.take(player)
		player.weapon.fired.connect(func(_shot: Projectile) -> void: _shots[index] += 1)
		_worlds.append(world)
		_players.append(player)
	# Only the first world has a camera, and it looks along +X, across the way the stream walks.
	var camera := Camera3D.new()
	camera.position = Vector3(-4.0, 1.5, 0.0)
	camera.rotation.y = deg_to_rad(-90.0)
	_worlds[0].get_child(0).add_child(camera)
	camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	for world in _worlds:
		AudioDrain.stop_all(world)


func _compare(_tick: int) -> void:
	_ticks += 1
	var a := _players[0]
	var b := _players[1]
	var same := (
		a.global_position == b.global_position
		and a.velocity == b.velocity
		and a.state == b.state
		and a.facing == b.facing
		and a.crouching == b.crouching
		and a.aiming == b.aiming
		and a.aim_amount == b.aim_amount
		and _shots[0] == _shots[1]
	)
	if not same and _differences.size() < 5:
		(
			_differences
			. append(
				(
					"tick %d: %s %s state %d shots %d / %s %s state %d shots %d"
					% [
						_ticks,
						a.global_position,
						a.velocity,
						a.state,
						_shots[0],
						b.global_position,
						b.velocity,
						b.state,
						_shots[1],
					]
				)
			)
		)


func _run(command: PlayerCommand, count: int) -> void:
	await CommandDriver.run(get_tree(), _players, command, count, _compare)


func test_the_same_commands_give_the_same_body_with_and_without_a_camera() -> void:
	var seen: Dictionary[int, bool] = {}
	_players[1].state_changed.connect(func(state: Player.State) -> void: seen[state] = true)
	var jumps: Array[int] = [0]
	_players[1].jumped.connect(func() -> void: jumps[0] += 1)
	var forward := CommandDriver.walking(Vector3.FORWARD)
	# Walk, then sprint.
	forward.walk = true
	await _run(forward, 40)
	forward.walk = false
	await _run(forward, 40)
	forward.sprint = true
	await _run(forward, 50)
	assert_bool(_players[1].is_sprinting()).is_true()
	forward.sprint = false
	# A full jump while running.
	forward.jump = true
	forward.jump_pressed = true
	await _run(forward, 30)
	forward.jump = false
	await _run(forward, 50)
	# Crouch, walk under the slab, let go under it (it stays down), walk out and stand.
	forward.crouch = true
	await _run(forward, 200)
	assert_float(_players[1].global_position.z).is_between(-20.0, -16.0)
	forward.crouch = false
	await _run(forward, 20)
	assert_bool(_players[1].crouching).is_true()
	await _run(forward, 220)
	assert_bool(_players[1].crouching).is_false()
	# Stand, aim to the side and shoot.
	var aim := CommandDriver.walking(Vector3.ZERO, Vector3(1.0, 0.2, -1.0))
	aim.aim = true
	await _run(aim, 30)
	aim.fire = true
	aim.fire_pressed = true
	await _run(aim, 10)
	aim.fire = false
	await _run(aim, 20)
	# Walk aside while aiming, then let go of everything.
	var strafe := CommandDriver.walking(Vector3.RIGHT, Vector3(1.0, 0.2, -1.0))
	strafe.aim = true
	await _run(strafe, 40)
	await _run(PlayerCommand.new(), 30)

	assert_array(_differences).is_empty()
	assert_int(_ticks).is_equal(780)
	# The stream did what it says: every part of it happened.
	assert_int(jumps[0]).is_equal(1)
	assert_int(_shots[1]).is_equal(1)
	for state: int in [
		Player.State.WALK,
		Player.State.RUN,
		Player.State.JUMP,
		Player.State.FALL,
		Player.State.CROUCH
	]:
		(
			assert_bool(seen.has(state))
			. override_failure_message("state %d never seen" % state)
			. is_true()
		)
	assert_float(_players[1].global_position.z).is_less(-20.0)
	# Aiming turned the body to the view: (1, 0.2, -1) is a facing of 135 degrees.
	(
		assert_float(rad_to_deg(angle_difference(_players[1].facing, deg_to_rad(135.0))))
		. is_equal_approx(0.0, 1.0)
	)
