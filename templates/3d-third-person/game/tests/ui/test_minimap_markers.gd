# The minimap's markers: an icon follows each node that carries a marker, sticks to the border
# when its thing is off the map, hides by its rules, and comes from a pool that is reused.
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
	# The marker group is the tree's: leave no marker for the next suite.
	for marker in get_tree().get_nodes_in_group(MinimapMarker.GROUP):
		marker.get_parent().queue_free()


func test_an_icon_follows_the_node_that_carries_the_marker() -> void:
	var carrier := _carry(Vector3(6.0, 0.0, -12.0))
	_minimap.refresh_now()
	var marker := _marker_of(carrier)
	var icon := _minimap.icon_for(marker)
	assert_object(icon).is_not_null()
	# 30 m to the border is 110 px: 3.667 px a metre, north is up.
	assert_vector(_centre_of(icon)).is_equal_approx(Vector2(132.0, 66.0), Vector2(0.01, 0.01))
	carrier.global_position = Vector3(-9.0, 0.0, 3.0)
	_minimap.refresh_now()
	assert_vector(_centre_of(icon)).is_equal_approx(Vector2(77.0, 121.0), Vector2(0.01, 0.01))


func test_the_icon_takes_the_markers_look() -> void:
	var carrier := _carry(Vector3(3.0, 0.0, 3.0))
	var marker := _marker_of(carrier)
	marker.color = Color(1.0, 0.2, 0.1, 1.0)
	marker.size = 20.0
	marker.draw_order = 3
	var picture := load("res://assets/ui/minimap/diamond.png") as Texture2D
	marker.icon = picture
	_minimap.refresh_now()
	var icon := _minimap.icon_for(marker)
	assert_object(icon.texture).is_same(picture)
	assert_float(icon.drawn_side()).is_equal_approx(20.0, 0.001)
	assert_int(icon.z_index).is_equal(3)
	assert_bool(icon.modulate.is_equal_approx(Color(1.0, 0.2, 0.1, 1.0))).is_true()
	_minimap.marker_scale = 2.0
	_minimap.refresh_now()
	assert_float(icon.drawn_side()).is_equal_approx(40.0, 0.001)


func test_a_marker_that_turns_with_its_node_turns_its_icon() -> void:
	var carrier := _carry(Vector3(3.0, 0.0, 3.0))
	var marker := _marker_of(carrier)
	marker.rotates_with_node = true
	_minimap.refresh_now()
	var icon := _minimap.icon_for(marker)
	assert_float(icon.rotation).is_equal_approx(0.0, 0.001)
	carrier.rotate_y(-PI * 0.5)
	_minimap.refresh_now()
	assert_float(icon.rotation).is_equal_approx(PI * 0.5, 0.001)


func test_a_marker_off_the_map_sticks_to_the_border_when_it_clamps() -> void:
	var carrier := _carry(Vector3(100.0, 0.0, 0.0))
	var marker := _marker_of(carrier)
	marker.clamp_to_edge = true
	marker.edge_inset = 6.0
	_minimap.refresh_now()
	var icon := _minimap.icon_for(marker)
	assert_object(icon).is_not_null()
	var from_middle := _centre_of(icon) - Vector2(110.0, 110.0)
	assert_float(from_middle.length()).is_equal_approx(104.0, 0.01)
	assert_float(from_middle.angle()).is_equal_approx(0.0, 0.001)
	# It points outward: right.
	assert_float(icon.rotation).is_equal_approx(PI * 0.5, 0.001)
	carrier.global_position = Vector3(0.0, 0.0, 100.0)
	_minimap.refresh_now()
	assert_float((_centre_of(icon) - Vector2(110.0, 110.0)).angle()).is_equal_approx(
		PI * 0.5, 0.001
	)


func test_a_marker_off_the_map_hides_when_it_does_not_clamp() -> void:
	var carrier := _carry(Vector3(100.0, 0.0, 0.0))
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(_marker_of(carrier))).is_null()
	carrier.global_position = Vector3(10.0, 0.0, 0.0)
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(_marker_of(carrier))).is_not_null()


func test_a_marker_that_comes_back_on_the_map_gets_its_icon_again() -> void:
	var carrier := _carry(Vector3(100.0, 0.0, 0.0))
	var marker := _marker_of(carrier)
	marker.clamp_to_edge = true
	_minimap.refresh_now()
	assert_int(_minimap.shown_count()).is_equal(1)
	marker.active = false
	_minimap.refresh_now()
	assert_int(_minimap.shown_count()).is_equal(0)
	marker.active = true
	_minimap.refresh_now()
	assert_int(_minimap.shown_count()).is_equal(1)


func test_the_visibility_rules_hide_a_marker() -> void:
	var carrier := _carry(Vector3(10.0, 0.0, 0.0))
	var marker := _marker_of(carrier)
	marker.rule = MinimapMarker.Rule.FLAGGED
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(marker)).is_null()
	marker.revealed = true
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(marker)).is_not_null()
	marker.rule = MinimapMarker.Rule.NEAR
	marker.near_distance = 5.0
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(marker)).is_null()
	marker.near_distance = 15.0
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(marker)).is_not_null()


