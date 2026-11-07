# The prototype level is solid, lit and made of the shared prototype materials.
extends GdUnitTestSuite

const LEVEL := "res://world/prototype/prototype_level.tscn"
const MATERIAL_FOLDER := "res://assets/materials/prototype/"


func _level() -> Node3D:
	var level: Node3D = auto_free(load(LEVEL).instantiate())
	add_child(level)
	return level


func _shapes(level: Node) -> Array[CSGShape3D]:
	var found: Array[CSGShape3D] = []
	for node in level.find_children("*", "CSGShape3D", true, false):
		found.append(node)
	return found


func test_every_solid_has_collision_and_a_prototype_material() -> void:
	var level := _level()
	var shapes := _shapes(level)
	assert_array(shapes).is_not_empty()
	for shape in shapes:
		if shape.operation == CSGShape3D.OPERATION_SUBTRACTION:
			continue
		assert_bool(shape.use_collision).override_failure_message(shape.name).is_true()
		assert_object(shape.material).override_failure_message(shape.name).is_not_null()
		assert_str(shape.material.resource_path).starts_with(MATERIAL_FOLDER)


func test_the_floor_top_is_at_ground_level() -> void:
	var floor_shape: CSGBox3D = _level().get_node("Boundary/Floor")
	assert_float(floor_shape.position.y + floor_shape.size.y / 2.0).is_equal_approx(0.0, 0.001)


func test_the_level_has_a_sun_with_shadows_and_a_sky() -> void:
	var level := _level()
	var sun: DirectionalLight3D = level.find_children("*", "DirectionalLight3D", true, false)[0]
	assert_bool(sun.shadow_enabled).is_true()
	var world: WorldEnvironment = level.find_children("*", "WorldEnvironment", true, false)[0]
	assert_int(world.environment.background_mode).is_equal(Environment.BG_SKY)
	assert_object(world.environment.sky).is_not_null()


func test_a_dropped_crate_comes_to_rest_on_the_floor() -> void:
	var level := _level()
	var crate := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	crate.add_child(shape)
	crate.position = Vector3(10.0, 3.0, 0.0)
	level.add_child(crate)
	for _frame in 120:
		await get_tree().physics_frame
	assert_float(crate.global_position.y).is_equal_approx(0.5, 0.02)


func test_every_prototype_material_is_the_grid_shader_with_its_own_colour() -> void:
	var seen := {}
	for file in DirAccess.get_files_at(MATERIAL_FOLDER):
		if not file.ends_with(".tres"):
			continue
		var material := load(MATERIAL_FOLDER + file) as ShaderMaterial
		assert_object(material).override_failure_message(file).is_not_null()
		assert_str(material.shader.resource_path).ends_with("prototype_grid.gdshader")
		var colour: Color = material.get_shader_parameter("base_color")
		(
			assert_bool(seen.has(colour))
			. override_failure_message("%s repeats a colour" % file)
			. is_false()
		)
		seen[colour] = true
