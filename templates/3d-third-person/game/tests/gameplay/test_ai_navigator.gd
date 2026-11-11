# The `AiNavigator` on a mesh of its own (`NavArena`): an AI character walks to a goal with its real
# body, waits for the map, asks for a path no more often than `repath_seconds` and only within the
# director's budget, snaps a goal in a wall to the open ground in front, keeps its route when a
# target off the mesh flips sides or a much longer route appears, gives up an unreachable goal
# after one more ask with no search limit, and a far character stepped every 4th tick, the AGENT
# backend and two walkers meeting head on all get there. The ways that are not what the mesh says
# are `test_ai_nav_recovery.gd`.
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


# The debug overlay: the path drawn, and what it does over the head.
func test_the_debug_overlay_draws_the_path_and_says_what_it_does() -> void:
	await _ready_arena()
	_arena.add_director()
	var navigator := _arena.add_walker(Vector3(-8, 0, -8))
	navigator.character.debug = true
	navigator.debug = true
	navigator.go_to(Vector3(8, 0, 6))
	await InputSim.ticks(get_tree(), 30)
	assert_str(navigator.character.debug_label.text).contains("go to")
	var drawing := navigator.get_node("NavDebug") as AiNavDebug
	assert_int((drawing.mesh as ImmediateMesh).get_surface_count()).is_equal(1)
	navigator.debug = false
	await InputSim.ticks(get_tree(), 2)
	assert_object(navigator.get_node_or_null("NavDebug")).is_null()


# A map that has not taken its first iteration (here one never made active) answers nothing and
# prints an error for a query. Fails first with a query on it.
func test_it_waits_for_the_map_s_first_iteration() -> void:
	_errors.start()
	var map := NavigationServer3D.map_create()
	AiNavigator.register_class_map(AiNavigator.NavClass.SMALL, map)
	var navigator := _arena.add_walker(Vector3.ZERO)
	navigator.nav_class = AiNavigator.NavClass.SMALL
	navigator.go_to(Vector3(5, 0, 0))
	await InputSim.ticks(get_tree(), 30)
	var queries := navigator.path_queries
	AiNavigator.register_class_map(AiNavigator.NavClass.SMALL, RID())
	navigator.stop()
	NavigationServer3D.free_rid(map)
	_errors.stop()
	assert_int(NavigationServer3D.map_get_iteration_id(map)).is_equal(0)
	assert_int(queries).is_equal(0)
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


# A target that moves across a wall: on its near side the route is short, on its far side the
# only route is round the wall's end. Fails first without the kept route: the walker takes the
# long way and back each time the target crosses.
func test_a_much_longer_route_is_not_taken_while_the_old_one_ends_near_the_target() -> void:
	_arena.add_wall(Rect2i(0, -10, 3, 20))
	await _ready_arena()
	var target := Node3D.new()
	_arena.add_child(target)
	target.position = Vector3(0.2, 0, 4)
	var navigator := _arena.add_walker(Vector3(-8, 0, -4))
	var ends: Array[float] = []
	navigator.path_changed.connect(func() -> void: ends.append(navigator.path.end().x))
	navigator.follow(target, 0.3, 0.4)
	for tick in 240:
		target.position.x = 0.2 if (tick / 30) % 2 == 0 else 2.8
		await get_tree().physics_frame
	var flips := 0
	for index in range(1, ends.size()):
		if (ends[index] > 1.5) != (ends[index - 1] > 1.5):
			flips += 1
	assert_int(flips).is_equal(0)


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
