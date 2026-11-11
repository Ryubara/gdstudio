# The marker any node can carry: it finds the place and the facing of its parent (3D or 2D), puts
# itself in the group the minimaps read, and its rules decide when it shows.
extends GdUnitTestSuite

const DEFAULTS := {
	&"icon": null,
	&"color": Color(1.0, 1.0, 1.0, 1.0),
	&"size": 14.0,
	&"rotates_with_node": false,
	&"kind": &"",
	&"draw_order": 0,
	&"clamp_to_edge": false,
	&"edge_inset": 6.0,
	&"edge_icon": null,
	&"active": true,
	&"rule": 0,
	&"near_distance": 30.0,
	&"revealed": false,
	&"height_fade": 0.0,
}


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(MinimapMarker.new()) as MinimapMarker
	assert_array(ExportPins.differences(fresh, DEFAULTS)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, DEFAULTS)).is_empty()


func test_it_is_in_the_marker_group_while_in_the_tree() -> void:
	var carrier := _carrier()
	var marker := _marker(carrier)
	assert_bool(get_tree().get_nodes_in_group(MinimapMarker.GROUP).has(marker)).is_true()
	carrier.remove_child(marker)
	assert_bool(get_tree().get_nodes_in_group(MinimapMarker.GROUP).has(marker)).is_false()
	marker.free()


func test_a_3d_parent_is_at_x_and_z_with_north_being_minus_z() -> void:
	var carrier := _carrier(Vector3(4.0, 7.0, -9.0))
	var marker := _marker(carrier)
	assert_vector(marker.plane_position()).is_equal(Vector2(4.0, -9.0))
	assert_float(marker.height()).is_equal(7.0)
	assert_vector(marker.position_3d()).is_equal(Vector3(4.0, 7.0, -9.0))
	# Facing -Z is facing north; turning the parent a quarter left (+90 degrees about Y) faces west.
	assert_vector(marker.heading()).is_equal_approx(Vector2(0.0, -1.0), Vector2(0.001, 0.001))
	carrier.rotate_y(PI * 0.5)
	assert_vector(marker.heading()).is_equal_approx(Vector2(-1.0, 0.0), Vector2(0.001, 0.001))


func test_a_2d_parent_is_at_x_and_y() -> void:
	var carrier := auto_free(Node2D.new()) as Node2D
	add_child(carrier)
	carrier.global_position = Vector2(12.0, -3.0)
	var marker := MinimapMarker.new()
	carrier.add_child(marker)
	assert_vector(marker.plane_position()).is_equal(Vector2(12.0, -3.0))
	assert_float(marker.height()).is_equal(0.0)
	carrier.rotation = PI * 0.5
	assert_vector(marker.heading()).is_equal_approx(Vector2(0.0, 1.0), Vector2(0.001, 0.001))


func test_a_parent_with_a_heading_source_faces_where_its_model_turns() -> void:
	var carrier := _carrier()
	var model := Node3D.new()
	carrier.add_child(model)
	var source := MinimapHeading.new()
	source.turns = model
	source.front = MinimapHeading.Front.PLUS_Z
	carrier.add_child(source)
	# The body stays put; the model's front (+Z) turned a quarter left faces east.
	model.rotate_y(PI * 0.5)
	assert_vector(_marker(carrier).heading()).is_equal_approx(
		Vector2(1.0, 0.0), Vector2(0.001, 0.001)
	)


func test_a_parent_without_a_heading_source_ignores_a_turning_child() -> void:
	var carrier := _carrier()
	var model := Node3D.new()
	carrier.add_child(model)
	model.rotate_y(PI * 0.5)
	assert_vector(_marker(carrier).heading()).is_equal_approx(
		Vector2(0.0, -1.0), Vector2(0.001, 0.001)
	)


func test_the_near_rule_counts_metres_from_the_viewer() -> void:
	var marker := _marker(_carrier(Vector3(20.0, 0.0, 0.0)))
	marker.rule = MinimapMarker.Rule.NEAR
	marker.near_distance = 25.0
	assert_bool(marker.passes_rule(Vector2.ZERO, null)).is_true()
	assert_bool(marker.passes_rule(Vector2(-10.0, 0.0), null)).is_false()


func test_the_flagged_rule_waits_for_the_game_to_reveal_it() -> void:
	var marker := _marker(_carrier())
	marker.rule = MinimapMarker.Rule.FLAGGED
	assert_bool(marker.passes_rule(Vector2.ZERO, null)).is_false()
	marker.revealed = true
	assert_bool(marker.passes_rule(Vector2.ZERO, null)).is_true()


func test_the_same_section_rule_compares_the_sections_of_marker_and_viewer() -> void:
	var inside := _section(Vector3.ZERO, Vector3(10.0, 6.0, 10.0))
	var other := _section(Vector3(50.0, 0.0, 0.0), Vector3(10.0, 6.0, 10.0))
	var marker := _marker(_carrier(Vector3(2.0, 0.0, 2.0)))
	marker.rule = MinimapMarker.Rule.SAME_SECTION
	assert_bool(marker.passes_rule(Vector2.ZERO, inside)).is_true()
	assert_bool(marker.passes_rule(Vector2.ZERO, other)).is_false()
	assert_bool(marker.passes_rule(Vector2.ZERO, null)).is_false()


func test_a_marker_in_no_section_matches_a_viewer_in_none() -> void:
	var marker := _marker(_carrier(Vector3(100.0, 0.0, 100.0)))
	marker.rule = MinimapMarker.Rule.SAME_SECTION
	assert_bool(marker.passes_rule(Vector2.ZERO, null)).is_true()


func _carrier(at := Vector3.ZERO) -> Node3D:
	var carrier := auto_free(Node3D.new()) as Node3D
	add_child(carrier)
	carrier.global_position = at
	var marker := MinimapMarker.new()
	carrier.add_child(marker)
	return carrier


func _marker(carrier: Node) -> MinimapMarker:
	return carrier.get_child(0) as MinimapMarker


func _section(at: Vector3, size: Vector3) -> MinimapSection:
	var section := auto_free(MinimapSection.new()) as MinimapSection
	section.size = size
	add_child(section)
	section.global_position = at
	return section
