# The prototype block's inspector contract: defaults pinned, and each setting changed on a
# running block and its effect read in the mesh, the collision and the material.
extends GdUnitTestSuite

const SCENE := "res://world/blocks/proto_block.tscn"

var _block: ProtoBlock


func before_test() -> void:
	_block = load(SCENE).instantiate() as ProtoBlock
	add_child(_block)


func after_test() -> void:
	_block.free()


func _shapes() -> Array[CollisionShape3D]:
	var found: Array[CollisionShape3D] = []
	for child in (_block.get_node("%Body") as StaticBody3D).get_children():
		found.append(child)
	return found


func test_every_export_has_its_default_pinned() -> void:
	var pins := {
		&"kind": ProtoBlock.Kind.BOX,
		&"size": Vector3(2.0, 2.0, 2.0),
		&"steps": 8,
		&"material": null,
	}
	assert_array(ExportPins.differences(_block, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_block, pins)).is_empty()


func test_the_scene_holds_its_body_and_has_no_warning() -> void:
	assert_object(_block.get_node("%Body")).is_not_null()
	assert_array(_block._get_configuration_warnings()).is_empty()


func test_the_size_resizes_the_mesh_and_the_collision_together() -> void:
	_block.size = Vector3(6.0, 1.0, 3.0)
	assert_vector(_block.mesh.get_aabb().size).is_equal_approx(
		Vector3(6.0, 1.0, 3.0), Vector3.ONE * 0.001
	)
	assert_int(_shapes().size()).is_equal(1)
	assert_vector((_shapes()[0].shape as BoxShape3D).size).is_equal(Vector3(6.0, 1.0, 3.0))


func test_the_kind_changes_the_shape_of_both() -> void:
	_block.kind = ProtoBlock.Kind.CYLINDER
	assert_object(_shapes()[0].shape).is_instanceof(CylinderShape3D)
	_block.kind = ProtoBlock.Kind.RAMP
	assert_object(_shapes()[0].shape).is_instanceof(ConvexPolygonShape3D)
	_block.kind = ProtoBlock.Kind.STAIRS
	assert_int(_shapes().size()).is_equal(_block.steps)


func test_the_steps_set_how_many_boxes_a_staircase_has() -> void:
	_block.kind = ProtoBlock.Kind.STAIRS
	_block.steps = 4
	assert_int(_shapes().size()).is_equal(4)
	_block.steps = 12
	assert_int(_shapes().size()).is_equal(12)


func test_the_material_paints_the_mesh() -> void:
	var paint := StandardMaterial3D.new()
	_block.material = paint
	assert_object(_block.material_override).is_same(paint)
