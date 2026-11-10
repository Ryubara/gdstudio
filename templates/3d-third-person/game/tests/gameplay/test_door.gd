# The door's inspector contract: every export has its default pinned, and each one that has an
# effect is changed on a running door and its effect read.
extends GdUnitTestSuite

const SCENE := "res://gameplay/door/door.tscn"

var _door: Door


func before_test() -> void:
	_door = load(SCENE).instantiate() as Door
	add_child(_door)
	await get_tree().physics_frame


func after_test() -> void:
	_door.free()


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func test_every_export_has_its_default_pinned() -> void:
	var pins := {
		&"panel_size": Vector3(2.0, 3.0, 0.25),
		&"panel_material": null,
		&"style": Door.Style.SLIDE_UP,
		&"slide_distance": 0.0,
		&"swing_angle": 100.0,
		&"open_time": 0.8,
		&"start_open": false,
		&"locked": false,
		&"close_after": 0.0,
		&"auto_open_range": 0.0,
		&"auto_open_mask": PhysicsLayers.CHARACTERS,
		&"player_can_use": true,
	}
	assert_array(ExportPins.differences(_door, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_door, pins)).is_empty()


func test_the_scene_holds_its_parts_and_has_no_warning() -> void:
	for part_name in ["Panel", "Shape", "Sensor", "SensorShape"]:
		assert_object(_door.find_child(part_name, true, false)).is_not_null()
	assert_array(_door._get_configuration_warnings()).is_empty()


func test_the_panel_size_resizes_the_mesh_and_the_collision() -> void:
	_door.panel_size = Vector3(4.0, 2.0, 0.5)
	var panel := _door.get_node("%Panel") as MeshInstance3D
	var shape := _door.get_node("%Shape") as CollisionShape3D
	assert_vector((panel.mesh as BoxMesh).size).is_equal(Vector3(4.0, 2.0, 0.5))
	assert_vector((shape.shape as BoxShape3D).size).is_equal(Vector3(4.0, 2.0, 0.5))
	assert_float(panel.position.y).is_equal(1.0)


func test_two_doors_do_not_share_a_size() -> void:
	var other := load(SCENE).instantiate() as Door
	add_child(other)
	other.panel_size = Vector3(1.0, 1.0, 1.0)
	assert_vector(((_door.get_node("%Panel") as MeshInstance3D).mesh as BoxMesh).size).is_equal(
		Vector3(2.0, 3.0, 0.25)
	)
	other.free()


func test_the_panel_material_paints_the_mesh() -> void:
	var paint := StandardMaterial3D.new()
	_door.panel_material = paint
	assert_object((_door.get_node("%Panel") as MeshInstance3D).material_override).is_same(paint)


func test_a_slide_distance_moves_the_open_panel_that_far_and_follows_a_change() -> void:
	_door.open_time = 0.1
	_door.slide_distance = 2.0
	_door.open()
	await _ticks(20)
	assert_float(_door.position.y).is_equal_approx(2.0, 0.01)
	_door.slide_distance = 1.0
	await _ticks(2)
	assert_float(_door.position.y).is_equal_approx(1.0, 0.01)
	_door.style = Door.Style.SLIDE_SIDE
	await _ticks(2)
	assert_float(_door.position.x).is_equal_approx(1.0, 0.01)
	assert_float(_door.position.y).is_equal_approx(0.0, 0.01)


func test_a_swing_angle_turns_the_open_panel_that_far() -> void:
	_door.style = Door.Style.SWING
	_door.open_time = 0.1
	_door.swing_angle = 60.0
	_door.open()
	await _ticks(20)
	assert_float(absf(rad_to_deg(_door.rotation.y))).is_equal_approx(60.0, 0.1)
	_door.swing_angle = 90.0
	await _ticks(2)
	assert_float(absf(rad_to_deg(_door.rotation.y))).is_equal_approx(90.0, 0.1)


func test_the_open_time_sets_how_long_it_takes() -> void:
	_door.open_time = 2.0
	_door.open()
	await _ticks(10)
	assert_float(_door.openness()).is_less(0.2)
	_door.close()
	await _ticks(2)
	_door.open_time = 0.05
	_door.open()
	await _ticks(10)
	assert_bool(_door.is_open()).is_true()


func test_a_locked_door_stays_shut_until_unlocked_in_the_inspector() -> void:
	var blocked := []
	_door.blocked.connect(func() -> void: blocked.append(true))
	_door.locked = true
	_door.open()
	assert_array(blocked).has_size(1)
	assert_bool(_door.is_moving()).is_false()
	_door.locked = false
	_door.open()
	assert_bool(_door.is_moving()).is_true()


func test_close_after_closes_an_open_door_when_set_while_it_is_open() -> void:
	_door.open_time = 0.1
	_door.open()
	await _ticks(15)
	assert_bool(_door.is_open()).is_true()
	_door.close_after = 0.2
	await _ticks(30)
	assert_float(_door.openness()).is_equal(0.0)


func test_start_open_decides_where_a_new_door_begins() -> void:
	var open_door := load(SCENE).instantiate() as Door
	open_door.start_open = true
	add_child(open_door)
	assert_bool(open_door.is_open()).is_true()
	open_door.free()


# A body on `layer`, or on the layer of what it is (a character, a prop, the level) when it is 0.
func _body(kind: Node3D, at: Vector3, layer := 0) -> Node3D:
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	kind.add_child(shape)
	if layer == 0:
		layer = PhysicsLayers.WORLD
		if kind is CharacterBody3D:
			layer = PhysicsLayers.CHARACTERS
		elif kind is RigidBody3D:
			layer = PhysicsLayers.PROPS
	(kind as CollisionObject3D).collision_layer = layer
	kind.position = at  # Before it enters the tree: one built at the origin is sensed there.
	add_child(kind)
	return kind


