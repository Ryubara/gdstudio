# The third-person camera: Phantom Camera follows the player, orbit comes from the stick, the
# mouse and the touch layer, the spring arm keeps the lens out of walls, and the player moves
# along the camera heading.
extends GdUnitTestSuite

var _runner: GdUnitSceneRunner
var _scene: Node
var _player: Player
var _rig: PlayerCamera
var _camera: Camera3D


func before_test() -> void:
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	_player = _scene.get_node("Player")
	_rig = _scene.get_node("PlayerCamera")
	_camera = _scene.get_node("Camera")
	await InputSim.ticks(get_tree(), 12)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _view_yaw() -> float:
	var forward := -_camera.global_basis.z
	return rad_to_deg(atan2(-forward.x, -forward.z))


func test_the_camera_sits_behind_and_above_the_player_at_the_tuned_distance() -> void:
	var pivot: Vector3 = _player.get_node("CameraTarget").global_position
	var distance := _camera.global_position.distance_to(pivot + Vector3.UP * _rig.height)
	assert_float(distance).is_equal_approx(_rig.distance, 0.4)
	assert_float(_camera.global_position.y).is_greater(pivot.y)
	assert_object(_scene.get_node("Camera/PhantomCameraHost").get_active_pcam()).is_same(
		_rig.phantom_camera()
	)


func test_the_right_stick_orbits_the_camera() -> void:
	var start := _view_yaw()
	InputSim.pad_axis(JOY_AXIS_RIGHT_X, 1.0)
	await InputSim.ticks(get_tree(), 30)
	InputSim.pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	await InputSim.ticks(get_tree(), 30)
	var turned := angle_difference(deg_to_rad(start), deg_to_rad(_view_yaw()))
	assert_float(rad_to_deg(turned)).is_less(-40.0)
	# The lens follows the angle the rig holds, a little late (it is damped).
	var late := absf(angle_difference(deg_to_rad(_rig.yaw), deg_to_rad(_view_yaw())))
	assert_float(late).is_less(deg_to_rad(6.0))


func test_the_mouse_orbits_the_camera_while_it_is_captured_and_not_otherwise() -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 50.0)
	var yaw := _rig.yaw
	var pitch := _rig.pitch
	# A headless run cannot capture the mouse, so the rule is tested on the option that stands
	# for it.
	_rig.require_captured_mouse = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rig._unhandled_input(motion)
	assert_float(_rig.yaw).is_equal(yaw)
	_rig.require_captured_mouse = false
	_rig._unhandled_input(motion)
	assert_float(_rig.yaw).is_equal_approx(yaw - 100.0 * _rig.mouse_sensitivity, 0.001)
	assert_float(_rig.pitch).is_equal_approx(pitch + 50.0 * _rig.mouse_sensitivity, 0.001)


func test_the_pitch_stops_at_its_limits() -> void:
	_rig.orbit(Vector2(0.0, 500.0))
	assert_float(_rig.pitch).is_equal(_rig.max_pitch)
	_rig.orbit(Vector2(0.0, -500.0))
	assert_float(_rig.pitch).is_equal(_rig.min_pitch)


func test_the_touch_layer_turns_the_camera_through_its_signal() -> void:
	var yaw := _rig.yaw
	_scene.get_node("TouchControls").look_turned.emit(Vector2(12.0, 0.0))
	assert_float(_rig.yaw).is_equal_approx(yaw - 12.0, 0.001)


func test_the_player_moves_along_the_way_the_camera_looks() -> void:
	_rig.yaw = -90.0
	await InputSim.ticks(get_tree(), 20)
	_player.teleport(Vector3(0.0, 1.0, 0.0))
	await InputSim.ticks(get_tree(), 4)
	var start := _player.global_position
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	var moved := _player.global_position - start
	assert_float(moved.x).is_greater(1.5)
	assert_float(absf(moved.z)).is_less(0.8)


func test_the_lens_does_not_go_through_a_wall_behind_the_player() -> void:
	# The north wall's inner face is at z = -24. Look toward +z so the camera sits behind the
	# player, in the wall.
	_player.teleport(Vector3(0.0, 0.0, -23.2))
	_rig.yaw = 180.0
	_rig.pitch = 0.0
	await InputSim.ticks(get_tree(), 40)
	assert_float(_camera.global_position.z).is_greater(-24.0)
	var pivot: Vector3 = _player.get_node("CameraTarget").global_position
	assert_float(_camera.global_position.distance_to(pivot)).is_less(_rig.distance - 1.0)
