# A character's body is drawn on `CharacterModel.body_layers` (layer 2), never on the layer the
# minimap's live camera draws (1): a body is a marker on the map, and drawing it there skinned the
# body a second time each frame (gdstudio #1138: a puppet's frame cost in a browser fell by half).
# The model swapped at run time comes onto the layer too, and a layer something else added (the
# inventory preview's) stays.
extends GdUnitTestSuite

const DRESSED := "res://gameplay/character/character_dressed.tscn"
const PLAYER := "res://gameplay/player/player.tscn"
const MINIMAP := "res://ui/minimap/minimap.tscn"
const MALE := CharacterBodies.MALE
## A layer the inventory preview might add (its default, 20).
const PREVIEW_BIT := 1 << 19


func _body(path: String) -> Character:
	var body := (load(path) as PackedScene).instantiate() as Character
	add_child(body)
	auto_free(body)
	return body


static func _meshes(body: Character) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	for node in body.model.find_children("*", "VisualInstance3D", true, false):
		out.append(node as VisualInstance3D)
	return out


func test_the_minimap_draws_no_layer_of_a_body() -> void:
	var minimap := auto_free((load(MINIMAP) as PackedScene).instantiate()) as Minimap
	var model := auto_free(CharacterModel.new()) as CharacterModel
	assert_int(model.body_layers).is_equal(1 << 1)
	assert_int(minimap.live_layers & model.body_layers).is_equal(0)


func test_every_mesh_of_a_body_is_on_the_body_layer() -> void:
	for path in [DRESSED, PLAYER]:
		var body := _body(path)
		await get_tree().process_frame
		var meshes := _meshes(body)
		# The mannequin, the pistol and its slide and magazine at least.
		assert_int(meshes.size()).is_greater_equal(4)
		for mesh in meshes:
			(
				assert_int(mesh.layers)
				. override_failure_message("%s of %s is on %d" % [mesh.name, path, mesh.layers])
				. is_equal(body.model.body_layers)
			)


func test_a_puppet_is_on_the_body_layer() -> void:
	var puppet := (load(PLAYER) as PackedScene).instantiate() as Player
	puppet.make_puppet()
	add_child(puppet)
	auto_free(puppet)
	await get_tree().process_frame
	for mesh in _meshes(puppet):
		assert_int(mesh.layers & 1).is_equal(0)


func test_a_model_swapped_in_comes_onto_the_layer_and_other_layers_stay() -> void:
	var body := _body(DRESSED)
	await get_tree().process_frame
	var pistol := body.model.get_node("PistolHeld").find_children(
		"*", "MeshInstance3D", true, false
	)
	(pistol[0] as MeshInstance3D).layers |= PREVIEW_BIT
	var old := body.model.rig()
	body.model.remove_child(old)
	old.free()
	var added := (load(MALE) as PackedScene).instantiate() as Node3D
	body.model.add_child(added)
	await get_tree().process_frame
	await get_tree().process_frame
	for mesh in added.find_children("*", "VisualInstance3D", true, false):
		assert_int((mesh as VisualInstance3D).layers).is_equal(body.model.body_layers)
	assert_int((pistol[0] as MeshInstance3D).layers).is_equal(body.model.body_layers | PREVIEW_BIT)


# Every look an online client draws AI characters with is out of the minimap's live view: drawn
# there, a puppet's first draw built the minimap's variants of its programs (no fog, no sun) after
# the seat, which no warm-up drew (gdstudio #1218; the browser gate now fails on any such link).
func test_every_ai_look_is_out_of_the_minimap_view() -> void:
	var minimap := auto_free((load(MINIMAP) as PackedScene).instantiate()) as Minimap
	var replica := auto_free(AiReplica.new()) as AiReplica
	assert_int(replica.variant_scenes.size()).is_greater_equal(1)
	for scene in replica.variant_scenes:
		var body := scene.instantiate() as Character
		add_child(body)
		auto_free(body)
		await get_tree().process_frame
		var meshes := _meshes(body)
		assert_int(meshes.size()).is_greater_equal(4)
		for mesh in meshes:
			(
				assert_int(mesh.layers & minimap.live_layers)
				. override_failure_message(
					"%s of %s is on %d" % [mesh.name, scene.resource_path, mesh.layers]
				)
				. is_equal(0)
			)
