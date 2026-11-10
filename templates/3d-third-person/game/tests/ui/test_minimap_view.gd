# The minimap's view: zoom and its range, the three rotation modes, the live camera held to the
# same maths as the icons, sections slicing and naming the map, the image source and the look.
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


func test_zoom_steps_the_range_and_stops_at_its_limits() -> void:
	_minimap.refresh_now()
	assert_float(_minimap.current_range()).is_equal_approx(30.0, 0.001)
	_minimap.zoom_in()
	_minimap.refresh_now()
	assert_float(_minimap.current_range()).is_equal_approx(30.0 / 1.3, 0.001)
	for i in 20:
		_minimap.zoom_in()
	_minimap.refresh_now()
	assert_float(_minimap.current_range()).is_equal_approx(12.0, 0.001)
	for i in 30:
		_minimap.zoom_out()
	_minimap.refresh_now()
	assert_float(_minimap.current_range()).is_equal_approx(90.0, 0.001)


func test_zoom_changes_where_a_marker_lands() -> void:
	var carrier := _carry(Vector3(10.0, 0.0, 0.0))
	_minimap.refresh_now()
	var was_at := _centre_of(_minimap.icon_for(_marker_of(carrier))).x - 110.0
	_minimap.zoom_in()
	_minimap.refresh_now()
	var now_at := _centre_of(_minimap.icon_for(_marker_of(carrier))).x - 110.0
	assert_float(now_at / was_at).is_equal_approx(1.3, 0.001)


func test_the_zoom_keys_zoom_the_map() -> void:
	_minimap.refresh_now()
	InputSim.key(KEY_EQUAL, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_EQUAL, false)
	await InputSim.ticks(get_tree(), 2)
	assert_float(_minimap.current_range()).is_equal_approx(30.0 / 1.3, 0.001)
	InputSim.key(KEY_MINUS, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_MINUS, false)
	await InputSim.ticks(get_tree(), 2)
	assert_float(_minimap.current_range()).is_equal_approx(30.0, 0.001)


func test_zoom_moves_to_its_goal_smoothly_when_asked_to() -> void:
	_minimap.zoom_smoothing = 6.0
	_minimap.refresh_now()
	_minimap.zoom_out()
	await get_tree().process_frame
	assert_float(_minimap.current_range()).is_greater(30.0)
	assert_float(_minimap.current_range()).is_less(39.0)
	await get_tree().create_timer(1.5).timeout
	assert_float(_minimap.current_range()).is_equal_approx(39.0, 0.1)


func test_north_up_ignores_the_camera() -> void:
	var camera := _camera(PI * 0.5)
	_minimap.rotation_mode = Minimap.RotationMode.NORTH_UP
	var carrier := _carry(Vector3(0.0, 0.0, -10.0))
	_minimap.refresh_now()
	assert_float(_minimap.projector().turn).is_equal_approx(0.0, 0.0001)
	assert_float(_centre_of(_minimap.icon_for(_marker_of(carrier))).y).is_less(110.0)
	assert_object(camera).is_not_null()


func test_the_map_turns_with_the_camera() -> void:
	_camera(PI * 0.5)  # looking west
	_minimap.rotation_mode = Minimap.RotationMode.CAMERA_FACING
	var west := _carry(Vector3(-10.0, 0.0, 0.0))
	var north := _carry(Vector3(0.0, 0.0, -10.0))
	_minimap.refresh_now()
	# West is now up, and north is to the right of that.
	var up_at := _centre_of(_minimap.icon_for(_marker_of(west))) - Vector2(110.0, 110.0)
	assert_float(up_at.x).is_equal_approx(0.0, 0.01)
	assert_float(up_at.y).is_equal_approx(-36.667, 0.01)
	var right_at := _centre_of(_minimap.icon_for(_marker_of(north))) - Vector2(110.0, 110.0)
	assert_float(right_at.x).is_equal_approx(36.667, 0.01)
	assert_float(right_at.y).is_equal_approx(0.0, 0.01)
	# The letter N sits on the side north is.
	var letter := _minimap.get_node("%North") as Control
	assert_bool(letter.visible).is_true()
	assert_float((letter.position + letter.size * 0.5).x).is_greater(110.0)


func test_the_map_turns_with_the_target_when_it_asks_for_that() -> void:
	_minimap.rotation_mode = Minimap.RotationMode.TARGET_FACING
	_subject.rotate_y(-PI * 0.5)  # facing east
	var east := _carry(Vector3(10.0, 0.0, 0.0))
	_minimap.refresh_now()
	var at := _centre_of(_minimap.icon_for(_marker_of(east))) - Vector2(110.0, 110.0)
	assert_float(at.x).is_equal_approx(0.0, 0.01)
	assert_float(at.y).is_less(0.0)


func test_a_turning_map_follows_at_the_smoothing_rate() -> void:
	_minimap.turn_smoothing = 4.0
	var camera := _camera(0.0)
	_minimap.refresh_now()
	camera.rotation.y = PI * 0.5
	await get_tree().process_frame
	var turn := _minimap.projector().turn
	assert_float(absf(turn)).is_greater(0.0)
	assert_float(absf(turn)).is_less(PI * 0.5 - 0.1)


func test_the_live_camera_looks_down_from_above_the_target_and_follows_it() -> void:
	_subject.global_position = Vector3(5.0, 1.0, -7.0)
	_minimap.refresh_now()
	var camera := _minimap.get_node("%MapCamera") as Camera3D
	assert_vector(camera.global_position).is_equal_approx(
		Vector3(5.0, 41.0, -7.0), Vector3(0.01, 0.01, 0.01)
	)
	assert_float(camera.size).is_equal_approx(60.0, 0.001)
	assert_float((-camera.global_basis.z).dot(Vector3.DOWN)).is_equal_approx(1.0, 0.0001)
	assert_int(camera.cull_mask).is_equal(1)
	_minimap.live_layers = 2
	assert_int(camera.cull_mask).is_equal(2)