# A door with a 3 m reach and a 0.5 s close_after, surrounded by what the prototype level puts
# around its gate: a floor under it, posts beside it and a low wall within the reach.
func _door_among_blocks() -> Array[Node3D]:
	_door.open_time = 0.1
	_door.close_after = 0.5
	_door.auto_open_range = 3.0
	var blocks: Array[Node3D] = []
	for at in [Vector3(0.0, -0.5, 0.0), Vector3(-1.5, 0.5, 0.0), Vector3(2.0, 0.5, 1.0)]:
		blocks.append(_body(StaticBody3D.new(), at))
	blocks.append(_body(RigidBody3D.new(), Vector3(0.0, 1.5, 2.0)))
	return blocks


func test_a_door_with_a_reach_stays_closed_among_static_blocks_and_props() -> void:
	var blocks := _door_among_blocks()
	await _ticks(30)
	var sensor := _door.get_node("%Sensor") as Area3D
	# The sensor masks Characters (#924): the floor, posts, wall and crate never reach it.
	assert_array(sensor.get_overlapping_bodies()).is_empty()
	assert_bool(_door.is_moving() or _door.is_open()).is_false()
	assert_float(_door.openness()).is_equal(0.0)
	for block in blocks:
		block.free()


func test_a_character_in_reach_opens_it_and_it_closes_close_after_they_leave() -> void:
	var blocks := _door_among_blocks()
	var walker := _body(CharacterBody3D.new(), Vector3(0.0, 1.0, 8.0)) as CharacterBody3D
	await _ticks(10)
	assert_float(_door.openness()).is_equal(0.0)
	walker.global_position = Vector3(0.0, 1.0, 2.0)
	await _ticks(10)
	assert_bool(_door.is_open()).is_true()
	# Standing there longer than close_after keeps it open.
	await _ticks(60)
	assert_bool(_door.is_open()).is_true()
	walker.global_position = Vector3(0.0, 1.0, 8.0)
	await _ticks(10)
	assert_bool(_door.is_open()).is_true()
	await _ticks(50)
	assert_float(_door.openness()).is_equal(0.0)
	walker.free()
	for block in blocks:
		block.free()


func test_interact_closes_a_door_that_opened_for_you_and_it_waits_until_you_come_back() -> void:
	var walker := _body(CharacterBody3D.new(), Vector3(0.0, 1.0, 2.0)) as CharacterBody3D
	_door.open_time = 0.1
	_door.close_after = 0.5
	_door.auto_open_range = 3.0
	await _ticks(10)
	assert_bool(_door.is_open()).is_true()
	_door.interact(walker)
	await _ticks(30)
	assert_float(_door.openness()).is_equal(0.0)
	assert_bool(_door.is_moving()).is_false()
	walker.global_position = Vector3(0.0, 1.0, 8.0)
	await _ticks(10)
	assert_float(_door.openness()).is_equal(0.0)
	walker.global_position = Vector3(0.0, 1.0, 2.0)
	await _ticks(10)
	assert_bool(_door.is_open()).is_true()
	walker.free()


func test_interact_opens_a_door_it_closed_while_you_stand_in_reach() -> void:
	var walker := _body(CharacterBody3D.new(), Vector3(0.0, 1.0, 2.0)) as CharacterBody3D
	_door.open_time = 0.1
	_door.auto_open_range = 3.0
	await _ticks(10)
	_door.interact(walker)
	await _ticks(10)
	assert_float(_door.openness()).is_equal(0.0)
	_door.interact(walker)
	await _ticks(10)
	assert_bool(_door.is_open()).is_true()
	await _ticks(30)
	assert_bool(_door.is_open()).is_true()
	walker.free()


func test_the_reach_is_measured_from_the_closed_door_even_when_a_swing_moves_it() -> void:
	var gate := load(SCENE).instantiate() as Door
	gate.style = Door.Style.SWING
	gate.open_time = 0.1
	gate.position = Vector3(5.0, 0.0, 4.0)
	add_child(gate)
	await _ticks(2)
	gate.open()
	await _ticks(20)
	assert_float(gate.global_position.distance_to(Vector3(5.0, 0.0, 4.0))).is_greater(0.5)
	assert_vector(gate.interact_point()).is_equal_approx(
		Vector3(5.0, 0.0, 4.0), Vector3.ONE * 0.001
	)
	var interactor := Interactor.new()
	add_child(interactor)
	interactor.global_position = Vector3(5.0, 0.0, 2.8)
	assert_object(interactor.find_target(Vector3.BACK, 1.6)).is_same(gate)
	interactor.free()
	gate.free()


func test_the_auto_open_mask_decides_which_characters_open_it() -> void:
	var walker := _body(CharacterBody3D.new(), Vector3(0.0, 1.0, 2.0)) as CharacterBody3D
	_door.open_time = 0.1
	_door.auto_open_mask = PhysicsLayers.WORLD
	_door.auto_open_range = 3.0
	await _ticks(10)
	assert_float(_door.openness()).is_equal(0.0)
	assert_int((_door.get_node("%Sensor") as Area3D).collision_mask).is_equal(PhysicsLayers.WORLD)
	_door.auto_open_mask = PhysicsLayers.CHARACTERS
	await _ticks(10)
	assert_bool(_door.is_open()).is_true()
	walker.free()


func test_player_can_use_puts_the_door_in_the_group_a_character_looks_in() -> void:
	assert_bool(_door.is_in_group(&"interactable")).is_true()
	_door.player_can_use = false
	assert_bool(_door.is_in_group(&"interactable")).is_false()
	_door.player_can_use = true
	assert_bool(_door.is_in_group(&"interactable")).is_true()
