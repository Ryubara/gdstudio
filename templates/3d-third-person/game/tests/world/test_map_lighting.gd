# The map and its sections are lit the same way and every block is in its scene's bake (kit #885):
# a block added or moved after the last bake keeps an old mesh or no lightmap and reads lit
# differently from its neighbours (the ragdoll ledge of #871 was not in the lightmap). Bake again
# with `tools/map_bake/` after changing a block.
extends GdUnitTestSuite

const SCENES := [
	"res://world/prototype/prototype_level.tscn",
	"res://world/prototype/ai_section/ai_section.tscn",
	"res://world/prototype/pathing_section/pathing_section.tscn",
]


func _scene(path: String) -> Node3D:
	var scene: Node3D = auto_free(load(path).instantiate())
	add_child(scene)
	return scene


func test_every_block_carries_a_saved_mesh_of_its_size() -> void:
	for path: String in SCENES:
		var scene := _scene(path)
		for block: ProtoBlock in scene.find_children("*", "ProtoBlock", true, false):
			var expected := block.size
			if block.kind == ProtoBlock.Kind.CYLINDER:
				expected = Vector3(block.size.x, block.size.y, block.size.x)
			(
				assert_vector(block.mesh.get_aabb().size)
				. override_failure_message("%s %s" % [path.get_file(), scene.get_path_to(block)])
				. is_equal_approx(expected, Vector3.ONE * 0.001)
			)


func test_every_block_is_in_its_scenes_lightmap() -> void:
	for path: String in SCENES:
		var scene := _scene(path)
		var lightmap: LightmapGI = scene.find_children("*", "LightmapGI", true, false)[0]
		var baked := {}
		# The saved users: a flat list of a node path, its UV scale, its slice and its instance each.
		for entry: Variant in lightmap.light_data.get("user_data"):
			if entry is NodePath:
				baked[str(entry)] = true
		assert_int(baked.size()).override_failure_message(path).is_greater(10)
		for block: ProtoBlock in scene.find_children("*", "ProtoBlock", true, false):
			var key := str(lightmap.get_path_to(block))
			(
				assert_bool(baked.has(key))
				. override_failure_message("%s: %s is not in the lightmap" % [path.get_file(), key])
				. is_true()
			)


func test_the_sections_bake_with_the_maps_lightmap_settings() -> void:
	var map: LightmapGI = _scene(SCENES[0]).find_children("*", "LightmapGI", true, false)[0]
	for path: String in SCENES.slice(1):
		var lightmap: LightmapGI = _scene(path).find_children("*", "LightmapGI", true, false)[0]
		for property in [
			"quality",
			"bounces",
			"texel_scale",
			"max_texture_size",
			"environment_mode",
			"environment_custom_color",
			"environment_custom_energy",
		]:
			(
				assert_that(lightmap.get(property))
				. override_failure_message("%s: %s" % [path.get_file(), property])
				. is_equal(map.get(property))
			)


func test_a_section_has_no_sun_of_its_own() -> void:
	# The map's sun lights a section where it is placed; a second one would light it twice.
	for path: String in SCENES.slice(1):
		var scene := _scene(path)
		assert_array(scene.find_children("*", "DirectionalLight3D", true, false)).is_empty()
		assert_array(scene.find_children("*", "WorldEnvironment", true, false)).is_empty()


func test_every_scenes_lightmap_holds_light() -> void:
	# A bake that saw no light writes an atlas of black texels: the section's shaded faces then
	# read black beside the map's. The sections were baked so once, with the map's sun added for
	# the bake but not owned by the scene (the bake leaves out a node with no owner).
	for path: String in SCENES:
		var atlas := ProjectSettings.globalize_path(path.get_basename() + ".exr")
		var image := Image.load_from_file(atlas)
		var lit := 0
		var count := 0
		for y in range(0, image.get_height(), 2):
			for x in range(0, image.get_width(), 2):
				count += 1
				if image.get_pixel(x, y).get_luminance() > 0.001:
					lit += 1
		(
			assert_float(float(lit) / count)
			. override_failure_message("%s: %d of %d texels lit" % [path.get_file(), lit, count])
			. is_greater(0.1)
		)
