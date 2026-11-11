# The level's navigation takes a new region or a swapped mesh on the physics step, the same on
# every machine (kit #1075): the project turns off both of Godot's threaded builds,
# `navigation/world/region_use_async_iterations` and `navigation/world/map_use_async_iterations`.
# With the region's build on a worker thread (Godot's default) a region added to the level reached
# the map after a number of ticks that moved with machine load (24 to 97 here, over 300 once on a
# CI runner: kit docs/engines/godot/navigation-in-tests.md#a-small-mesh-of-your-own).
extends GdUnitTestSuite

const MAIN := "res://main.tscn"
const PATHING_SCENE := "res://world/prototype/pathing_section/pathing_section.tscn"
const REGION_SETTING := "navigation/world/region_use_async_iterations"
const MAP_SETTING := "navigation/world/map_use_async_iterations"
## Where the extra section stands: far from the level, so nothing else on the map answers there.
const AWAY := Vector3(200.0, 0.0, 200.0)
## The map answers at a point when its closest point is this near (the baked surface floats 0.2 m
## over the floor).
const ARRIVE := 0.75
## A region added in one frame is in the map by the end of the next physics tick's server step:
## the first `physics_frame` comes before that step, the second after it.
const NEXT_TICK := 2
## Long enough for any threaded build, so a failure says how late the map was.
const CAP := 300

var _main: Node
var _world: Node


func before() -> void:
	_main = load(MAIN).instantiate()
	(_main.get_node("PlayerRig/Player") as Player).start_at_spawn = false
	add_child(_main)
	_world = _main.get_node("World")
	for _frame in 4:
		await get_tree().physics_frame


func after() -> void:
	_main.free()


func test_the_project_builds_regions_and_maps_on_the_physics_step() -> void:
	assert_bool(ProjectSettings.get_setting(REGION_SETTING)).is_false()
	assert_bool(ProjectSettings.get_setting(MAP_SETTING)).is_false()
	assert_bool(NavigationServer3D.map_get_use_async_iterations(_map())).is_false()
	for section_name: String in ["AISection", "PathingSection"]:
		var region: NavigationRegion3D = _world.get_node(section_name + "/Navigation")
		(
			assert_bool(NavigationServer3D.region_get_use_async_iterations(region.get_rid()))
			. override_failure_message("%s builds its region on a thread" % section_name)
			. is_false()
		)


func test_a_section_added_to_the_level_answers_at_the_next_tick() -> void:
	var section := _add_section()
	var probe := _probe(section)
	var ticks := await _ticks_until(probe, true)
	(
		assert_int(ticks)
		. override_failure_message("the map took the new section after %d ticks" % ticks)
		. is_less_equal(NEXT_TICK)
	)
	section.free()


func test_a_mesh_swapped_out_of_a_region_leaves_the_map_at_the_next_tick() -> void:
	var section := _add_section()
	var probe := _probe(section)
	assert_int(await _ticks_until(probe, true)).is_less_equal(NEXT_TICK)
	(section.get_node("Navigation") as NavigationRegion3D).navigation_mesh = NavigationMesh.new()
	var ticks := await _ticks_until(probe, false)
	(
		assert_int(ticks)
		. override_failure_message("the map dropped the old mesh after %d ticks" % ticks)
		. is_less_equal(NEXT_TICK)
	)
	section.free()


func _add_section() -> Node3D:
	var section: Node3D = load(PATHING_SCENE).instantiate()
	section.position = AWAY
	_world.add_child(section)
	return section


func _probe(section: Node3D) -> Vector3:
	return (section.get_node("Routes/Wide/Start") as Node3D).global_position


# The physics ticks until the map answers at `probe` (`answers`) or stops answering there; CAP + 1
# when it never did.
func _ticks_until(probe: Vector3, answers: bool) -> int:
	for tick in range(1, CAP + 1):
		await get_tree().physics_frame
		var near := NavigationServer3D.map_get_closest_point(_map(), probe).distance_to(probe)
		if (near < ARRIVE) == answers:
			return tick
	return CAP + 1


func _map() -> RID:
	return (_world.get_node("PathingSection") as Node3D).get_world_3d().navigation_map
