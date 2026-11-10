# Acceptance suite of the moving-platform eval (kit evals/godot/moving-platform/TASK.md). `gds eval check` copies it
# into the game's tests/eval_acceptance/, runs it with the game's own suites and removes it again. It never names the
# delivery's classes, only its scene, properties and signals, so a missing class fails a case and not the whole suite.
extends GdUnitTestSuite

const SCENE := "res://gameplay/platform/moving_platform.tscn"
const TUNING := "res://gameplay/platform/platform_tuning.tres"
const MAIN := "res://main.tscn"
const PING_PONG := 0
const LOOP := 1
const ONCE := 2

var _arrivals: Array[int] = []
var _finished := 0


func _dt() -> float:
	return 1.0 / Engine.physics_ticks_per_second


func _frames(seconds: float) -> int:
	return roundi(seconds * Engine.physics_ticks_per_second)


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _class_of(node: Object) -> String:
	var script: Script = node.get_script()
	return script.get_global_name() if script != null else ""


func _world() -> Node3D:
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	return world


## A platform at (0, 1, 0) with its stops and tuning set, not yet in the tree.
func _platform(stops: Array[Vector3], speed: float, pause: float, mode: int) -> AnimatableBody3D:
	var platform: AnimatableBody3D = load(SCENE).instantiate()
	var tuning: Resource = (load(TUNING) as Resource).duplicate()
	tuning.set("speed", speed)
	tuning.set("pause_seconds", pause)
	tuning.set("mode", mode)
	platform.set("tuning", tuning)
	platform.set("stops", stops)
	platform.position = Vector3(0.0, 1.0, 0.0)
	_arrivals.clear()
	_finished = 0
	platform.connect("arrived", func(index: int) -> void: _arrivals.append(index))
	platform.connect("finished", func() -> void: _finished += 1)
	return platform


func test_the_scene_is_an_animatable_body_with_the_platform_script() -> void:
	assert_bool(ResourceLoader.exists(SCENE)).is_true()
	var platform: Node = auto_free(load(SCENE).instantiate())
	assert_bool(platform is AnimatableBody3D).is_true()
	assert_bool((platform as AnimatableBody3D).sync_to_physics).is_true()
	assert_str(_class_of(platform)).is_equal("MovingPlatform")
	assert_bool(platform.is_in_group("moving_platforms")).is_true()
	assert_bool(platform.has_signal("arrived")).is_true()
	assert_bool(platform.has_signal("finished")).is_true()
	assert_bool(platform.has_method("is_moving")).is_true()
	(
		assert_int(platform.find_children("*", "CollisionShape3D", true, false).size())
		. is_greater_equal(1)
	)
	assert_int(platform.find_children("*", "MeshInstance3D", true, false).size()).is_greater_equal(
		1
	)
	assert_object(platform.get("tuning")).is_not_null()
	assert_str(_class_of(platform.get("tuning"))).is_equal("PlatformTuning")


func test_the_tuning_file_holds_two_metres_a_second_and_half_a_second() -> void:
	var tuning: Resource = load(TUNING)
	assert_str(_class_of(tuning)).is_equal("PlatformTuning")
	assert_float(tuning.get("speed")).is_equal_approx(2.0, 0.001)
	assert_float(tuning.get("pause_seconds")).is_equal_approx(0.5, 0.001)
	assert_int(tuning.get("mode")).is_equal(PING_PONG)


func test_it_travels_at_its_tuned_speed() -> void:
	var world := _world()
	var platform := _platform([Vector3(4.0, 0.0, 0.0)], 2.0, 0.5, PING_PONG)
	world.add_child(platform)
	await _physics_frames(_frames(0.5))
	assert_float(platform.global_position.x).is_between(0.9, 1.1)
	assert_float(platform.global_position.y).is_equal_approx(1.0, 0.001)
	assert_bool(platform.call("is_moving")).is_true()


func test_it_arrives_once_holds_for_the_pause_then_goes_back() -> void:
	var world := _world()
	var platform := _platform([Vector3(1.0, 0.0, 0.0)], 2.0, 0.5, PING_PONG)
	world.add_child(platform)
	await _physics_frames(_frames(0.8))
	assert_array(_arrivals).is_equal([1])
	assert_float(platform.global_position.x).is_equal_approx(1.0, 0.02)
	assert_bool(platform.call("is_moving")).is_false()
	await _physics_frames(_frames(3.2))
	assert_array(_arrivals.slice(0, 4)).is_equal([1, 0, 1, 0])
	assert_float(platform.global_position.x).is_between(-0.001, 1.001)