func test_a_marker_in_another_section_hides_by_the_same_section_rule() -> void:
	var here := _section(Vector3.ZERO, Vector3(40.0, 10.0, 40.0))
	var carrier := _carry(Vector3(10.0, 0.0, 0.0))
	var marker := _marker_of(carrier)
	marker.rule = MinimapMarker.Rule.SAME_SECTION
	_minimap.refresh_now()
	assert_object(_minimap.current_section()).is_same(here)
	assert_object(_minimap.icon_for(marker)).is_not_null()
	_section(Vector3(10.0, 0.0, 0.0), Vector3(4.0, 10.0, 4.0))
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(marker)).is_null()


func test_a_kind_can_be_left_out_of_one_minimap() -> void:
	var carrier := _carry(Vector3(5.0, 0.0, 0.0))
	var marker := _marker_of(carrier)
	marker.kind = &"enemy"
	_minimap.hidden_kinds = PackedStringArray(["enemy"])
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(marker)).is_null()
	_minimap.hidden_kinds = PackedStringArray(["pickup"])
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(marker)).is_not_null()


func test_a_marker_above_or_below_fades_when_it_asks_to() -> void:
	var carrier := _carry(Vector3(5.0, 8.0, 0.0))
	var marker := _marker_of(carrier)
	_minimap.refresh_now()
	assert_float(_minimap.icon_for(marker).modulate.a).is_equal_approx(1.0, 0.001)
	marker.height_fade = 10.0
	_minimap.refresh_now()
	assert_float(_minimap.icon_for(marker).modulate.a).is_less(0.5)


func test_the_target_is_not_drawn_twice_while_the_map_follows_it() -> void:
	var own := _marker_of(_attach_marker(_subject))
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(own)).is_null()
	assert_bool((_minimap.get_node("%Self") as Control).visible).is_true()
	_minimap.follow_target = false
	_minimap.refresh_now()
	assert_object(_minimap.icon_for(own)).is_not_null()
	assert_bool((_minimap.get_node("%Self") as Control).visible).is_false()


func test_the_pool_makes_an_icon_for_a_marker_once_and_reuses_it() -> void:
	var carriers: Array[Node3D] = []
	for i in 200:
		carriers.append(_carry(Vector3(randf_range(-20.0, 20.0), 0.0, randf_range(-20.0, 20.0))))
	_minimap.refresh_now()
	assert_int(_minimap.shown_count()).is_equal(200)
	assert_int(_minimap.pool().made()).is_equal(200)
	for i in 100:
		carriers[i].free()
	_minimap.refresh_now()
	assert_int(_minimap.shown_count()).is_equal(100)
	assert_int(_minimap.pool().in_use()).is_equal(100)
	for i in 100:
		_carry(Vector3(randf_range(-20.0, 20.0), 0.0, randf_range(-20.0, 20.0)))
	_minimap.refresh_now()
	assert_int(_minimap.shown_count()).is_equal(200)
	assert_int(_minimap.pool().made()).is_equal(200)


func test_the_cap_stops_a_flood_of_markers() -> void:
	_minimap.max_markers = 50
	for i in 120:
		_carry(Vector3(randf_range(-20.0, 20.0), 0.0, randf_range(-20.0, 20.0)))
	_minimap.refresh_now()
	assert_int(_minimap.shown_count()).is_equal(50)


func test_markers_are_placed_at_their_own_rate() -> void:
	var carrier := _carry(Vector3(6.0, 0.0, 0.0))
	var marker := _marker_of(carrier)
	_minimap.marker_update_rate = 2.0
	_minimap.refresh_now()
	var icon := _minimap.icon_for(marker)
	var first := _centre_of(icon)
	carrier.global_position = Vector3(12.0, 0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(_centre_of(icon)).is_equal(first)
	await InputSim.ticks(get_tree(), 36)
	assert_vector(_centre_of(icon)).is_not_equal(first)


func _carry(at: Vector3) -> Node3D:
	var carrier := auto_free(Node3D.new()) as Node3D
	add_child(carrier)
	carrier.global_position = at
	_attach_marker(carrier)
	return carrier


func _attach_marker(carrier: Node3D) -> Node3D:
	var marker := MinimapMarker.new()
	carrier.add_child(marker)
	return carrier


func _marker_of(carrier: Node3D) -> MinimapMarker:
	for child in carrier.get_children():
		if child is MinimapMarker:
			return child
	return null


func _centre_of(icon: MinimapIcon) -> Vector2:
	return icon.position


func _section(at: Vector3, size: Vector3) -> MinimapSection:
	var section := auto_free(MinimapSection.new()) as MinimapSection
	section.size = size
	add_child(section)
	section.global_position = at
	return section
