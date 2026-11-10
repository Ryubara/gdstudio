# The over-the-shoulder view is the Camera node's own H Offset and V Offset, set from the
# `shoulder` settings of `PlayerCamera` and from nothing else: the zooms, the Phantom Camera
# host and the lens resource leave them alone. Aiming only zooms unless `aim_shifts_shoulder`
# is on. Blends are stepped by hand with `advance()`, so no real time passes.
extends GdUnitTestSuite

var _scene: Node
var _rig: PlayerCamera
var _player: Player
var _camera: Camera3D


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_player = _scene.get_node("PlayerRig/Player")
	_camera = _scene.get_node("PlayerRig/Camera")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


func _settle(seconds := 2.0) -> void:
	for _step in int(seconds * 60.0):
		_rig.advance(1.0 / 60.0)


func test_the_default_view_is_the_right_shoulder_on_the_camera_node() -> void:
	_settle()
	assert_int(_rig.shoulder).is_equal(PlayerCamera.Shoulder.RIGHT)
	assert_float(_camera.h_offset).is_equal_approx(0.5, 0.001)
	assert_float(_camera.v_offset).is_equal_approx(0.0, 0.001)
	assert_float(_rig.distance).is_equal(1.7)


func test_the_shoulder_choice_sets_the_h_offset_of_the_camera_node() -> void:
	_rig.shoulder = PlayerCamera.Shoulder.LEFT
	_settle()
	assert_float(_camera.h_offset).is_equal_approx(-0.5, 0.001)
	_rig.shoulder = PlayerCamera.Shoulder.CENTER
	_settle()
	assert_float(_camera.h_offset).is_equal_approx(0.0, 0.001)
	_rig.shoulder = PlayerCamera.Shoulder.RIGHT
	_settle()
	assert_float(_camera.h_offset).is_equal_approx(0.5, 0.001)


func test_the_shoulder_offset_and_the_vertical_offset_are_live() -> void:
	_rig.shoulder_offset = 0.9
	_rig.vertical_offset = 0.2
	_settle()
	assert_float(_camera.h_offset).is_equal_approx(0.9, 0.001)
	assert_float(_camera.v_offset).is_equal_approx(0.2, 0.001)
	# The lens shifts by it: the camera's own transform includes the two offsets.
	var shifted := _camera.get_camera_transform().origin - _camera.global_position
	assert_float(shifted.length()).is_equal_approx(Vector2(0.9, 0.2).length(), 0.01)


func test_a_change_of_shoulder_crosses_over_the_time_it_is_given() -> void:
	_settle()
	_rig.shoulder_time = 1.0
	_rig.shoulder = PlayerCamera.Shoulder.LEFT
	_rig.advance(0.25)
	var early := _camera.h_offset
	assert_float(early).is_less(0.5).is_greater(-0.5)
	_rig.advance(0.25)
	assert_float(_camera.h_offset).is_less(early)
	_rig.advance(0.6)
	assert_float(_camera.h_offset).is_equal_approx(-0.5, 0.001)


func test_the_swap_action_changes_shoulder() -> void:
	assert_bool(InputMap.has_action(&"shoulder_swap")).is_true()
	var event := InputEventKey.new()
	event.keycode = KEY_Q
	event.physical_keycode = KEY_Q
	event.pressed = true
	_rig._unhandled_input(event)
	assert_int(_rig.shoulder).is_equal(PlayerCamera.Shoulder.LEFT)
	_rig._unhandled_input(event)
	assert_int(_rig.shoulder).is_equal(PlayerCamera.Shoulder.RIGHT)


func test_the_offsets_stick_when_the_zooms_and_the_lens_change() -> void:
	_rig.vertical_offset = 0.1
	_settle()
	# Every zoom writes the lens resource, which the host copies onto the Camera node.
	_rig.field_of_view = 70.0
	_rig.near_clip = 0.1
	_rig.sprint_fov_change = 10.0
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 50)
	assert_float(_camera.fov).is_greater(70.0)
	assert_float(_camera.h_offset).is_equal_approx(0.5, 0.001)
	assert_float(_camera.v_offset).is_equal_approx(0.1, 0.001)
	var lens := _rig.phantom_camera().camera_3d_resource
	assert_float(lens.h_offset).is_equal_approx(0.5, 0.001)
	assert_float(lens.v_offset).is_equal_approx(0.1, 0.001)


func test_aiming_only_zooms_with_aim_shifts_shoulder_off() -> void:
	assert_bool(_rig.aim_shifts_shoulder).is_false()
	_settle()
	var resting := Vector2(_camera.h_offset, _camera.v_offset)
	var arm_before := _rig.phantom_camera().follow_offset
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 20)
	_settle()
	assert_float(_rig.aim_blend()).is_equal(1.0)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.aim_distance, 0.001)
	assert_float(_camera.h_offset).is_equal(resting.x)
	assert_float(_camera.v_offset).is_equal(resting.y)
	assert_vector(_rig.phantom_camera().follow_offset).is_equal(arm_before)


func test_aiming_moves_the_view_to_the_aim_offset_with_aim_shifts_shoulder_on() -> void:
	_rig.aim_shifts_shoulder = true
	_rig.aim_shoulder = 0.8
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 20)
	_settle()
	assert_float(_camera.h_offset).is_equal_approx(0.8, 0.001)
	# On the left shoulder the aim offset is on the left.
	_rig.shoulder = PlayerCamera.Shoulder.LEFT
	_settle()
	assert_float(_camera.h_offset).is_equal_approx(-0.8, 0.001)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await InputSim.ticks(get_tree(), 30)
	_settle()
	assert_float(_camera.h_offset).is_equal_approx(-0.5, 0.001)


func test_the_aim_view_never_moves_the_arm_or_its_wall_cast() -> void:
	_rig.aim_shifts_shoulder = true
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 20)
	_settle()
	assert_vector(_rig.phantom_camera().follow_offset).is_equal_approx(
		_rig.offset, Vector3.ONE * 0.001
	)
