# The camera's inspector contract: every export has its default pinned, and each one that has an
# effect is changed on the running camera and its effect read (the framing, follow and wall
# settings are in test_player_camera.gd).
extends GdUnitTestSuite

var _scene: Node
var _rig: PlayerCamera


func before_test() -> void:
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerCamera")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_every_export_has_its_default_pinned() -> void:
	var fresh := PlayerCamera.new()
	var pins := {
		&"target": null,
		&"follow_camera": null,
		&"distance": 4.4,
		&"height": 0.1,
		&"field_of_view": 62.0,
		&"start_pitch": 14.0,
		&"follow_damping": true,
		&"follow_damping_amount": 0.06,
		&"mouse_sensitivity": 0.12,
		&"stick_speed": 180.0,
		&"min_pitch": -55.0,
		&"max_pitch": 70.0,
		&"invert_y": false,
		&"capture_mouse": true,
		&"require_captured_mouse": true,
		&"wall_mask": 1,
		&"wall_margin": 0.25,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	fresh.free()


func test_the_scene_sets_both_nodes_and_the_camera_has_no_warning() -> void:
	assert_object(_rig.target).is_not_null()
	assert_object(_rig.follow_camera).is_not_null()
	assert_array(_rig._get_configuration_warnings()).is_empty()
	var bare := PlayerCamera.new()
	assert_array(bare._get_configuration_warnings()).has_size(2)
	bare.free()


func test_a_new_target_is_followed_at_once() -> void:
	var elsewhere := auto_free(Node3D.new()) as Node3D
	_scene.add_child(elsewhere)
	_rig.target = elsewhere
	assert_object(_rig.phantom_camera().follow_target).is_same(elsewhere)


func test_the_mouse_sensitivity_scales_the_turn_per_pixel() -> void:
	_rig.require_captured_mouse = false
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 0.0)
	_rig.mouse_sensitivity = 0.5
	var yaw := _rig.yaw
	_rig._unhandled_input(motion)
	assert_float(angle_difference(deg_to_rad(_rig.yaw), deg_to_rad(yaw - 50.0))).is_equal_approx(
		0.0, 0.001
	)


func test_the_stick_speed_sets_the_turn_per_second_at_full_push() -> void:
	for _frame in 5:
		await get_tree().process_frame
	_rig.stick_speed = 100.0
	InputSim.pad_axis(JOY_AXIS_RIGHT_X, 1.0)
	var yaw := _rig.yaw
	_rig._process(0.1)
	assert_float(angle_difference(deg_to_rad(_rig.yaw), deg_to_rad(yaw - 10.0))).is_equal_approx(
		0.0, 0.001
	)


func test_the_pitch_limits_are_read_when_the_camera_turns() -> void:
	_rig.max_pitch = 30.0
	_rig.min_pitch = -20.0
	_rig.orbit(Vector2(0.0, 500.0))
	assert_float(_rig.pitch).is_equal(30.0)
	_rig.orbit(Vector2(0.0, -500.0))
	assert_float(_rig.pitch).is_equal(-20.0)


func test_invert_y_flips_the_up_and_down_turn() -> void:
	_rig.pitch = 0.0
	_rig.orbit(Vector2(0.0, 10.0))
	assert_float(_rig.pitch).is_equal(10.0)
	_rig.invert_y = true
	_rig.orbit(Vector2(0.0, 10.0))
	assert_float(_rig.pitch).is_equal(0.0)


func test_capture_mouse_off_leaves_the_mouse_alone_on_a_click() -> void:
	_rig.capture_mouse = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	_rig._unhandled_input(click)
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)


func test_start_pitch_is_where_a_new_camera_begins() -> void:
	var packed := load("res://main.tscn") as PackedScene
	var fresh := packed.instantiate()
	(fresh.get_node("PlayerCamera") as PlayerCamera).start_pitch = 33.0
	add_child(fresh)
	assert_float((fresh.get_node("PlayerCamera") as PlayerCamera).pitch).is_equal(33.0)
	fresh.free()
