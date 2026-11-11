# The `AiNavigator` when the way is not what the mesh says (`NavArena`): the stuck ladder (a
# sidestep round a block it did not know of; against one it cannot pass, every rung, the goal
# dropped and a report, nobody moved by hand), a wall the mesh runs through found by the body-ray
# check, a door that shuts mid-walk and opens again, a locked one that blocks, and a link crossed
# by the body or left to a task.
extends GdUnitTestSuite

var _arena: NavArena


func before_test() -> void:
	_arena = auto_free(NavArena.new())
	add_child(_arena)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _ready_arena() -> void:
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()


# A block the mesh does not know of and the body-ray check passes (it may move): the stuck watch
# sees it, the sidestep takes the body round it.
func test_a_sidestep_takes_it_round_a_block_it_did_not_know_of() -> void:
	await _ready_arena()
	var block := _frozen_box(Vector3(0, 1, 0), Vector3(1.4, 2, 1.4))
	_arena.add_child(block)
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	# A path asked at every slot, as a crowd under a changing map would: the stuck window must
	# still close (it restarts only on another route).
	navigator.refresh_seconds = 0.25
	# A slow walk (a push of 0.7 is a walk): the sidestep must clear the block all the same.
	navigator.go_to(Vector3(6, 0, 0), 0.7)
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()
	assert_int(navigator.watch.episodes).is_greater_equal(1)
	assert_float(navigator.watch.longest_episode).is_less(3.0)


# A wall across the whole way that the ray passes: every rung is tried, the goal is dropped and
# reported, and the body is never moved by hand.
func test_a_way_it_cannot_pass_ends_in_a_report_and_no_teleport() -> void:
	await _ready_arena()
	_arena.add_child(_frozen_box(Vector3(0, 1, 0), Vector3(1, 2, 28)))
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	var reasons: Array[int] = []
	navigator.failed.connect(func(reason: int) -> void: reasons.append(reason))
	navigator.go_to(Vector3(6, 0, 0))
	var jump := 0.0
	var last := navigator.character.global_position
	for _tick in 15 * 60:
		await get_tree().physics_frame
		var at := navigator.character.global_position
		jump = maxf(jump, at.distance_to(last))
		last = at
		if not navigator.is_active():
			break
	assert_array(reasons).is_equal([AiNavigator.Failure.STUCK])
	assert_int(navigator.ladder.reports).is_equal(1)
	assert_float(jump).is_less(0.3)
	assert_bool(navigator.go_to(Vector3(6, 0, 0))).is_false()


# A solid wall the mesh runs through: the body-ray check of the new path finds it.
func test_a_wall_the_mesh_runs_through_is_blocked() -> void:
	await _ready_arena()
	_arena.add_block(Vector2(0, 0), Vector3(1, 2, 28), 2.0)
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	var reasons: Array[int] = []
	navigator.failed.connect(func(reason: int) -> void: reasons.append(reason))
	navigator.go_to(Vector3(6, 0, 0))
	await NavArena.walk(get_tree(), navigator, 3.0)
	assert_array(reasons).is_equal([AiNavigator.Failure.BLOCKED])
	assert_str(navigator.refusal).contains("blocked")


# A door on the way that shuts as the walker comes: it opens again for the body and the walk goes
# on. A locked one blocks.
func test_a_door_that_shuts_mid_walk_opens_again() -> void:
	await _ready_arena()
	var wall_a := _arena.add_block(Vector2(0, -7.5), Vector3(1, 3, 13), 3.0)
	var wall_b := _arena.add_block(Vector2(0, 7.5), Vector3(1, 3, 13), 3.0)
	assert_object(wall_a).is_not_null()
	assert_object(wall_b).is_not_null()
	var door := _door(Vector3(0, 0, 0))
	door.open()
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	navigator.go_to(Vector3(6, 0, 0))
	# Shut while the walker is still out of the door's range (a door shut on a body in its range
	# stays shut until the range empties).
	for _tick in 15:
		await get_tree().physics_frame
	assert_float(navigator.character.global_position.distance_to(door.position)).is_greater(2.6)
	door.close()
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()


func test_a_locked_door_blocks() -> void:
	await _ready_arena()
	_arena.add_block(Vector2(0, -7.5), Vector3(1, 3, 13), 3.0)
	_arena.add_block(Vector2(0, 7.5), Vector3(1, 3, 13), 3.0)
	var door := _door(Vector3(0, 0, 0))
	door.lock()
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	var reasons: Array[int] = []
	navigator.failed.connect(func(reason: int) -> void: reasons.append(reason))
	navigator.go_to(Vector3(6, 0, 0))
	await NavArena.walk(get_tree(), navigator, 4.0)
	assert_array(reasons).is_equal([AiNavigator.Failure.BLOCKED])


# A hole in the mesh that only a navigation link crosses: it reaches the link, says so, crosses
# it with its body and arrives. With the crossing left to a task it waits at the link.
func test_it_crosses_a_link() -> void:
	_arena.add_wall(Rect2i(-1, -14, 2, 28), 0.0, false)
	_arena.add_link(Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0))
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	# A path asked at every slot: none may be asked from the middle of the gap.
	navigator.refresh_seconds = 0.25
	var links := [0]
	navigator.link_reached.connect(
		func(_link: Node, _from: Vector3, _to: Vector3) -> void: links[0] += 1
	)
	navigator.go_to(Vector3(6, 0, 0))
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()
	assert_int(links[0]).is_equal(1)


func test_with_the_crossing_left_to_a_task_it_waits_at_the_link() -> void:
	_arena.add_wall(Rect2i(-1, -14, 2, 28), 0.0, false)
	_arena.add_link(Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0))
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	navigator.auto_traverse_links = false
	var ends: Array[Vector3] = []
	navigator.link_reached.connect(
		func(_link: Node, _from: Vector3, to: Vector3) -> void: ends.append(to)
	)
	navigator.go_to(Vector3(6, 0, 0))
	await InputSim.ticks(get_tree(), 4 * 60)
	assert_bool(navigator.is_active()).is_true()
	assert_float(navigator.character.global_position.x).is_between(-2.2, -0.9)
	assert_int(ends.size()).is_equal(1)
	# The stand-in task crosses (a climb or a door's own move puts the body at the far end).
	navigator.character.teleport(ends[0] + Vector3.UP * 0.05)
	navigator.finish_link()
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()


func _frozen_box(centre: Vector3, size: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


func _door(spot: Vector3) -> Door:
	var door := (load("res://gameplay/door/door.tscn") as PackedScene).instantiate() as Door
	door.auto_open_range = 2.5
	door.close_after = 1.5
	door.position = spot
	door.rotation.y = PI / 2.0
	_arena.add_child(door)
	return door
