# The map components work on their own: each is made in code with its exports, then driven by
# the calls and signals another node would use.
extends GdUnitTestSuite


func _add(node: Node) -> Node:
	add_child(auto_free(node))
	return node


func test_a_door_opens_closes_and_stays_shut_when_locked() -> void:
	var door := _add(load("res://gameplay/door/door.tscn").instantiate()) as Door
	door.open_time = 0.1
	door.open()
	for _frame in 20:
		await get_tree().physics_frame
	assert_bool(door.is_open()).is_true()
	door.close()
	for _frame in 20:
		await get_tree().physics_frame
	assert_float(door.openness()).is_equal(0.0)
	door.lock()
	door.open()
	assert_bool(door.is_moving()).is_false()


func test_a_pickup_says_who_took_what_and_goes() -> void:
	var pickup := _add(load("res://gameplay/pickup/pickup.tscn").instantiate()) as Pickup
	pickup.item_id = &"key"
	pickup.amount = 3
	var taker := Node3D.new()
	auto_free(taker)
	var got := []
	pickup.collected.connect(
		func(who: Node3D, id: StringName, n: int) -> void: got.append([who, id, n])
	)
	pickup._on_body_entered(taker)
	assert_array(got).has_size(1)
	assert_str(got[0][1]).is_equal("key")
	assert_int(got[0][2]).is_equal(3)


func test_a_trigger_zone_reports_the_first_in_and_the_last_out() -> void:
	var zone := (
		_add(load("res://gameplay/trigger_zone/trigger_zone.tscn").instantiate()) as TriggerZone
	)
	var log := []
	zone.activated.connect(func(_body: Node3D) -> void: log.append("on"))
	zone.deactivated.connect(func() -> void: log.append("off"))
	var one := Node3D.new()
	var two := Node3D.new()
	auto_free(one)
	auto_free(two)
	zone._on_body_entered(one)
	zone._on_body_entered(two)
	zone._on_body_exited(one)
	assert_bool(zone.is_active()).is_true()
	zone._on_body_exited(two)
	assert_array(log).is_equal(["on", "off"])


func test_a_moving_platform_goes_to_the_far_end_and_says_so() -> void:
	var platform := (
		load("res://gameplay/moving_platform/moving_platform.tscn").instantiate() as MovingPlatform
	)
	platform.travel = Vector3(0.0, 0.0, 1.0)
	platform.speed = 10.0
	platform.autostart = false
	platform.mode = MovingPlatform.Mode.ON_CALL
	_add(platform)
	var reached := []
	platform.reached_end.connect(func() -> void: reached.append(true))
	platform.send_to_end()
	for _frame in 20:
		await get_tree().physics_frame
	assert_array(reached).has_size(1)
	assert_float(platform.progress()).is_equal(1.0)


func test_a_spawn_point_is_picked_by_group_and_faces_its_forward() -> void:
	var point := (
		_add(load("res://gameplay/spawn_point/spawn_point.tscn").instantiate()) as SpawnPoint
	)
	point.spawn_group = &"team_red"
	point.position = Vector3(4.0, 0.0, 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	assert_object(SpawnPoint.pick(get_tree(), &"team_red", rng)).is_same(point)
	assert_object(SpawnPoint.pick(get_tree(), &"team_blue", rng)).is_null()
	assert_vector(point.spawn_transform(rng).origin).is_equal(Vector3(4.0, 0.0, 2.0))


func test_a_physics_prop_follows_its_size_and_weight() -> void:
	var prop := (
		_add(load("res://gameplay/physics_prop/physics_prop.tscn").instantiate()) as PhysicsProp
	)
	prop.size = Vector3(2.0, 1.0, 2.0)
	prop.weight = 40.0
	assert_float(prop.mass).is_equal(40.0)
	var shape := prop.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	assert_vector((shape.shape as BoxShape3D).size).is_equal(Vector3(2.0, 1.0, 2.0))
