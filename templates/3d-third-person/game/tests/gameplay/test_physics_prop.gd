# The physics prop's inspector contract: every export has its default pinned, and each one that has
# an effect is changed on a running prop and its effect read.
extends GdUnitTestSuite

const SCENE := "res://gameplay/physics_prop/physics_prop.tscn"

var _prop: PhysicsProp


func before_test() -> void:
	_prop = load(SCENE).instantiate() as PhysicsProp
	add_child(_prop)
	await get_tree().physics_frame


func after_test() -> void:
	_prop.free()


func _mesh(part_name: String) -> MeshInstance3D:
	return _prop.get_node("%" + part_name + "Mesh") as MeshInstance3D


func _collider(part_name: String) -> CollisionShape3D:
	return _prop.get_node("%" + part_name + "Shape") as CollisionShape3D


func test_every_export_has_its_default_pinned() -> void:
	var pins := {
		&"shape": PhysicsProp.Shape.BOX,
		&"size": Vector3.ONE,
		&"material": null,
		&"weight": 10.0,
		&"grip": 0.6,
		&"bounciness": 0.1,
		&"fall_limit": -20.0,
	}
	assert_array(ExportPins.differences(_prop, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_prop, pins)).is_empty()


func test_the_scene_holds_all_three_shapes_and_has_no_warning() -> void:
	for part_name in ["Crate", "Barrel", "Ball"]:
		assert_object(_mesh(part_name)).is_not_null()
		assert_object(_collider(part_name)).is_not_null()
	assert_array(_prop._get_configuration_warnings()).is_empty()


func test_the_shape_shows_one_mesh_and_enables_one_collider() -> void:
	var order := ["Crate", "Barrel", "Ball"]
	for chosen in 3:
		_prop.shape = chosen as PhysicsProp.Shape
		for index in 3:
			assert_bool(_mesh(order[index]).visible).is_equal(index == chosen)
			assert_bool(_collider(order[index]).disabled).is_equal(index != chosen)


func test_the_size_sizes_every_shape_its_own_way() -> void:
	_prop.size = Vector3(2.0, 3.0, 4.0)
	assert_vector((_collider("Crate").shape as BoxShape3D).size).is_equal(Vector3(2.0, 3.0, 4.0))
	var barrel := _collider("Barrel").shape as CylinderShape3D
	assert_float(barrel.radius).is_equal(1.0)
	assert_float(barrel.height).is_equal(3.0)
	assert_float((_collider("Ball").shape as SphereShape3D).radius).is_equal(1.0)
	assert_float((_mesh("Barrel").mesh as CylinderMesh).height).is_equal(3.0)
	assert_float((_mesh("Ball").mesh as SphereMesh).radius).is_equal(1.0)


func test_two_props_do_not_share_a_size() -> void:
	var other := load(SCENE).instantiate() as PhysicsProp
	add_child(other)
	other.size = Vector3(5.0, 5.0, 5.0)
	assert_vector((_collider("Crate").shape as BoxShape3D).size).is_equal(Vector3.ONE)
	other.free()


func test_the_material_paints_every_mesh() -> void:
	var paint := StandardMaterial3D.new()
	_prop.material = paint
	for part_name in ["Crate", "Barrel", "Ball"]:
		assert_object(_mesh(part_name).material_override).is_same(paint)


func test_the_weight_is_the_bodys_mass_and_the_surface_follows_grip_and_bounciness() -> void:
	_prop.weight = 55.0
	assert_float(_prop.mass).is_equal(55.0)
	_prop.grip = 0.2
	_prop.bounciness = 0.7
	assert_float(_prop.physics_material_override.friction).is_equal_approx(0.2, 0.0001)
	assert_float(_prop.physics_material_override.bounce).is_equal_approx(0.7, 0.0001)


func test_the_fall_limit_sends_it_back_to_where_it_started() -> void:
	var returned := []
	_prop.returned.connect(func() -> void: returned.append(true))
	_prop.global_position = Vector3(0.0, -5.0, 0.0)
	_prop.fall_limit = -2.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_array(returned).has_size(1)
	assert_float(_prop.global_position.y).is_greater(-2.0)
