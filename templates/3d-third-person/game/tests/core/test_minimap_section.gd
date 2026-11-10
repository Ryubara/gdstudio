# A section is an axis-aligned box of the world: what it holds, its footprint, and which of two
# overlapping boxes a place belongs to.
extends GdUnitTestSuite

const SCENE := "res://core/minimap/minimap_section.tscn"
const DEFAULTS := {
	&"title": "",
	&"size": Vector3(30.0, 8.0, 30.0),
	&"level": 0,
	&"map_texture": null,
}


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(load(SCENE).instantiate()) as MinimapSection
	assert_array(ExportPins.differences(fresh, DEFAULTS)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, DEFAULTS)).is_empty()


func test_the_scene_holds_a_preview_that_the_game_hides() -> void:
	var section := auto_free(load(SCENE).instantiate()) as MinimapSection
	add_child(section)
	var preview := section.get_node("%Preview") as MeshInstance3D
	assert_bool(preview.visible).is_false()
	section.size = Vector3(10.0, 4.0, 6.0)
	assert_vector((preview.mesh as BoxMesh).size).is_equal(Vector3(10.0, 4.0, 6.0))


func test_it_holds_the_points_inside_its_box() -> void:
	var section := _section(Vector3(10.0, 2.0, -10.0), Vector3(8.0, 4.0, 6.0))
	assert_bool(section.contains(Vector3(10.0, 2.0, -10.0))).is_true()
	assert_bool(section.contains(Vector3(13.9, 3.9, -12.9))).is_true()
	assert_bool(section.contains(Vector3(14.1, 2.0, -10.0))).is_false()
	assert_bool(section.contains(Vector3(10.0, 4.1, -10.0))).is_false()
	assert_bool(section.contains(Vector3(10.0, 2.0, -13.1))).is_false()


func test_its_footprint_and_heights() -> void:
	var section := _section(Vector3(10.0, 2.0, -10.0), Vector3(8.0, 4.0, 6.0))
	assert_vector(section.footprint().position).is_equal(Vector2(6.0, -13.0))
	assert_vector(section.footprint().size).is_equal(Vector2(8.0, 6.0))
	assert_float(section.top_y()).is_equal(4.0)
	assert_float(section.bottom_y()).is_equal(0.0)


func test_the_smaller_of_two_overlapping_sections_wins() -> void:
	var big := _section(Vector3.ZERO, Vector3(40.0, 10.0, 40.0))
	var small := _section(Vector3(5.0, 0.0, 5.0), Vector3(6.0, 4.0, 6.0))
	assert_object(MinimapSection.at(get_tree(), Vector3(5.0, 0.0, 5.0))).is_same(small)
	assert_object(MinimapSection.at(get_tree(), Vector3(-15.0, 0.0, 0.0))).is_same(big)
	assert_object(MinimapSection.at(get_tree(), Vector3(90.0, 0.0, 0.0))).is_null()


func test_floors_are_told_apart_by_height() -> void:
	var ground := _section(Vector3(0.0, 2.0, 0.0), Vector3(20.0, 4.0, 20.0))
	var upper := _section(Vector3(0.0, 6.0, 0.0), Vector3(20.0, 4.0, 20.0))
	assert_object(MinimapSection.at(get_tree(), Vector3(0.0, 1.0, 0.0))).is_same(ground)
	assert_object(MinimapSection.at(get_tree(), Vector3(0.0, 7.0, 0.0))).is_same(upper)


func _section(at: Vector3, size: Vector3) -> MinimapSection:
	var section := auto_free(MinimapSection.new()) as MinimapSection
	section.size = size
	add_child(section)
	section.global_position = at
	return section
