# The prototype level is solid, lit and made of the shared prototype materials.
extends GdUnitTestSuite

const LEVEL := "res://world/prototype/prototype_level.tscn"
const MATERIAL_FOLDER := "res://assets/materials/prototype/"


func _level() -> Node3D:
	var level: Node3D = auto_free(load(LEVEL).instantiate())
	add_child(level)
	return level


func _blocks(level: Node) -> Array[ProtoBlock]:
	var found: Array[ProtoBlock] = []
	for node in level.find_children("*", "ProtoBlock", true, false):
		found.append(node)
	return found


func test_every_block_has_collision_and_a_prototype_material() -> void:
	var level := _level()
	var blocks := _blocks(level)
	assert_array(blocks).is_not_empty()
	for block in blocks:
		assert_object(block.material).override_failure_message(block.name).is_not_null()
		assert_str(block.material.resource_path).starts_with(MATERIAL_FOLDER)
		var body := block.get_node("Body") as StaticBody3D
		assert_int(body.get_child_count()).override_failure_message(block.name).is_greater(0)


func test_every_block_mesh_has_the_second_uv_set_a_lightmap_needs() -> void:
	for block in _blocks(_level()):
		var mesh := block.mesh as ArrayMesh
		assert_object(mesh).override_failure_message(block.name).is_not_null()
		var format := mesh.surface_get_format(0)
		(
			assert_bool((format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0)
			. override_failure_message(block.name)
			. is_true()
		)


func test_the_floor_top_is_at_ground_level() -> void:
	var floor_block: ProtoBlock = _level().get_node("Boundary/Floor")
	assert_float(floor_block.position.y + floor_block.size.y / 2.0).is_equal_approx(0.0, 0.001)


func test_the_level_carries_baked_bounce_light_and_a_dynamic_sun() -> void:
	var level := _level()
	var lightmap: LightmapGI = level.find_children("*", "LightmapGI", true, false)[0]
	assert_object(lightmap.light_data).is_not_null()
	var sun: DirectionalLight3D = level.find_children("*", "DirectionalLight3D", true, false)[0]
	assert_int(sun.light_bake_mode).is_equal(Light3D.BAKE_DYNAMIC)


func test_the_graphics_profile_does_nothing_on_the_compatibility_renderer() -> void:
	var level := _level()
	var profile: GraphicsProfile = level.find_children("*", "GraphicsProfile", true, false)[0]
	var world: WorldEnvironment = level.find_children("*", "WorldEnvironment", true, false)[0]
	var before := world.environment
	profile.apply()
	if GraphicsProfile.is_supported():
		assert_bool(world.environment.ssao_enabled).is_equal(profile.ambient_occlusion)
	else:
		assert_object(world.environment).is_same(before)


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
