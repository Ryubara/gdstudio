# The real character walks into both sections and through every part of them by pressing the move
# actions (`RouteWalker`), in the real main scene with its camera (kit #885): from the start
# through each doorway, along every route of the pathing section on its navigation path (the
# body follows what the mesh says an agent can do: up the ramp and the stairs, through the door
# that opens for it, across the gap by a jump, down the drop), and from a friendly spawn to every
# marker and enemy spawn of the AI section.
extends GdUnitTestSuite

## Physics steps run this much faster than the clock while a walk is on (the steps are the same).
const TIME_SCALE := 3.0

var _runner: GdUnitSceneRunner
var _scene: Node
var _player: Player
var _walker := RouteWalker.new()


func before_test() -> void:
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	_player = _scene.get_node("Player")
	Engine.time_scale = TIME_SCALE
	await InputSim.ticks(get_tree(), 10)
	var map := _map()
	var probe := (_scene.get_node("PathingSection/Routes/Wide/Start") as Node3D).global_position
	for _frame in 300:
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 0.75:
			break
		await get_tree().physics_frame


func after_test() -> void:
	Engine.time_scale = 1.0
	RouteWalker.release()
	InputSim.release_all()


func test_the_body_walks_from_the_start_through_each_doorway() -> void:
	var start := _player.global_position
	var east := PackedVector3Array([Vector3(10, 0, -6.5), Vector3(23, 0, -6), Vector3(28, 0, -6)])
	(
		assert_bool(await _walker.walk(_player, east))
		. override_failure_message(_walker.report)
		. is_true()
	)
	_player.teleport(start)
	await InputSim.ticks(get_tree(), 5)
	var west := PackedVector3Array([Vector3(-12, 0, -9), Vector3(-23, 0, -9), Vector3(-28, 0, -9)])
	(
		assert_bool(await _walker.walk(_player, west))
		. override_failure_message(_walker.report)
		. is_true()
	)


func test_the_body_walks_every_route_of_the_pathing_section() -> void:
	var failed: Array[String] = []
	for route: Node3D in _scene.get_node("PathingSection/Routes").get_children():
		var from := (route.get_node("Start") as Node3D).global_position
		var to := (route.get_node("End") as Node3D).global_position
		_player.teleport(from + Vector3.UP * 0.1)
		await InputSim.ticks(get_tree(), 5)
		var path := RouteWalker.path_on(_map(), _player.global_position, to)
		if not await _walker.walk(_player, path["points"], path["links"]):
			failed.append("%s: %s" % [route.name, _walker.report])
		elif absf(_player.global_position.y - to.y) > 0.3:
			failed.append("%s: ended at height %.2f" % [route.name, _player.global_position.y])
	assert_array(failed).override_failure_message("\n".join(failed)).is_empty()


func test_the_body_walks_from_a_friendly_spawn_to_every_part_of_the_ai_section() -> void:
	var section := _scene.get_node("AISection")
	var start := (section.get_node("Spawns/Friendly1") as Node3D).global_position
	var goals: Array[Node3D] = []
	for node: Node3D in section.get_node("Perception").get_children():
		goals.append(node)
	for node: Node3D in section.get_node("Spawns").get_children():
		if (node as SpawnPoint).spawn_group == &"enemy":
			goals.append(node)
	var failed: Array[String] = []
	for goal in goals:
		_player.teleport(start + Vector3.UP * 0.1)
		await InputSim.ticks(get_tree(), 5)
		var path := RouteWalker.path_on(_map(), _player.global_position, goal.global_position)
		if not await _walker.walk(_player, path["points"], path["links"]):
			failed.append("%s: %s" % [goal.name, _walker.report])
	assert_array(failed).override_failure_message("\n".join(failed)).is_empty()


func _map() -> RID:
	return _player.get_world_3d().navigation_map
