# When the `AiNavigator` asks for a path again and how often it steers (kit #1062), on a mesh of
# its own (`NavArena`): a path is asked again only when the answer can differ (a map that changed,
# a body off its path, a followed target that moved, a path found blocked, `refresh_seconds` gone
# by), never more often than `repath_seconds`; and a steer holds on a long stretch until the body
# may reach the next point. Each rule's test fails with that rule taken out.
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


# A straight walk on a map that does not change: one path, however long the walk. Fails with every
# timer slot asking (about 4 a second).
func test_a_walk_on_a_still_map_asks_one_path() -> void:
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-12, 0, 0.5))
	navigator.refresh_seconds = 0.0
	navigator.go_to(Vector3(12, 0, 0.5), 0.5)
	assert_bool(await NavArena.walk(get_tree(), navigator)).is_true()
	assert_int(navigator.path_queries).is_equal(1)


# The same walk asks again every `refresh_seconds`, the net for what the map does not say.
func test_a_path_is_asked_again_after_refresh_seconds() -> void:
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-12, 0, 0.5))
	navigator.refresh_seconds = 1.0
	navigator.go_to(Vector3(12, 0, 0.5), 0.3)
	await InputSim.ticks(get_tree(), 200)
	assert_int(navigator.path_queries).is_between(3, 4)


# A hole cut across the way mid-walk (the map's next iteration): the walker asks again at its next
# slot and goes round. Fails without the iteration rule: it walks the old path into the hole's edge.
func test_a_map_that_changes_mid_walk_is_asked_again() -> void:
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-12, 0, 0.5))
	navigator.refresh_seconds = 0.0
	navigator.go_to(Vector3(12, 0, 0.5), 0.5)
	await InputSim.ticks(get_tree(), 30)
	assert_int(navigator.path_queries).is_equal(1)
	var old := _arena.region
	_arena.add_wall(Rect2i(2, -6, 2, 12), 2.0, false)
	_arena.build()
	old.free()
	var map := navigator.navigation_map()
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	for _tick in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) != iteration:
			break
	await InputSim.ticks(get_tree(), 45)
	assert_int(navigator.path_queries).is_greater(1)
	var round_the_hole := false
	for point in navigator.path.points:
		if absf(point.z) > 5.5:
			round_the_hole = true
	assert_bool(round_the_hole).is_true()


# A body put off its path (a push, a shove by the crowd): it asks again within a slot. Fails
# without the stray rule: it steers back to the old path and asks nothing.
func test_a_body_off_its_path_asks_again() -> void:
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-12, 0, 0.5))
	navigator.refresh_seconds = 0.0
	navigator.go_to(Vector3(12, 0, 0.5), 0.5)
	await InputSim.ticks(get_tree(), 30)
	assert_int(navigator.path_queries).is_equal(1)
	navigator.character.global_position += Vector3(0, 0, 3)
	# A slot is 0.25 s; the first after a goal waits a share of one more.
	await InputSim.ticks(get_tree(), 45)
	assert_int(navigator.path_queries).is_equal(2)


# On a long straight stretch a steer holds until the body may reach the next point, so the
# channel is written a few times a second, not at every `steer_seconds`; it still arrives. Fails
# with a steer every `steer_seconds` (20 a second).
func test_a_steer_holds_on_a_long_stretch() -> void:
	await _ready_arena()
	var navigator := _arena.add_walker(Vector3(-12, 0, 0.5))
	navigator.go_to(Vector3(12, 0, 0.5))
	var steers := 0
	var ticks := 0
	var last := navigator.steers
	for _tick in 600:
		await get_tree().physics_frame
		if navigator.is_arrived():
			break
		if (
			navigator.path.has_points()
			and navigator.path.left(navigator.character.global_position) > 3.0
		):
			steers += navigator.steers - last
			ticks += 1
		last = navigator.steers
	assert_bool(navigator.is_arrived()).is_true()
	assert_int(ticks).is_greater(60)
	assert_float(steers * 60.0 / ticks).is_less(6.0)


# Following, a target that moves off where the path was asked for is asked again at the next slot;
# one that stays put is not. Fails without the moved-target rule: the walker asks nothing more.
func test_a_followed_target_that_moves_is_asked_again() -> void:
	await _ready_arena()
	var target := Node3D.new()
	_arena.add_child(target)
	target.position = Vector3(10, 0, -6)
	var navigator := _arena.add_walker(Vector3(-10, 0, -6))
	navigator.refresh_seconds = 0.0
	navigator.follow(target, 1.0, 0.5)
	await InputSim.ticks(get_tree(), 45)
	assert_int(navigator.path_queries).is_equal(1)
	target.position = Vector3(10, 0, 6)
	await InputSim.ticks(get_tree(), 45)
	assert_int(navigator.path_queries).is_equal(2)
