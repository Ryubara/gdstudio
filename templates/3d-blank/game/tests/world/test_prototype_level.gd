# The prototype level of 3D Blank: a bounded floor and four walls, lit, on the shared prototype
# materials.
extends GdUnitTestSuite

const LEVEL := "res://world/prototype/prototype_level.tscn"
const MATERIAL_FOLDER := "res://assets/materials/prototype/"


func _level() -> Node3D:
	var level: Node3D = auto_free(load(LEVEL).instantiate())
	add_child(level)
	return level


func _pieces(level: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in level.get_node("Boundary").get_children():
		found.append(node)
	return found


func test_the_level_is_a_floor_and_four_walls() -> void:
	var names := []
	for piece in _pieces(_level()):
		names.append(str(piece.name))
	assert_array(names).contains_exactly(
		["Floor", "WallNorth", "WallSouth", "WallWest", "WallEast"]
	)


func test_every_piece_has_collision_and_a_prototype_material() -> void:
	for piece in _pieces(_level()):
		assert_object(piece.material_override).override_failure_message(piece.name).is_not_null()
		assert_str(piece.material_override.resource_path).starts_with(MATERIAL_FOLDER)
		var body := piece.get_node("Body") as StaticBody3D
		assert_int(body.get_child_count()).override_failure_message(piece.name).is_greater(0)


func test_every_piece_mesh_has_the_second_uv_set_a_lightmap_needs() -> void:
	for piece in _pieces(_level()):
		var mesh := piece.mesh as ArrayMesh
		assert_object(mesh).override_failure_message(piece.name).is_not_null()
		var format := mesh.surface_get_format(0)
		(
			assert_bool((format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0)
			. override_failure_message(piece.name)
			. is_true()
		)


func test_the_floor_top_is_at_ground_level() -> void:
	var floor_piece: MeshInstance3D = _level().get_node("Boundary/Floor")
	var size: Vector3 = floor_piece.mesh.get_aabb().size
	assert_float(floor_piece.position.y + size.y / 2.0).is_equal_approx(0.0, 0.001)


func test_the_pieces_sit_on_whole_grid_cells() -> void:
	# A piece moved with the editor's snap on lands on the grid lines: the faces of every piece
	# do.
	var cell: float = ProjectSettings.get_setting("shader_globals/prototype_cell_size")["value"]
	for piece in _pieces(_level()):
		var box := piece.mesh.get_aabb()
		var faces := [
			piece.position.x + box.position.x,
			piece.position.x + box.end.x,
			piece.position.y + box.position.y,
			piece.position.y + box.end.y,
			piece.position.z + box.position.z,
			piece.position.z + box.end.z,
		]
		for face: float in faces:
			var offset := absf(face / cell - roundf(face / cell))
			assert_float(offset).override_failure_message(piece.name).is_less(0.001)


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
	var earlier := world.environment
	profile.apply()
	if GraphicsProfile.is_supported():
		assert_bool(world.environment.ssao_enabled).is_equal(profile.ambient_occlusion)
	else:
		assert_object(world.environment).is_same(earlier)


func test_the_level_has_a_sun_with_shadows_and_a_sky() -> void:
	var level := _level()
	var sun: DirectionalLight3D = level.find_children("*", "DirectionalLight3D", true, false)[0]
	assert_bool(sun.shadow_enabled).is_true()
	var world: WorldEnvironment = level.find_children("*", "WorldEnvironment", true, false)[0]
	assert_int(world.environment.background_mode).is_equal(Environment.BG_SKY)
	assert_object(world.environment.sky).is_not_null()


func test_a_body_cannot_leave_the_floor_through_a_wall() -> void:
	var level := _level()
	var ball := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	ball.add_child(shape)
	ball.position = Vector3(0.0, 0.5, 0.0)
	level.add_child(ball)
	await get_tree().physics_frame
	ball.linear_velocity = Vector3(40.0, 0.0, 0.0)
	for _frame in 120:
		await get_tree().physics_frame
	assert_float(ball.global_position.x).is_less(24.0)


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