func test_it_never_moves_faster_than_its_speed_or_leaves_its_path() -> void:
	var world := _world()
	var platform := _platform([Vector3(3.0, 0.0, 0.0), Vector3(3.0, 0.0, 3.0)], 2.0, 0.0, LOOP)
	world.add_child(platform)
	var last := platform.global_position
	var fastest := 0.0
	var outside := 0
	for i in _frames(5.0):
		await get_tree().physics_frame
		var here := platform.global_position
		fastest = maxf(fastest, here.distance_to(last))
		last = here
		if here.x < -0.01 or here.x > 3.01 or here.z < -0.01 or here.z > 3.01:
			outside += 1
	assert_float(fastest).is_less_equal(2.0 * _dt() * 1.02 + 0.0001)
	assert_float(fastest).is_greater(2.0 * _dt() * 0.5)
	assert_int(outside).is_equal(0)


func test_loop_mode_goes_round_without_turning_back() -> void:
	var world := _world()
	var platform := _platform([Vector3(2.0, 0.0, 0.0), Vector3(2.0, 0.0, 2.0)], 4.0, 0.0, LOOP)
	world.add_child(platform)
	await _physics_frames(_frames(3.5))
	assert_array(_arrivals.slice(0, 5)).is_equal([1, 2, 0, 1, 2])


func test_once_mode_stops_at_the_end_and_finishes_once() -> void:
	var world := _world()
	var platform := _platform([Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 1.0)], 2.0, 0.0, ONCE)
	world.add_child(platform)
	await _physics_frames(_frames(3.0))
	assert_array(_arrivals).is_equal([1, 2])
	assert_int(_finished).is_equal(1)
	assert_bool(platform.call("is_moving")).is_false()
	assert_float(platform.global_position.distance_to(Vector3(1.0, 1.0, 1.0))).is_less(0.02)


func test_an_inactive_platform_holds_still_and_carries_on_when_set_active() -> void:
	var world := _world()
	var platform := _platform([Vector3(4.0, 0.0, 0.0)], 2.0, 0.5, PING_PONG)
	platform.set("active", false)
	world.add_child(platform)
	await _physics_frames(_frames(0.5))
	assert_float(platform.global_position.x).is_equal_approx(0.0, 0.001)
	assert_bool(platform.call("is_moving")).is_false()
	platform.set("active", true)
	await _physics_frames(_frames(0.5))
	assert_float(platform.global_position.x).is_between(0.9, 1.1)


func test_no_stops_or_no_tuning_does_nothing_quietly() -> void:
	var world := _world()
	var bare := _platform([], 2.0, 0.5, PING_PONG)
	world.add_child(bare)
	var untuned := _platform([Vector3(4.0, 0.0, 0.0)], 2.0, 0.5, PING_PONG)
	untuned.set("tuning", null)
	world.add_child(untuned)
	await _physics_frames(_frames(0.3))
	assert_vector(bare.global_position).is_equal(Vector3(0.0, 1.0, 0.0))
	assert_vector(untuned.global_position).is_equal(Vector3(0.0, 1.0, 0.0))
	assert_bool(bare.call("is_moving")).is_false()


func test_a_body_standing_on_it_is_carried_along() -> void:
	var world := _world()
	var platform := _platform([Vector3(20.0, 0.0, 0.0)], 2.0, 0.5, PING_PONG)
	platform.position = Vector3.ZERO
	world.add_child(platform)
	var rider := CharacterBody3D.new()
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	rider.add_child(capsule)
	var script := GDScript.new()
	script.source_code = (
		"extends CharacterBody3D\nfunc _physics_process(delta: float) -> void:\n"
		+ "\tvelocity.y -= 20.0 * delta\n\tmove_and_slide()\n"
	)
	script.reload()
	rider.set_script(script)
	rider.position = Vector3(0.0, 3.0, 0.0)
	world.add_child(rider)
	await _physics_frames(_frames(3.0))
	assert_float(rider.global_position.x).is_between(3.0, 6.2)
	assert_float(rider.global_position.y).is_between(0.5, 3.5)


func test_main_has_a_moving_platform_with_stops_standing_above_the_floor() -> void:
	var runner := scene_runner(MAIN)
	await _physics_frames(5)
	var scene: Node = runner.scene()
	var platforms: Array[Node] = []
	for node in get_tree().get_nodes_in_group("moving_platforms"):
		if scene.is_ancestor_of(node):
			platforms.append(node)
	assert_int(platforms.size()).is_greater_equal(1)
	if platforms.is_empty():
		return
	var platform: Node3D = platforms[0]
	var stops: Array = platform.get("stops")
	assert_int(stops.size()).is_greater_equal(2)
	var start := platform.global_position
	var space := (scene.get_viewport().world_3d as World3D).direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(start, start + Vector3.DOWN * 10.0)
	ray.exclude = [(platform as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(ray)
	assert_bool(hit.is_empty()).override_failure_message("no floor under the platform").is_false()
	if not hit.is_empty():
		assert_float(start.y - (hit.position as Vector3).y).is_between(0.3, 3.0)
	await _physics_frames(_frames(1.0))
	assert_float(platform.global_position.distance_to(start)).is_greater(0.5)
