# `Interactable` of `gds_game` on its own: it says `interacted` with who used it, does nothing
# switched off, measures from its fixed point, is found by a physics query on its layer, warns
# with no shape, and pins its exports. 3D Third Person's suites use one through a character's
# interactor (`test_interact_components.gd`).
extends GdUnitTestSuite


func _usable(at := Vector3.ZERO, shaped := true) -> Interactable:
	var holder: Node3D = auto_free(Node3D.new())
	holder.position = at
	add_child(holder)
	var usable := Interactable.new()
	if shaped:
		var shape := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.3
		shape.shape = ball
		usable.add_child(shape)
	holder.add_child(usable)
	return usable


func test_it_says_who_used_it_and_nothing_when_switched_off() -> void:
	var usable := _usable()
	var users: Array[Node3D] = []
	usable.interacted.connect(func(by: Node3D) -> void: users.append(by))
	var someone: Node3D = auto_free(Node3D.new())
	assert_bool(usable.interact(someone)).is_true()
	usable.enabled = false
	assert_bool(usable.interact(someone)).is_false()
	assert_array(users).is_equal([someone])
	assert_object(usable.usable()).is_same(usable.get_parent())


func test_it_measures_from_its_fixed_point_when_it_has_one() -> void:
	var usable := _usable(Vector3(2.0, 0.0, 0.0))
	assert_vector(usable.reach_point()).is_equal(Vector3(2.0, 0.0, 0.0))
	var spot: Node3D = auto_free(Node3D.new())
	spot.position = Vector3(0.0, 0.0, 5.0)
	add_child(spot)
	usable.point = spot
	assert_vector(usable.reach_point()).is_equal(Vector3(0.0, 0.0, 5.0))


func test_it_sits_on_the_sensors_layer_and_a_query_there_finds_it() -> void:
	var usable := _usable(Vector3(1.0, 0.0, 0.0))
	assert_int(usable.collision_layer).is_equal(64)
	assert_int(usable.collision_mask).is_equal(0)
	assert_bool(usable.monitoring).is_false()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var query := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 1.5
	query.shape = ball
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = Interactable.SENSORS_LAYER
	var found := usable.get_world_3d().direct_space_state.intersect_shape(query)
	assert_int(found.size()).is_equal(1)
	assert_object(found[0].collider).is_same(usable)
	query.collision_mask = 1
	assert_array(usable.get_world_3d().direct_space_state.intersect_shape(query)).is_empty()


func test_it_warns_without_a_shape_and_not_with_one() -> void:
	assert_array(_usable()._get_configuration_warnings()).is_empty()
	assert_array(_usable(Vector3.ZERO, false)._get_configuration_warnings()).is_not_empty()


func test_the_exports_keep_their_defaults() -> void:
	var pins := {&"prompt": "Use", &"enabled": true, &"point": null}
	var fresh: Interactable = auto_free(Interactable.new())
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