func test_the_live_picture_and_the_icons_use_the_same_maths_at_any_turn() -> void:
	_camera(PI * 0.75)
	_subject.global_position = Vector3(5.0, 0.0, -7.0)
	_minimap.refresh_now()
	# A camera's transform reaches its lens at the end of the frame.
	await get_tree().process_frame
	var camera := _minimap.get_node("%MapCamera") as Camera3D
	var view := _minimap.get_node("%LiveView") as SubViewport
	var projector := _minimap.projector()
	for world in [Vector3(9.0, 0.0, -3.0), Vector3(-2.0, 0.0, -20.0), Vector3(12.0, 0.0, -12.0)]:
		var pixel := camera.unproject_position(world)
		var seen := pixel / Vector2(view.size)
		var plane := Vector2(world.x, world.z)
		var expected := MinimapProjector.snapshot_uv(
			plane, projector.centre, projector.turn, Vector2(30.0, 30.0)
		)
		assert_vector(seen).is_equal_approx(expected, Vector2(0.002, 0.002))


func test_a_picture_turned_by_the_view_lands_where_the_icons_do() -> void:
	# What the shader sums for the middle of the widget's top edge must be the place the
	# projector puts there.
	_camera(1.0)
	_subject.global_position = Vector3(3.0, 0.0, 4.0)
	_minimap.refresh_now()
	var projector := _minimap.projector()
	var above := projector.to_world(Vector2(0.0, -50.0))
	var uv := MinimapProjector.snapshot_uv(
		above, projector.centre, projector.turn, Vector2(30.0, 30.0)
	)
	assert_float(uv.x).is_equal_approx(0.5, 0.0001)
	assert_float(uv.y).is_less(0.5)


func test_a_still_view_does_not_render_again_and_a_moving_one_does() -> void:
	_minimap.still_refresh_seconds = 0.0
	_minimap.refresh_now()
	var taken := _minimap.snapshots_taken()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_minimap.snapshots_taken()).is_equal(taken)
	for i in 3:
		_subject.global_position += Vector3(0.5, 0.0, 0.0)
		await get_tree().process_frame
	assert_int(_minimap.snapshots_taken()).is_greater_equal(taken + 3)


func test_a_still_view_renders_now_and_then_to_catch_a_moving_door() -> void:
	_minimap.still_refresh_seconds = 0.3
	_minimap.refresh_now()
	var taken := _minimap.snapshots_taken()
	await get_tree().create_timer(0.8).timeout
	assert_int(_minimap.snapshots_taken()).is_greater(taken)
	assert_int(_minimap.snapshots_taken()).is_less(taken + 5)


func test_a_rate_limited_map_renders_at_its_rate() -> void:
	_minimap.map_update_rate = 5.0
	_minimap.still_refresh_seconds = 0.0
	_minimap.refresh_now()
	var taken := _minimap.snapshots_taken()
	for i in 30:
		_subject.global_position += Vector3(0.1, 0.0, 0.0)
		await get_tree().process_frame
	# Thirty frames are far less than a second at any frame rate a test runs at (or just
	# over it on a slow runner): never more than five renders to a second.
	assert_int(_minimap.snapshots_taken() - taken).is_less_equal(int(ceil(30.0 / 60.0 * 5.0)) + 2)


func test_a_map_that_does_not_follow_stays_where_it_is_put() -> void:
	_minimap.follow_target = false
	_minimap.fixed_centre = Vector2(10.0, -10.0)
	_subject.global_position = Vector3(50.0, 0.0, 50.0)
	_minimap.refresh_now()
	assert_vector(_minimap.projector().centre).is_equal(Vector2(10.0, -10.0))


func test_a_2d_game_can_follow_a_node_2d_and_mark_other_nodes_2d() -> void:
	var player := auto_free(Node2D.new()) as Node2D
	add_child(player)
	player.global_position = Vector2(10.0, 20.0)
	var coin := auto_free(Node2D.new()) as Node2D
	add_child(coin)
	coin.global_position = Vector2(16.0, 14.0)
	var marker := MinimapMarker.new()
	coin.add_child(marker)
	_minimap.target = player
	_minimap.rotation_mode = Minimap.RotationMode.TARGET_FACING
	_minimap.source = Minimap.Source.IMAGE
	player.rotation = 0.0  # facing +X: east is up
	_minimap.refresh_now()
	assert_vector(_minimap.projector().centre).is_equal(Vector2(10.0, 20.0))
	# Six metres east and six north of the player, with east up: up six and left six (3.667 px a
	# metre).
	var at := _minimap.icon_for(marker).position - Vector2(110.0, 110.0)
	assert_float(at.x).is_equal_approx(-22.0, 0.05)
	assert_float(at.y).is_equal_approx(-22.0, 0.05)


func _camera(yaw: float) -> Camera3D:
	var camera := auto_free(Camera3D.new()) as Camera3D
	add_child(camera)
	camera.rotation.y = yaw
	camera.current = true
	return camera


func _carry(at: Vector3) -> Node3D:
	var carrier := auto_free(Node3D.new()) as Node3D
	add_child(carrier)
	carrier.global_position = at
	carrier.add_child(MinimapMarker.new())
	return carrier


func _marker_of(carrier: Node3D) -> MinimapMarker:
	return carrier.get_child(0) as MinimapMarker


func _centre_of(icon: MinimapIcon) -> Vector2:
	return icon.position
