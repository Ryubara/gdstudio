# The `AiNavigator` on a mesh of its own (`NavArena`): an AI character walks to a goal with its real
# body, waits for the map, asks for a path no more often than `repath_seconds` and only within the
# director's budget, snaps a goal in a wall to the open ground in front, keeps its route when a
# target off the mesh flips sides, gives up an unreachable goal after one more ask with no search
# limit, climbs the stuck ladder (a sidestep round a block it did not know of, a report with the
# goal dropped against one it cannot pass, nobody moved by hand), finds a wall the mesh runs
# through, crosses a link, and a far character stepped every 4th tick still gets there.
extends GdUnitTestSuite

var _arena: NavArena
var _errors := NavArena.ErrorLog.new()


func before_test() -> void:
	_arena = auto_free(NavArena.new())
	add_child(_arena)
	_errors.lines.clear()


func after_test() -> void:
	_errors.stop()
	AudioDrain.stop_all(_arena)


func _ready_arena() -> void:
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()


func test_it_walks_to_a_goal_with_its_body() -> void:
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-8, 0, -8))
	var arrived := [0]
	navigator.arrived.connect(func() -> void: arrived[0] += 1)
	navigator.go_to(Vector3(8, 0, 6))
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()
	assert_int(arrived[0]).is_equal(1)
	var at := navigator.character.global_position
	assert_float(AiNavPath.flat(at - Vector3(8, 0, 6)).length()).is_less(0.6)
	assert_int(navigator.watch.episodes).is_equal(0)


# Fails first with a query before the map's first iteration: the server prints an error and
# answers nothing.
func test_it_waits_for_the_map_s_first_iteration() -> void:
	_errors.start()
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	AiNavigator.register_class_map(AiNavigator.NavClass.SMALL, map)
	var navigator := _arena.add_walker(Vector3.ZERO)
	navigator.nav_class = AiNavigator.NavClass.SMALL
	navigator.go_to(Vector3(5, 0, 0))
	await InputSim.ticks(get_tree(), 1)
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		assert_int(navigator.path_queries).is_equal(0)
	AiNavigator.register_class_map(AiNavigator.NavClass.SMALL, RID())
	navigator.stop()
	NavigationServer3D.free_rid(map)
	assert_array(_errors.lines).is_empty()


func test_the_server_map_runs_without_async_iterations() -> void:
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-8, 0, -8))
	navigator.go_to(Vector3(-2, 0, -8))
	await InputSim.ticks(get_tree(), 5)
	var map := navigator.navigation_map()
	assert_bool(NavigationServer3D.map_get_use_async_iterations(map)).is_false()


# A target that moves every tick is asked for no more often than `repath_seconds` (counted).
func test_a_path_is_never_asked_for_more_often_than_repath_seconds() -> void:
	await _ready_arena()
	var target := Node3D.new()
	_arena.add_child(target)
	target.position = Vector3(10, 0, 10)
	var navigator := _arena.add_walker(Vector3(-10, 0, -10))
	navigator.repath_seconds = 0.25
	navigator.follow(target, 1.0)
	var seconds := 4.0
	for tick in roundi(seconds * 60):
		target.position = Vector3(10, 0, 10 - fmod(tick * 0.05, 8.0))
		await get_tree().physics_frame
	assert_int(navigator.path_queries).is_greater(4)
	assert_int(navigator.path_queries).is_less_equal(int(seconds / 0.25) + 1)


# Six characters given goals on one tick with one path query a tick: never two in a tick.
func test_path_queries_stay_within_the_director_s_budget() -> void:
	await _ready_arena()
	var director := _arena.add_director()
	director.paths_per_tick = 1
	var navigators: Array[AiNavigator] = []
	for index in 6:
		navigators.append(_arena.add_walker(Vector3(-10 + index * 2, 0, -10)))
	await InputSim.ticks(get_tree(), 2)
	for navigator in navigators:
		navigator.go_to(navigator.character.global_position + Vector3(0, 0, 15))
	var most := 0
	var before_count := _queries(navigators)
	for _tick in 120:
		await get_tree().physics_frame
		var now := _queries(navigators)
		most = maxi(most, now - before_count)
		before_count = now
	assert_int(most).is_equal(1)
	for navigator in navigators:
		assert_int(navigator.path_queries).is_greater(0)


func _queries(navigators: Array[AiNavigator]) -> int:
	var total := 0
	for navigator in navigators:
		total += navigator.path_queries
	return total


# A goal inside a wall, nearer its far side: the nearest point of the mesh is behind the wall, in
# a shut pocket. Fails first with the nearest point as the goal (the walker gives up the goal).
func test_a_goal_in_a_wall_is_walked_to_from_the_open_side() -> void:
	# A pocket behind the wall: shut on every side.
	_arena.add_wall(Rect2i(0, -4, 2, 9))
	_arena.add_wall(Rect2i(4, -4, 2, 9))
	_arena.add_wall(Rect2i(2, -4, 2, 2))
	_arena.add_wall(Rect2i(2, 3, 2, 2))
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-8, 0, 0))
	# Inside the west wall, 0.3 m from its east face (the pocket's side).
	navigator.go_to(Vector3(1.2, 0, 0.5))
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()
	assert_float(navigator.character.global_position.x).is_less(0.0)


