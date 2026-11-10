# The minimap's maths with no nodes: where a place on the map plane lands on the widget, with the
# map north up and turned, at any zoom, and where an icon that is off the map is pulled to.
extends GdUnitTestSuite

var _projector := MinimapProjector.new()


func before_test() -> void:
	_projector = MinimapProjector.new()
	_projector.half_extent = 100.0
	_projector.set_range(50.0)  # two pixels a metre


func test_north_up_puts_north_at_the_top_and_east_to_the_right() -> void:
	_projector.centre = Vector2(10.0, 20.0)
	assert_vector(_projector.to_local(Vector2(10.0, 20.0))).is_equal_approx(
		Vector2.ZERO, Vector2(0.001, 0.001)
	)
	# North is -Z: ten metres north is twenty pixels up.
	assert_vector(_projector.to_local(Vector2(10.0, 10.0))).is_equal_approx(
		Vector2(0.0, -20.0), Vector2(0.001, 0.001)
	)
	assert_vector(_projector.to_local(Vector2(15.0, 20.0))).is_equal_approx(
		Vector2(10.0, 0.0), Vector2(0.001, 0.001)
	)


func test_a_map_that_turns_puts_the_heading_at_the_top() -> void:
	# Facing east (+X): east is up, north is to the left, south to the right.
	_projector.turn = MinimapProjector.turn_for_heading(Vector2.RIGHT)
	assert_vector(_projector.to_local(Vector2(10.0, 0.0))).is_equal_approx(
		Vector2(0.0, -20.0), Vector2(0.001, 0.001)
	)
	assert_vector(_projector.to_local(Vector2(0.0, -10.0))).is_equal_approx(
		Vector2(-20.0, 0.0), Vector2(0.001, 0.001)
	)
	# Facing south (+Z): south is up.
	_projector.turn = MinimapProjector.turn_for_heading(Vector2.DOWN)
	assert_vector(_projector.to_local(Vector2(0.0, 10.0))).is_equal_approx(
		Vector2(0.0, -20.0), Vector2(0.001, 0.001)
	)
	# Facing north changes nothing.
	_projector.turn = MinimapProjector.turn_for_heading(Vector2.UP)
	assert_float(_projector.turn).is_equal_approx(0.0, 0.0001)


func test_the_zoom_is_pixels_per_metre() -> void:
	_projector.set_range(25.0)
	assert_float(_projector.px_per_metre).is_equal_approx(4.0, 0.0001)
	assert_float(_projector.metres_to_border()).is_equal_approx(25.0, 0.0001)
	assert_vector(_projector.to_local(Vector2(5.0, 0.0))).is_equal_approx(
		Vector2(20.0, 0.0), Vector2(0.001, 0.001)
	)


func test_a_place_goes_out_and_back_the_same_at_any_turn() -> void:
	_projector.centre = Vector2(-7.0, 3.0)
	for turn in [0.0, 0.7, 2.5, -1.3]:
		_projector.turn = turn
		var back := _projector.to_world(_projector.to_local(Vector2(4.0, -9.0)))
		assert_vector(back).is_equal_approx(Vector2(4.0, -9.0), Vector2(0.001, 0.001))


func test_a_round_widget_holds_what_is_inside_the_circle() -> void:
	assert_bool(_projector.contains(Vector2(0.0, 99.0))).is_true()
	assert_bool(_projector.contains(Vector2(80.0, 80.0))).is_false()
	assert_bool(_projector.contains(Vector2(0.0, 99.0), 6.0)).is_false()


func test_a_square_widget_holds_its_corners() -> void:
	_projector.circular = false
	assert_bool(_projector.contains(Vector2(80.0, 80.0))).is_true()
	assert_bool(_projector.contains(Vector2(101.0, 0.0))).is_false()


func test_a_place_off_the_map_is_pulled_onto_the_border_in_its_direction() -> void:
	var out := _projector.clamp_to_border(Vector2(300.0, 400.0), 6.0)
	assert_float(out.length()).is_equal_approx(94.0, 0.001)
	assert_float(out.angle()).is_equal_approx(Vector2(300.0, 400.0).angle(), 0.0001)
	# A place inside stays where it is.
	assert_vector(_projector.clamp_to_border(Vector2(10.0, 10.0), 6.0)).is_equal(
		Vector2(10.0, 10.0)
	)
	_projector.circular = false
	var square := _projector.clamp_to_border(Vector2(300.0, 150.0), 6.0)
	assert_float(square.x).is_equal_approx(94.0, 0.001)
	assert_float(square.y).is_equal_approx(47.0, 0.001)


func test_an_icon_points_along_the_way_its_thing_faces_on_the_widget() -> void:
	# North up: a thing facing north points up (no turn), facing east points right.
	assert_float(_projector.icon_rotation(Vector2.UP)).is_equal_approx(0.0, 0.0001)
	assert_float(_projector.icon_rotation(Vector2.RIGHT)).is_equal_approx(PI * 0.5, 0.0001)
	# A map turned to face east: a thing facing east points up.
	_projector.turn = MinimapProjector.turn_for_heading(Vector2.RIGHT)
	assert_float(wrapf(_projector.icon_rotation(Vector2.RIGHT), -PI, PI)).is_equal_approx(
		0.0, 0.0001
	)


func test_an_edge_arrow_points_outward() -> void:
	assert_float(MinimapProjector.outward_rotation(Vector2(0.0, -50.0))).is_equal_approx(
		0.0, 0.0001
	)
	assert_float(MinimapProjector.outward_rotation(Vector2(50.0, 0.0))).is_equal_approx(
		PI * 0.5, 0.0001
	)


func test_a_snapshot_texture_coordinate_is_the_middle_for_its_own_centre() -> void:
	var uv := MinimapProjector.snapshot_uv(
		Vector2(3.0, 4.0), Vector2(3.0, 4.0), 1.2, Vector2(20.0, 20.0)
	)
	assert_vector(uv).is_equal_approx(Vector2(0.5, 0.5), Vector2(0.0001, 0.0001))
	# Ten metres north of the centre of a north-up snapshot that covers 20 either side: a quarter
	# down from the top.
	var north := MinimapProjector.snapshot_uv(
		Vector2(0.0, -10.0), Vector2.ZERO, 0.0, Vector2(20.0, 20.0)
	)
	assert_vector(north).is_equal_approx(Vector2(0.5, 0.25), Vector2(0.0001, 0.0001))
