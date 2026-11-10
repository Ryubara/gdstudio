# A character aims and shoots where its command looks, never where a camera does: a second
# character beside the human's camera drops its own target, and a character in a world with no
# camera at all drops one too. While the weapon read the viewport's camera, every character shot
# where the local player was looking.
#
# The first test is written so that it also loads on a build whose weapon still reads the camera,
# and fails there by where the shot lands (so the other two ask for `aim_ray` by name).
extends GdUnitTestSuite

const TARGET := "res://gameplay/target/target.tscn"

var _arena: PlayArena
var _players: Array[Player] = []


func before_test() -> void:
	InputSim.release_all()
	_players.clear()


func after_test() -> void:
	if _arena != null:
		AudioDrain.stop_all(_arena)


# A target `distance` metres from `spot` along `flat`, its board turned to face `spot`.
func _board(world: PlayArena, spot: Vector3, flat: Vector3, distance: float) -> Target:
	var board := load(TARGET).instantiate() as Target
	var way := Vector3(flat.x, 0.0, flat.z).normalized()
	board.position = Vector3(spot.x, 0.0, spot.z) + way * distance
	board.rotation.y = atan2(-way.x, -way.z)
	board.reset_time = 0.0
	world.add_child(board)
	return board


func _middle(board: Target) -> Vector3:
	return board.global_position + Vector3.UP * (board.get_node("%Pivot") as Node3D).position.y


func _eye(player: Player) -> Vector3:
	return (player.get_node("%CameraTarget") as Node3D).global_position


# Aims `player` at `point` for half a second, presses fire and lets the shot fly.
func _aim_and_fire(player: Player, point: Vector3) -> void:
	_players = [player]
	var command := CommandDriver.walking(Vector3.ZERO, point - _eye(player))
	command.aim = true
	await CommandDriver.run(get_tree(), _players, command, 30)
	command.fire = true
	command.fire_pressed = true
	await CommandDriver.run(get_tree(), _players, command, 10)
	command.fire = false
	command.fire_pressed = false
	await CommandDriver.run(get_tree(), _players, command, 50)


func test_a_second_character_hits_its_own_target_not_what_the_camera_looks_at() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	var human := _arena.add_player(Vector3(-3.0, 0.0, 0.0))
	var other := _arena.add_player(Vector3(3.0, 0.0, 0.0))
	CommandDriver.take(other)
	# The human's camera is behind the human and looks along -Z, at the human's target.
	var camera := Camera3D.new()
	camera.position = Vector3(-3.0, 1.3, 3.0)
	_arena.add_child(camera)
	camera.make_current()
	var humans := _board(_arena, human.global_position, Vector3.FORWARD, 10.0)
	# The other character's target is behind the camera's back, along +Z and to the side.
	var others := _board(_arena, other.global_position, Vector3(0.6, 0.0, 1.0), 9.0)
	await InputSim.ticks(get_tree(), 4)
	var shots: Array[int] = [0]
	other.weapon.fired.connect(func(_shot: Projectile) -> void: shots[0] += 1)

	await _aim_and_fire(other, _middle(others))

	assert_int(shots[0]).is_equal(1)
	assert_bool(others.is_down()).is_true()
	assert_bool(humans.is_down()).is_false()
	# The human did nothing: nobody pressed its buttons.
	assert_bool(human.aiming).is_false()


func test_in_a_world_with_no_camera_a_character_aims_along_its_command_and_hits() -> void:
	var world: SubViewport = auto_free(SubViewport.new())
	world.own_world_3d = true
	world.size = Vector2i(64, 64)
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(world)
	_arena = PlayArena.new()
	world.add_child(_arena)
	var player := _arena.add_player(Vector3.ZERO)
	CommandDriver.take(player)
	var high := _board(_arena, Vector3.ZERO, Vector3(-1.0, 0.0, -0.4), 8.0)
	high.position.y = 2.5
	await InputSim.ticks(get_tree(), 4)
	assert_object(world.get_camera_3d()).is_null()

	await _aim_and_fire(player, _middle(high))

	assert_bool(high.is_down()).is_true()
	# It looked up at the board: the view of the command is the character's, and the ray it aims
	# along starts at its eye.
	assert_float(player.view_pitch).is_greater(deg_to_rad(5.0))
	var ray: PackedVector3Array = player.call(&"aim_ray")
	assert_vector(ray[0]).is_equal_approx(_eye(player), Vector3.ONE * 0.0001)
	var want := CommandCodec.direction_from_angles(player.view_yaw, player.view_pitch)
	assert_vector(ray[1]).is_equal_approx(want, Vector3.ONE * 0.0001)


func test_a_shot_block_in_the_command_is_the_ray_and_wins_over_the_view() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	var player := _arena.add_player(Vector3.ZERO)
	CommandDriver.take(player)
	_players = [player]
	var viewed := _board(_arena, Vector3.ZERO, Vector3.FORWARD, 10.0)
	var blocked := _board(_arena, Vector3(4.0, 0.0, 0.0), Vector3.FORWARD, 10.0)
	await InputSim.ticks(get_tree(), 4)
	# The view looks at one board; the shot block (a crosshair's ray, as a camera over the
	# shoulder would send it) starts 1 m to the side and behind and points at the other.
	var command := CommandDriver.walking(Vector3.ZERO, _middle(viewed) - _eye(player))
	command.aim = true
	await CommandDriver.run(get_tree(), _players, command, 30)
	var start := Vector3(1.0, 1.6, 2.5)
	var angles := CommandCodec.direction_angles(_middle(blocked) - start)
	command.fire = true
	command.fire_pressed = true
	for tick in 10:
		# A press is stepped once; the block rides on every tick a shot may leave.
		command.has_shot = true
		command.origin = start
		command.shot_yaw = angles.x
		command.shot_pitch = angles.y
		await CommandDriver.run(get_tree(), _players, command, 1)
		command.clear_edges()
	var ray: PackedVector3Array = player.call(&"aim_ray")
	assert_vector(ray[0]).is_equal(start)
	await CommandDriver.run(get_tree(), _players, command, 50)
	assert_bool(blocked.is_down()).is_true()
	assert_bool(viewed.is_down()).is_false()
