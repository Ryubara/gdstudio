# Acceptance suite of the pickup-feature eval (kit evals/godot/pickup-feature/TASK.md). `gds eval check` copies it
# into the game's tests/eval_acceptance/, runs it with the game's own suites and removes it again.
extends GdUnitTestSuite

const PICKUP := "res://gameplay/pickup/pickup.tscn"
const TUNING := "res://gameplay/pickup/pickup_tuning.tres"
const MAIN := "res://main.tscn"


func _body(at: Vector3, in_player_group: bool) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	if in_player_group:
		body.add_to_group("player")
	body.position = at
	return body


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


func _pickup(world: Node3D) -> Area3D:
	var pickup: Area3D = load(PICKUP).instantiate()
	world.add_child(pickup)
	return pickup


func test_the_pickup_scene_is_an_area_with_the_pickup_script() -> void:
	assert_bool(ResourceLoader.exists(PICKUP)).is_true()
	var pickup: Node = auto_free(load(PICKUP).instantiate())
	assert_bool(pickup is Area3D).is_true()
	assert_str(_class_of(pickup)).is_equal("Pickup")
	assert_bool(pickup.has_signal("collected")).is_true()
	assert_object(pickup.get("tuning")).is_not_null()
	assert_str(_class_of(pickup.get("tuning"))).is_equal("PickupTuning")


func test_the_tuning_file_holds_ten_points_and_ninety_degrees() -> void:
	var tuning: Resource = load(TUNING)
	assert_str(_class_of(tuning)).is_equal("PickupTuning")
	assert_int(tuning.get("value")).is_equal(10)
	assert_float(tuning.get("spin_speed_deg")).is_equal_approx(90.0, 0.001)


func test_a_player_collects_it_once_and_it_leaves() -> void:
	var world := _world()
	var pickup := _pickup(world)
	assert_bool(pickup.is_in_group("pickups")).is_true()
	var got: Array[int] = []
	pickup.collected.connect(func(value: int) -> void: got.append(value))
	world.add_child(_body(pickup.global_position, true))
	await _physics_frames(10)
	assert_array(got).is_equal([10])
	assert_bool(not is_instance_valid(pickup) or not pickup.is_inside_tree()).is_true()


func test_a_body_outside_the_player_group_takes_nothing() -> void:
	var world := _world()
	var pickup := _pickup(world)
	var got: Array[int] = []
	pickup.collected.connect(func(value: int) -> void: got.append(value))
	world.add_child(_body(pickup.global_position, false))
	await _physics_frames(10)
	assert_array(got).is_empty()
	assert_bool(is_instance_valid(pickup) and pickup.is_inside_tree()).is_true()


func test_it_spins_at_its_tuned_speed() -> void:
	var world := _world()
	var pickup := _pickup(world)
	var nodes: Array[Node3D] = [pickup]
	for child in pickup.find_children("*", "Node3D", true, false):
		nodes.append(child)
	var yaw_before: Array[float] = []
	for node in nodes:
		yaw_before.append(node.rotation.y)
	var start := Time.get_ticks_usec()
	await get_tree().create_timer(0.5).timeout
	var seconds := (Time.get_ticks_usec() - start) / 1_000_000.0
	var turned := 0.0
	for i in nodes.size():
		turned = maxf(turned, absf(angle_difference(yaw_before[i], nodes[i].rotation.y)))
	var expected := deg_to_rad(90.0) * seconds
	assert_float(turned).is_between(expected * 0.7, expected * 1.3)


func test_main_has_five_pickups_standing_above_the_floor() -> void:
	var runner := scene_runner(MAIN)
	await _physics_frames(5)
	var scene: Node = runner.scene()
	var pickups: Array[Node] = []
	for node in get_tree().get_nodes_in_group("pickups"):
		if scene.is_ancestor_of(node):
			pickups.append(node)
	assert_int(pickups.size()).is_greater_equal(5)
	var space := (scene.get_viewport().world_3d as World3D).direct_space_state
	for pickup: Node3D in pickups:
		var from := pickup.global_position
		var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0)
		var hit := space.intersect_ray(ray)
		(
			assert_bool(hit.is_empty())
			. override_failure_message("%s has no floor under it" % pickup.name)
			. is_false()
		)
		if not hit.is_empty():
			var height: float = from.y - (hit.position as Vector3).y
			assert_float(height).override_failure_message("%s height" % pickup.name).is_between(
				0.3, 2.0
			)
		var probe := PhysicsPointQueryParameters3D.new()
		probe.position = from
		var inside := space.intersect_point(probe)
		(
			assert_array(inside)
			. override_failure_message("%s is inside a solid" % pickup.name)
			. is_empty()
		)


func test_collecting_two_in_main_scores_twenty_and_shows_it() -> void:
	var runner := scene_runner(MAIN)
	await _physics_frames(5)
	var scene: Node = runner.scene()
	var pickups: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("pickups"):
		if scene.is_ancestor_of(node):
			pickups.append(node)
	var scores := get_tree().get_nodes_in_group("score")
	var labels := get_tree().get_nodes_in_group("score_label")
	assert_int(pickups.size()).is_greater_equal(2)
	assert_int(scores.size()).is_greater_equal(1)
	assert_int(labels.size()).is_greater_equal(1)
	if pickups.size() < 2 or scores.is_empty() or labels.is_empty():
		return
	var score: Node = scores[0]
	assert_bool(score.has_signal("score_changed")).is_true()
	var body := _body(pickups[0].global_position, true)
	scene.add_child(body)
	await _physics_frames(10)
	body.global_position = pickups[1].global_position
	await _physics_frames(10)
	await get_tree().process_frame
	assert_int(score.get("score")).is_equal(20)
	assert_bool(labels[0] is Label).is_true()
	assert_str((labels[0] as Label).text).ends_with("20")
