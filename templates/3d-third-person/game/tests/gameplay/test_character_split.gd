# The character and the human are two things since #901: `Character` (`character.tscn`, the body
# alone, which a server loads, and `character_dressed.tscn`, the body with its model, animation,
# footsteps and ragdoll) and `Player` (`player.tscn`, the dressed character with the human's
# controller). The body alone and the dressed body step one stream of commands alike, shot
# included; a character driven by a scripted controller walks with no input and is not taken for
# the player; only the player is in the group the HUD, the minimap and a camera zone look for.
# Scenes are loaded by path and members read by name, so the suite also runs (and fails) on a
# tree without the split.
extends GdUnitTestSuite

const BODY := "res://gameplay/character/character.tscn"
const DRESSED := "res://gameplay/character/character_dressed.tscn"
const TARGET := "res://gameplay/target/target.tscn"
const ZONE := "res://gameplay/trigger_zone/trigger_zone.tscn"
const START_Z := 12.0

var _worlds: Array[SubViewport] = []
var _bodies: Array[Node3D] = []
var _shots: Array[Array] = [[], []]
var _differences: Array[String] = []
var _ticks := 0


func before_test() -> void:
	InputSim.release_all()
	_worlds.clear()
	_bodies.clear()
	_differences.clear()
	_shots = [[], []]
	_ticks = 0


func after_test() -> void:
	for world in _worlds:
		AudioDrain.stop_all(world)


# A character from `path` on a floor of its own world, facing -Z.
func _character_in_a_world(path: String, index: int) -> Node3D:
	var world: SubViewport = auto_free(SubViewport.new())
	world.own_world_3d = true
	world.size = Vector2i(64, 64)
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(world)
	var arena := PlayArena.new()
	world.add_child(arena)
	var scene := load(path) as PackedScene
	assert_object(scene).override_failure_message("no scene at " + path).is_not_null()
	var body := scene.instantiate() as Node3D
	body.position = Vector3(0.0, 0.0, START_Z)
	arena.add_child(body)
	body.set(&"facing", PI)
	body.set_physics_process(false)
	var weapon: Node = body.get(&"weapon")
	weapon.connect(&"fired", _on_fired.bind(index))
	_worlds.append(world)
	return body


func _on_fired(shot: Node3D, index: int) -> void:
	var flies: Vector3 = shot.get(&"velocity")
	_shots[index].append([shot.global_position, flies.normalized()])


func _compare() -> void:
	_ticks += 1
	var a := _bodies[0]
	var b := _bodies[1]
	var same: bool = (
		a.global_position == b.global_position
		and a.get(&"velocity") == b.get(&"velocity")
		and a.get(&"state") == b.get(&"state")
		and a.get(&"facing") == b.get(&"facing")
		and a.get(&"aim_amount") == b.get(&"aim_amount")
		and _shots[0].size() == _shots[1].size()
	)
	if not same and _differences.size() < 5:
		_differences.append(
			(
				"tick %d: %s state %d / %s state %d"
				% [_ticks, a.global_position, a.get(&"state"), b.global_position, b.get(&"state")]
			)
		)


func _run(command: PlayerCommand, count: int) -> void:
	for _tick in count:
		await get_tree().physics_frame
		for body in _bodies:
			body.call(&"step", command, CommandDriver.tick_seconds())
		command.clear_edges()
		_compare()


