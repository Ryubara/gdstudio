# The baker renders a rectangle of the world top down, north up, at the pixels to the metre asked
# for. It needs a renderer, so the check runs in a windowed run and a headless one skips it.
extends GdUnitTestSuite


func test_a_baked_picture_covers_its_rectangle_north_up() -> void:
	if DisplayServer.get_name() == "headless":
		assert_str(DisplayServer.get_name()).is_equal("headless")
		return
	var host := auto_free(Node3D.new()) as Node3D
	add_child(host)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	(box.mesh as BoxMesh).size = Vector3(4.0, 1.0, 4.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material_override = material
	host.add_child(box)
	box.global_position = Vector3(6.0, 0.0, -6.0)
	await get_tree().process_frame
	var image := await MinimapBaker.bake(host, Rect2(-10.0, -10.0, 20.0, 20.0), 8.0, 10.0, 20.0)
	assert_int(image.get_width()).is_equal(160)
	assert_int(image.get_height()).is_equal(160)
	# Six metres east and six north of the middle: right of the middle, above it.
	var there := image.get_pixel(128, 32)
	assert_float(there.r).is_greater(0.8)
	assert_float(there.g).is_less(0.2)
	var mirrored := image.get_pixel(32, 128)
	assert_float(mirrored.r).is_less(0.2)
