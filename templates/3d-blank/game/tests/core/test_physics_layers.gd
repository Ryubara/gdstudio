# The physics layers have names: the project's `[layer_names]` and `PhysicsLayers` agree, and no
# scene of the game uses a layer bit the project does not name (a body's layer and mask, and every
# inspector value shown as a layer grid: a camera's wall mask, a weapon's aim mask).
extends GdUnitTestSuite

## Folders whose scenes are not the game's own.
const SKIPPED := ["res://addons", "res://tests", "res://.godot"]


func _scenes(folder: String, found: Array[String]) -> Array[String]:
	if SKIPPED.has(folder.trim_suffix("/")):
		return found
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".tscn"):
			found.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		_scenes(folder.path_join(sub), found)
	return found


# Every layer-grid value of `node`, as "path:property" -> bits.
func _layer_values(node: Node, root: Node, into: Dictionary) -> void:
	for property in node.get_property_list():
		if property.hint != PROPERTY_HINT_LAYERS_3D_PHYSICS:
			continue
		if property.type != TYPE_INT:
			continue
		var at := "%s:%s" % [root.get_path_to(node), property.name]
		into[at] = int(node.get(property.name))
	for child in node.get_children():
		_layer_values(child, root, into)


func test_the_project_names_every_layer_the_constants_name() -> void:
	for layer: int in PhysicsLayers.NAMES:
		assert_str(PhysicsLayers.project_name(layer)).is_equal(PhysicsLayers.NAMES[layer])
	var bits := {
		PhysicsLayers.WORLD: "World",
		PhysicsLayers.CHARACTERS: "Characters",
		PhysicsLayers.PROJECTILES: "Projectiles",
		PhysicsLayers.PROPS: "Props",
		PhysicsLayers.RAGDOLL: "Ragdoll",
		PhysicsLayers.HIT_ZONES: "Hit Zones",
		PhysicsLayers.SENSORS: "Sensors",
	}
	for bit: int in bits:
		assert_str(PhysicsLayers.project_name(PhysicsLayers.number(bit))).is_equal(bits[bit])


func test_the_two_layers_that_were_numbers_kept_their_place() -> void:
	# Projectiles were on 4 and ragdoll bones on 16 before the layers had names.
	assert_int(PhysicsLayers.PROJECTILES).is_equal(4)
	assert_int(PhysicsLayers.RAGDOLL).is_equal(16)
	assert_int(PhysicsLayers.number(PhysicsLayers.WORLD)).is_equal(1)
	assert_int(PhysicsLayers.number(PhysicsLayers.SENSORS)).is_equal(7)


func test_a_bit_with_no_name_is_found() -> void:
	assert_array(PhysicsLayers.unnamed(PhysicsLayers.WORLD | PhysicsLayers.SENSORS)).is_empty()
	assert_array(PhysicsLayers.unnamed(1 << 20 | PhysicsLayers.WORLD)).contains_exactly([21])


func test_no_scene_uses_a_layer_the_project_does_not_name() -> void:
	var scenes := _scenes("res://", [] as Array[String])
	assert_array(scenes).is_not_empty()
	var unnamed: Array[String] = []
	for path in scenes:
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var values := {}
		_layer_values(root, root, values)
		for at: String in values:
			var missing := PhysicsLayers.unnamed(values[at])
			if not missing.is_empty():
				unnamed.append("%s %s: layers %s" % [path, at, missing])
		root.free()
	assert_array(unnamed).is_empty()
