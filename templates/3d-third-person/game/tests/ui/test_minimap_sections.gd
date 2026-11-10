# The minimap's sections and sources: a section slices the live camera, names the map and may bring
# its own picture, and the image source lays a texture over a rectangle.
extends GdUnitTestSuite

const SCENE := "res://ui/minimap/minimap.tscn"

var _root: Control
var _minimap: Minimap
var _subject: Node3D


func before_test() -> void:
	_root = auto_free(Control.new()) as Control
	_root.size = Vector2(800.0, 600.0)
	add_child(_root)
	_subject = auto_free(Node3D.new()) as Node3D
	add_child(_subject)
	_minimap = load(SCENE).instantiate() as Minimap
	_minimap.target = _subject
	_minimap.pool_prewarm = 0
	_minimap.zoom_smoothing = 0.0
	_minimap.turn_smoothing = 0.0
	_root.add_child(_minimap)
	await get_tree().process_frame
	await get_tree().process_frame


func after_test() -> void:
	InputSim.release_all()
	for marker in get_tree().get_nodes_in_group(MinimapMarker.GROUP):
		marker.get_parent().queue_free()


func test_a_section_slices_the_live_camera_to_its_height_and_names_the_map() -> void:
	var seen: Array[MinimapSection] = []
	_minimap.section_changed.connect(func(section: MinimapSection) -> void: seen.append(section))
	var room := _section(Vector3(0.0, 2.0, 0.0), Vector3(20.0, 4.0, 20.0), "Room")
	_subject.global_position = Vector3(1.0, 0.5, 1.0)
	_minimap.refresh_now()
	var camera := _minimap.get_node("%MapCamera") as Camera3D
	assert_object(_minimap.current_section()).is_same(room)
	assert_float(camera.global_position.y).is_equal_approx(4.0, 0.001)
	assert_float(camera.far).is_equal_approx(4.1, 0.001)
	var title := _minimap.get_node("%SectionTitle") as Label
	assert_bool(title.visible).is_true()
	assert_str(title.text).is_equal("Room")
	assert_array(seen).has_size(1)
	_subject.global_position = Vector3(40.0, 0.5, 40.0)
	_minimap.refresh_now()
	assert_object(_minimap.current_section()).is_null()
	assert_bool(title.visible).is_false()
	assert_array(seen).has_size(2)
	assert_float(camera.global_position.y).is_equal_approx(40.5, 0.001)


func test_a_section_can_be_shown_whatever_the_target_is_in() -> void:
	var room := _section(Vector3(30.0, 2.0, 0.0), Vector3(10.0, 4.0, 10.0), "Annex")
	_subject.global_position = Vector3.ZERO
	_minimap.refresh_now()
	assert_object(_minimap.current_section()).is_null()
	_minimap.show_section(room)
	_minimap.refresh_now()
	assert_object(_minimap.current_section()).is_same(room)
	_minimap.show_section(null)
	_minimap.refresh_now()
	assert_object(_minimap.current_section()).is_null()


func test_a_section_with_its_own_picture_uses_it() -> void:
	var room := _section(Vector3(0.0, 2.0, 0.0), Vector3(20.0, 4.0, 10.0), "Room")
	room.map_texture = load("res://assets/ui/minimap/square.png")
	var taken := _minimap.snapshots_taken()
	_minimap.refresh_now()
	var material := (_minimap.get_node("%Map") as ColorRect).material as ShaderMaterial
	assert_bool(material.get_shader_parameter(&"has_map")).is_true()
	assert_vector(material.get_shader_parameter(&"source_centre")).is_equal(Vector2(0.0, 0.0))
	assert_vector(material.get_shader_parameter(&"source_half")).is_equal(Vector2(10.0, 5.0))
	assert_float(material.get_shader_parameter(&"source_turn")).is_equal(0.0)
	assert_int(_minimap.snapshots_taken()).is_equal(taken)


func test_the_image_source_lays_a_texture_over_its_rectangle() -> void:
	var taken := _minimap.snapshots_taken()
	_minimap.source = Minimap.Source.IMAGE
	_minimap.refresh_now()
	var material := (_minimap.get_node("%Map") as ColorRect).material as ShaderMaterial
	assert_bool(material.get_shader_parameter(&"has_map")).is_false()
	_minimap.image = load("res://assets/ui/minimap/dot.png")
	_minimap.image_world_rect = Rect2(-10.0, -20.0, 40.0, 60.0)
	_minimap.refresh_now()
	assert_bool(material.get_shader_parameter(&"has_map")).is_true()
	assert_vector(material.get_shader_parameter(&"source_centre")).is_equal(Vector2(10.0, 10.0))
	assert_vector(material.get_shader_parameter(&"source_half")).is_equal(Vector2(20.0, 30.0))
	assert_int(_minimap.snapshots_taken()).is_equal(taken)


func _section(at: Vector3, size: Vector3, title: String) -> MinimapSection:
	var section := auto_free(MinimapSection.new()) as MinimapSection
	section.size = size
	section.title = title
	add_child(section)
	section.global_position = at
	return section
