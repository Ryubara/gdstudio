# One stream of commands steps two characters in two worlds of their own, one with a camera that
# looks somewhere else and one with no camera at all: the bodies are in the same place, move at
# the same speed and are in the same state on every tick. A body that read a key or a camera
# would differ between the two. Nothing is pressed: the commands are the only input. The stream
# ends with a shot at a target, which falls in both worlds on the same tick: the aim is the
# command's too.
extends GdUnitTestSuite

const TARGET := "res://gameplay/target/target.tscn"
const START_Z := 12.0

var _worlds: Array[SubViewport] = []
var _players: Array[Player] = []
var _shots: Array[int] = [0, 0]
var _differences: Array[String] = []
var _ticks := 0
var _boards: Array[Target] = []
var _dropped_on: Array[int] = [-1, -1]


func before_test() -> void:
	InputSim.release_all()
	_worlds.clear()
	_players.clear()
	_differences.clear()
	_shots = [0, 0]
	_ticks = 0
	_boards.clear()
	_dropped_on = [-1, -1]
	for index in 2:
		var world: SubViewport = auto_free(SubViewport.new())
		world.own_world_3d = true
		world.size = Vector2i(64, 64)
		world.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(world)
		var arena := PlayArena.new()
		world.add_child(arena)
		# A slab whose underside is 1.3 m up, from z = -4 to z = -8: too low to stand under.
		arena.add_block(Vector2(0.0, -6.0), Vector3(4.0, 0.4, 4.0), 1.7)
		# The stream walks 35 m along -Z; the floor ends at z = -30.
		var player := arena.add_player(Vector3(0.0, 0.0, START_Z))
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


# Stands a target in each world, 8 m from the character along (1, 0, -1), facing it. Returns
# the way from the character's eye to the middle of the board.
func _stand_targets() -> Vector3:
	var look := Vector3.ZERO
	for index in 2:
		var player := _players[index]
		var way := Vector3(1.0, 0.0, -1.0).normalized()
		var board := load(TARGET).instantiate() as Target
		board.position = Vector3(player.position.x, 0.0, player.position.z) + way * 8.0
		board.rotation.y = atan2(-way.x, -way.z)
		board.reset_time = 0.0
		board.knocked_down.connect(func() -> void: _dropped_on[index] = _ticks)
		player.get_parent().add_child(board)
		_boards.append(board)
		var middle := board.position + Vector3.UP * (board.get_node("%Pivot") as Node3D).position.y
		look = middle - (player.position + (player.get_node("%CameraTarget") as Node3D).position)
	return look


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
	assert_float(_players[1].global_position.z).is_between(-8.0, -4.0)
	forward.crouch = false
	await _run(forward, 20)
	assert_bool(_players[1].crouching).is_true()
	await _run(forward, 220)
	assert_bool(_players[1].crouching).is_false()
	# Stand, aim to the side, at a target, and shoot.
	await _run(PlayerCommand.new(), 20)
	# Still on the floor: a body that walked off the arena would shoot while it fell.
	assert_bool(_players[0].is_on_floor() and _players[1].is_on_floor()).is_true()
	var look := _stand_targets()
	var aim := CommandDriver.walking(Vector3.ZERO, look)
	aim.aim = true
	await _run(aim, 30)
	aim.fire = true
	aim.fire_pressed = true
	await _run(aim, 10)
	aim.fire = false
	aim.fire_pressed = false
	await _run(aim, 20)
	# Walk aside while aiming, then let go of everything.
	var strafe := CommandDriver.walking(Vector3.RIGHT, look)
	strafe.aim = true
	await _run(strafe, 40)
	await _run(PlayerCommand.new(), 30)

	assert_array(_differences).is_empty()
	assert_int(_ticks).is_equal(800)
	# The stream did what it says: every part of it happened.
	assert_int(jumps[0]).is_equal(1)
	assert_int(_shots[1]).is_equal(1)
	# The shot dropped the target, with and without a camera, on the same tick.
	assert_bool(_boards[0].is_down() and _boards[1].is_down()).is_true()
	assert_int(_dropped_on[1]).is_greater(0)
	assert_int(_dropped_on[0]).is_equal(_dropped_on[1])
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
	assert_float(_players[1].global_position.z).is_less(-8.0)
	# Aiming turned the body to the view: (1, y, -1) is a facing of 135 degrees.
	(
		assert_float(rad_to_deg(angle_difference(_players[1].facing, deg_to_rad(135.0))))
		. is_equal_approx(0.0, 1.0)
	)
