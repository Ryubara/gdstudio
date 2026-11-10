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
		&"camera": null,
		&"player": null,
		&"distance": 1.7,
		&"offset": Vector3(0.0, 0.1, 0.0),
		&"field_of_view": 62.0,
		&"near_clip": 0.05,
		&"far_clip": 4000.0,
		&"start_pitch": 14.0,
		&"shoulder": PlayerCamera.Shoulder.RIGHT,
		&"shoulder_offset": 0.5,
		&"vertical_offset": 0.0,
		&"shoulder_time": 0.3,
		&"sprint_fov_change": 6.0,
		&"sprint_distance_change": 0.4,
		&"sprint_zoom_speed": 3.0,
		&"sprint_shake_amplitude": 0.0,
		&"sprint_shake_frequency": 3.0,
		&"sprint_shake_blend": 4.0,
		&"aim_distance": 1.1,
		&"aim_shifts_shoulder": false,
		&"aim_shoulder": 0.7,
		&"aim_fov": 50.0,
		&"aim_in_speed": 8.0,
		&"aim_out_speed": 6.0,
		&"zoom_when_firing": true,
		&"fire_distance": 1.4,
		&"fire_fov": 56.0,
		&"fire_in_speed": 8.0,
		&"fire_out_speed": 6.0,
		&"follow_damping": true,
		&"follow_damping_amount": 0.06,
		&"mouse_sensitivity": 0.12,
		&"stick_speed": 180.0,
		&"min_pitch": -55.0,
		&"max_pitch": 70.0,
		&"invert_y": false,
		&"capture_mouse": true,
		&"require_captured_mouse": true,
		&"priority": 10,
		&"blend_duration": 1.2,
		&"blend_transition": PhantomCameraTween.TransitionType.SINE,
		&"blend_ease": PhantomCameraTween.EaseType.EASE_IN_OUT,
		&"wall_mask": PhysicsLayers.CAMERA_MASK,
		&"wall_shape": null,
		&"wall_margin": 0.25,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	fresh.free()


func test_the_scene_sets_both_nodes_and_the_camera_has_no_warning() -> void:
	assert_object(_rig.target).is_not_null()
	assert_object(_rig.follow_camera).is_not_null()
	assert_object(_rig.camera).is_same(_scene.get_node("Camera"))
	assert_array(_rig._get_configuration_warnings()).is_empty()
	var bare := PlayerCamera.new()
	assert_array(bare._get_configuration_warnings()).has_size(3)
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
	# The Phantom Camera makes its spring arm a frame later: free the scene after it did.
	await get_tree().process_frame
	await get_tree().process_frame
	fresh.free()


func test_the_offset_moves_the_aim_on_every_axis() -> void:
	var pcam := _rig.phantom_camera()
	_rig.offset = Vector3(0.7, 0.3, -0.4)
	assert_vector(pcam.follow_offset).is_equal_approx(Vector3(0.7, 0.3, -0.4), Vector3.ONE * 0.001)


func test_the_clip_planes_reach_the_lens_and_the_real_camera() -> void:
	_rig.near_clip = 0.3
	_rig.far_clip = 500.0
	assert_float(_rig.phantom_camera().camera_3d_resource.near).is_equal_approx(0.3, 0.0001)
	await InputSim.ticks(get_tree(), 3)
	var camera: Camera3D = _scene.get_node("Camera")
	assert_float(camera.near).is_equal_approx(0.3, 0.001)
	assert_float(camera.far).is_equal_approx(500.0, 0.1)


func test_the_priority_and_the_blend_reach_the_phantom_camera() -> void:
	var pcam := _rig.phantom_camera()
	assert_int(pcam.priority).is_equal(10)
	assert_float(pcam.tween_duration).is_equal_approx(1.2, 0.001)
	_rig.priority = 30
	_rig.blend_duration = 0.4
	_rig.blend_transition = PhantomCameraTween.TransitionType.CUBIC
	_rig.blend_ease = PhantomCameraTween.EaseType.EASE_OUT
	assert_int(pcam.priority).is_equal(30)
	assert_float(pcam.tween_duration).is_equal_approx(0.4, 0.001)
	assert_int(pcam.tween_transition).is_equal(PhantomCameraTween.TransitionType.CUBIC)
	assert_int(pcam.tween_ease).is_equal(PhantomCameraTween.EaseType.EASE_OUT)


func test_the_wall_shape_is_the_spring_arms_shape() -> void:
	var ball := SphereShape3D.new()
	ball.radius = 0.2
	_rig.wall_shape = ball
	assert_object(_rig.phantom_camera().shape).is_same(ball)
	_rig.wall_shape = null
	assert_object(_rig.phantom_camera().shape).is_null()