func test_the_body_alone_and_the_dressed_body_step_one_stream_alike() -> void:
	_bodies.append(_character_in_a_world(BODY, 0))
	_bodies.append(_character_in_a_world(DRESSED, 1))
	await InputSim.ticks(get_tree(), 4)
	var forward := CommandDriver.walking(Vector3.FORWARD)
	forward.walk = true
	await _run(forward, 40)
	forward.walk = false
	await _run(forward, 40)
	forward.sprint = true
	await _run(forward, 50)
	forward.sprint = false
	forward.jump = true
	forward.jump_pressed = true
	await _run(forward, 30)
	forward.jump = false
	await _run(forward, 50)
	forward.crouch = true
	await _run(forward, 40)
	await _run(PlayerCommand.new(), 30)
	# Still on the floor, so the shot below is a standing one.
	assert_bool(_bodies[0].call(&"is_on_floor") and _bodies[1].call(&"is_on_floor")).is_true()
	for index in 2:
		var board := load(TARGET).instantiate() as Node3D
		board.position = _bodies[index].position + Vector3(4.0, 0.0, -6.0)
		_bodies[index].get_parent().add_child(board)
	var aim := CommandDriver.walking(Vector3.ZERO, Vector3(4.0, 0.0, -6.0))
	aim.aim = true
	await _run(aim, 30)
	aim.fire = true
	aim.fire_pressed = true
	await _run(aim, 10)
	aim.fire = false
	await _run(aim, 20)
	await _run(PlayerCommand.new(), 30)

	assert_array(_differences).is_empty()
	assert_int(_ticks).is_equal(370)
	assert_int(_shots[0].size()).is_equal(1)
	assert_int(_shots[1].size()).is_equal(1)
	# The body alone fires from the weapon's `no_muzzle_offset`, the dressed one from the muzzle the
	# animation holds: the two starts are within that offset, and the shots fly the same way.
	var offset: Vector3 = _bodies[0].get(&"weapon").get(&"no_muzzle_offset")
	var gap: float = _shots[0][0][0].distance_to(_shots[1][0][0])
	var turn := rad_to_deg((_shots[0][0][1] as Vector3).angle_to(_shots[1][0][1]))
	assert_float(gap).is_less(offset.length())
	assert_float(turn).is_less(0.5)


func test_the_body_alone_has_no_model_and_still_shoots() -> void:
	var body := _character_in_a_world(BODY, 0)
	await InputSim.ticks(get_tree(), 2)
	for part in [^"Model", ^"AnimationPlayer", ^"AnimationTree", ^"Animation", ^"Ragdoll"]:
		assert_bool(body.has_node(part)).override_failure_message(str(part)).is_false()
	var weapon: Node = body.get(&"weapon")
	assert_object(weapon.get(&"muzzle")).is_null()
	assert_bool(weapon.call(&"can_fire")).is_true()


func test_a_character_walks_a_route_by_its_controller_with_no_input() -> void:
	var body := _character_in_a_world(DRESSED, 0)
	var route := RouteController.new()
	route.points = PackedVector3Array(
		[Vector3(0.0, 0.0, 9.0), Vector3(3.0, 0.0, 9.0), Vector3(3.0, 0.0, 12.0)]
	)
	body.add_child(route)
	body.set(&"controller", route)
	body.set_physics_process(true)
	for _tick in 600:
		await get_tree().physics_frame
		assert_bool(Input.is_anything_pressed()).is_false()
		if route.reached == route.points.size():
			break
	assert_int(route.reached).is_equal(3)
	var spot := body.global_position
	assert_float(Vector2(spot.x - 3.0, spot.z - 12.0).length()).is_less(0.5)
	assert_bool(body.is_in_group(&"player")).is_false()


func test_only_the_player_is_in_the_group_the_hud_and_zones_look_for() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3(-4.0, 0.0, 0.0))
	var character := (load(DRESSED) as PackedScene).instantiate() as Node3D
	character.position = Vector3(4.0, 0.0, 0.0)
	arena.add_child(character)
	await InputSim.ticks(get_tree(), 2)
	# The HUD's widgets and the minimap find the player by this group.
	assert_array(get_tree().get_nodes_in_group(&"player")).contains_exactly([player])
	assert_object(get_tree().get_first_node_in_group(&"player")).is_same(player)
	# A camera zone's trigger in the map counts only the group `player`.
	var zone := (load(ZONE) as PackedScene).instantiate() as TriggerZone
	arena.add_child(zone)
	zone.required_group = &"player"
	zone.call(&"_on_body_entered", character)
	assert_bool(zone.is_active()).is_false()
	zone.call(&"_on_body_entered", player)
	assert_bool(zone.is_active()).is_true()