# Deadnight #950's flip, made here: a target in a hole between two blocks, moving across its
# middle. Fails first without the kept route: the walker turns round at each repath.
func test_a_target_off_the_mesh_does_not_turn_the_walker_round() -> void:
	_arena.add_wall(Rect2i(-1, -6, 3, 12))
	await _ready_arena()
	var target := Node3D.new()
	_arena.add_child(target)
	var navigator := _arena.add_walker(Vector3(-8, 0, -1))
	navigator.follow(target, 0.5)
	var turns := 0
	var heading := Vector3.ZERO
	for tick in 360:
		# The target crosses the hole's middle line (z = 0) every half second.
		target.position = Vector3(0.5, 0, 0.6 * sin(tick * TAU / 60.0))
		await get_tree().physics_frame
		var walk := (navigator.character.controller as AiController).walk_direction
		if walk != Vector3.ZERO and heading != Vector3.ZERO and walk.dot(heading) < -0.5:
			turns += 1
		if walk != Vector3.ZERO:
			heading = walk
	assert_int(turns).is_less_equal(1)


# An island the walker cannot reach: asked once with the limit, once with none, then refused
# for 5 s without a query.
func test_an_unreachable_goal_is_asked_twice_and_remembered() -> void:
	_arena.add_wall(Rect2i(4, 2, 6, 1))
	_arena.add_wall(Rect2i(4, 7, 6, 1))
	_arena.add_wall(Rect2i(4, 3, 1, 4))
	_arena.add_wall(Rect2i(9, 3, 1, 4))
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	var reasons: Array[int] = []
	navigator.failed.connect(func(reason: int) -> void: reasons.append(reason))
	navigator.go_to(Vector3(7, 0, 5))
	assert_bool(await NavArena.walk(get_tree(), navigator, 3.0)).is_false()
	assert_array(reasons).is_equal([AiNavigator.Failure.UNREACHABLE])
	assert_int(navigator.path_queries).is_equal(2)
	assert_bool(navigator.go_to(Vector3(7.2, 0, 5.1))).is_false()
	assert_int(navigator.path_queries).is_equal(2)
	await InputSim.ticks(get_tree(), 5 * 60 + 5)
	assert_bool(navigator.go_to(Vector3(7, 0, 5))).is_true()


# A block the mesh does not know of and the body-ray check passes (it may move): the stuck watch
# sees it, the sidestep takes the body round it.
func test_a_sidestep_takes_it_round_a_block_it_did_not_know_of() -> void:
	await _ready_arena()
	var block := _frozen_box(Vector3(0, 1, 0), Vector3(1.2, 2, 1.2))
	_arena.add_child(block)
	var navigator := _arena.add_walker(Vector3(-6, 0, 0))
	navigator.go_to(Vector3(6, 0, 0))
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


# The director steps a far character every 4th tick: its walks are as sure.
func test_a_far_character_stepped_less_often_reaches_its_goal() -> void:
	await _ready_arena()
	var director := _arena.add_director()
	director.reduced_step_ticks = 4
	_arena.viewer.position = Vector3(0, 0, 40)
	var navigator := _arena.add_walker(Vector3(-8, 0, -8))
	await InputSim.ticks(get_tree(), 10)
	assert_int(navigator.character.tier).is_equal(AiDirector.Tier.REDUCED)
	var steps := director.body_steps
	navigator.go_to(Vector3(8, 0, 6))
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()
	var off := AiNavPath.flat(navigator.character.global_position - Vector3(8, 0, 6))
	assert_float(off.length()).is_less(0.8)
	assert_int(director.body_steps - steps).is_greater(0)


func test_the_agent_backend_walks_the_same_way() -> void:
	await _ready_arena()
	var character := _arena.add_character(Vector3(-8, 0, -8))
	var navigator := character.navigator as AiNavigator
	character.remove_child(navigator)
	navigator.backend = AiNavigator.Backend.AGENT
	navigator.avoidance = AiNavAvoidance.Mode.RVO
	character.add_child(navigator)
	navigator.go_to(Vector3(8, 0, 6))
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()


# Two walkers that meet head on in a corridor, with the separation push, both get through.
func test_two_walkers_meeting_head_on_both_get_through() -> void:
	_arena.add_wall(Rect2i(-10, -14, 20, 12))
	_arena.add_wall(Rect2i(-10, 1, 20, 13))
	await _ready_arena()
	var one := _arena.add_walker(Vector3(-12, 0, -0.5))
	var other := _arena.add_walker(Vector3(12, 0, -0.5))
	for navigator: AiNavigator in [one, other]:
		navigator.avoidance = AiNavAvoidance.Mode.SEPARATION
	one.go_to(Vector3(12, 0, -0.5))
	other.go_to(Vector3(-12, 0, -0.5))
	for _tick in 25 * 60:
		await get_tree().physics_frame
		if one.is_arrived() and other.is_arrived():
			break
	assert_bool(one.is_arrived() and other.is_arrived()).is_true()


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
