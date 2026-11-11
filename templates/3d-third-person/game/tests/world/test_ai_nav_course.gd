# An AI character walks the map's proof course with its navigator and its real body, in the real
# main scene with the level's director (kit #967 on the sections of #885): every route of the
# pathing section (wide, narrow and tight passages, the door that opens and shuts, the ramp, the
# stairs, the kerb, the gap with its link, the drop, the moving obstacles, across) and from the AI
# section's doorway to every marker and enemy spawn in it, with stuck seconds under 1 % of the
# walking time and no episode over 3 s; and the same routes stepped every 4th tick as a far
# character.
extends GdUnitTestSuite

const CHARACTER := "res://gameplay/ai/ai_character.tscn"

var _runner: GdUnitSceneRunner
var _scene: Node
var _walker: AiCharacter
var _navigator: AiNavigator


func before_test() -> void:
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	await InputSim.ticks(get_tree(), 10)
	var map := (_scene.get_node("PlayerRig/Player") as Node3D).get_world_3d().navigation_map
	var probe := (
		(_scene.get_node("World/PathingSection/Routes/Wide/Start") as Node3D).global_position
	)
	for _frame in 300:
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 0.75:
			break
		await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_scene)


# A walker in the world, at the Full tier wherever it is (or, `far`, never: Reduced, stepped
# every `reduced_step_ticks`).
func _add_walker(spot: Vector3, far := false) -> void:
	_walker = (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	var profile := _walker.profile.duplicate() as AiProfile
	profile.full_range = 0.0 if far else 1000.0
	profile.reduced_range = 1000.0
	_walker.profile = profile
	_walker.position = spot
	_scene.get_node("World").add_child(_walker)
	_navigator = _walker.navigator as AiNavigator
	await InputSim.ticks(get_tree(), 12)


func _routes() -> Array[Node3D]:
	var routes: Array[Node3D] = []
	for route: Node3D in _scene.get_node("World/PathingSection/Routes").get_children():
		routes.append(route)
	return routes


# Walks each route from its start to its end; returns the failures.
func _walk_routes() -> Array[String]:
	var failed: Array[String] = []
	for route in _routes():
		var from := (route.get_node("Start") as Node3D).global_position
		var to := (route.get_node("End") as Node3D).global_position
		_walker.teleport(from + Vector3.UP * 0.1)
		await InputSim.ticks(get_tree(), 8)
		_navigator.go_to(to)
		var ticks_before := Engine.get_physics_frames()
		var walked := await NavArena.walk(get_tree(), _navigator, 30.0)
		print(
			(
				"route %s: %s in %d ticks, at %s, %s"
				% [
					route.name,
					walked,
					Engine.get_physics_frames() - ticks_before,
					_walker.global_position,
					_stuck_message()
				]
			)
		)
		if not walked:
			failed.append("%s: %s" % [route.name, _navigator.debug_text()])
		elif absf(_walker.global_position.y - to.y) > 0.3:
			failed.append("%s: ended at height %.2f" % [route.name, _walker.global_position.y])
	return failed


func _stuck_message() -> String:
	var watch := _navigator.watch
	return (
		"stuck %.2f s of %.1f s walking (%d episodes, longest %.2f s)"
		% [watch.stuck_seconds, watch.walking_seconds, watch.episodes, watch.longest_episode]
	)


func test_an_ai_character_walks_every_route_of_the_pathing_section() -> void:
	await _add_walker(Vector3(30, 0.1, 10))
	var failed := await _walk_routes()
	assert_array(failed).override_failure_message("\n".join(failed)).is_empty()
	var watch := _navigator.watch
	assert_float(watch.stuck_share()).override_failure_message(_stuck_message()).is_less(0.01)
	assert_float(watch.longest_episode).override_failure_message(_stuck_message()).is_less(3.0)


func test_a_far_character_stepped_every_4th_tick_walks_them_too() -> void:
	await _add_walker(Vector3(30, 0.1, 10), true)
	assert_int(_walker.tier).is_equal(AiDirector.Tier.REDUCED)
	var failed := await _walk_routes()
	assert_array(failed).override_failure_message("\n".join(failed)).is_empty()
	(
		assert_float(_navigator.watch.longest_episode)
		. override_failure_message(_stuck_message())
		. is_less(3.0)
	)


# The AI section from its doorway: from a friendly spawn round the cover, the columns and the shed
# to every marker and every enemy spawn behind the screen.
func test_it_walks_from_the_doorway_to_every_part_of_the_ai_section() -> void:
	var section := _scene.get_node("World/AISection")
	var start := (section.get_node("Spawns/Friendly1") as Node3D).global_position
	await _add_walker(start + Vector3.UP * 0.1)
	var goals: Array[Node3D] = []
	for node: Node3D in section.get_node("Perception").get_children():
		goals.append(node)
	for node: Node3D in section.get_node("Spawns").get_children():
		if (node as SpawnPoint).spawn_group == &"enemy":
			goals.append(node)
	var failed: Array[String] = []
	for goal in goals:
		_walker.teleport(start + Vector3.UP * 0.1)
		await InputSim.ticks(get_tree(), 8)
		_navigator.go_to(goal.global_position)
		if not await NavArena.walk(get_tree(), _navigator, 30.0):
			failed.append("%s: %s" % [goal.name, _navigator.debug_text()])
	assert_array(failed).override_failure_message("\n".join(failed)).is_empty()
	var watch := _navigator.watch
	assert_float(watch.stuck_share()).override_failure_message(_stuck_message()).is_less(0.01)
	assert_float(watch.longest_episode).override_failure_message(_stuck_message()).is_less(3.0)
