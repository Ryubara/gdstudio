# The camera's sprint and aim views, on the real camera in the main scene: sprinting zooms out a
# little, aiming brings the camera in over the shoulder to a narrower view, and the sprint shake is
# off by default. Every number is changed on the running rig and its effect read. The blends are
# stepped by hand with `advance()`, so the test needs no real time.
extends GdUnitTestSuite

var _scene: Node
var _rig: PlayerCamera
var _player: Player
var _camera: Camera3D


func before_test() -> void:
	# Another suite may have left a button down (a base suite leaves `fire` pressed).
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


func _sprint() -> void:
	# On the open floor of the south, where nothing is in the way for 6 m.
	_player.teleport(Vector3(4.0, 0.0, 23.0))
	await InputSim.ticks(get_tree(), 6)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 60)
	assert_bool(_player.is_sprinting()).is_true()


func _pitch_bobs_in_a_second() -> int:
	var bobs := 0
	var last := _rig.current_shake().x
	for _step in 60:
		_rig.advance(1.0 / 60.0)
		var pitch := _rig.current_shake().x
		if last <= 0.0 and pitch > 0.0:
			bobs += 1
		last = pitch
	return bobs


func _aim() -> void:
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_player.aiming).is_true()


func test_at_rest_the_view_is_the_framing() -> void:
	_settle()
	assert_float(_rig.current_distance()).is_equal(_rig.distance)
	assert_float(_rig.current_fov()).is_equal(_rig.field_of_view)
	assert_vector(_rig.current_offset()).is_equal(_rig.offset)
	assert_vector(_rig.current_shake()).is_equal(Vector3.ZERO)


func test_sprinting_zooms_the_view_out_and_widens_it_and_stopping_brings_it_back() -> void:
	await _sprint()
	_settle()
	assert_float(_rig.sprint_blend()).is_equal(1.0)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.distance + 0.4, 0.001)
	assert_float(_rig.current_fov()).is_equal_approx(62.0 + 6.0, 0.001)
	# The lens that draws the scene follows (the Phantom Camera host copies it).
	await InputSim.ticks(get_tree(), 4)
	assert_float(_camera.fov).is_equal_approx(68.0, 0.5)
	InputSim.key(KEY_SHIFT, false)
	InputSim.key(KEY_W, false)
	await InputSim.ticks(get_tree(), 40)
	_settle()
	assert_float(_rig.current_fov()).is_equal_approx(62.0, 0.001)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.distance, 0.001)


func test_the_sprint_zoom_numbers_are_live() -> void:
	await _sprint()
	_rig.sprint_fov_change = 12.0
	_rig.sprint_distance_change = -1.0
	_settle()
	assert_float(_rig.current_fov()).is_equal_approx(74.0, 0.001)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.distance - 1.0, 0.001)
	var pcam := _rig.phantom_camera()
	assert_float(pcam.camera_3d_resource.fov).is_equal_approx(74.0, 0.001)
	assert_float(pcam.spring_length).is_equal_approx(_rig.distance - 1.0, 0.001)


func test_sprint_zoom_speed_is_how_fast_the_zoom_blends() -> void:
	await _sprint()
	_settle()
	InputSim.key(KEY_SHIFT, false)
	InputSim.key(KEY_W, false)
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_player.is_sprinting()).is_false()
	_rig._sprint_blend = 1.0
	_rig.sprint_zoom_speed = 1.0
	_rig.advance(0.25)
	assert_float(_rig.sprint_blend()).is_equal_approx(0.75, 0.001)
	_rig.sprint_zoom_speed = 4.0
	_rig.advance(0.25)
	assert_float(_rig.sprint_blend()).is_equal_approx(0.0, 0.001)


func test_the_sprint_shake_is_off_by_default_and_stays_inside_its_amplitude() -> void:
	await _sprint()
	_settle()
	for _step in 60:
		_rig.advance(1.0 / 60.0)
		assert_vector(_rig.current_shake()).is_equal(Vector3.ZERO)
	_rig.sprint_shake_amplitude = 0.3
	var peak := Vector3.ZERO
	for _step in 180:
		_rig.advance(1.0 / 60.0)
		var shake := _rig.current_shake()
		peak = Vector3(
			maxf(peak.x, absf(shake.x)), maxf(peak.y, absf(shake.y)), maxf(peak.z, absf(shake.z))
		)
	# Pitch peaks at the amplitude, the turn at half of it and the roll at two thirds.
	assert_float(peak.x).is_between(0.27, 0.3001)
	assert_float(peak.y).is_between(0.13, 0.1501)
	assert_float(peak.z).is_between(0.18, 0.2011)


func test_the_shake_frequency_and_blend_are_live() -> void:
	await _sprint()
	_rig.sprint_shake_amplitude = 1.0
	_rig.sprint_shake_blend = 2.0
	_rig.shaker.clear()
	_rig.advance(0.25)
	# Half of the way in (2 per second for a quarter of a second).
	assert_float(_rig.shaker.level_of(&"sprint")).is_equal_approx(0.5, 0.001)
	_settle()
	assert_float(_rig.shaker.level_of(&"sprint")).is_equal(1.0)
	# The pitch bobs at the frequency: three bobs a second, then six.
	assert_int(_pitch_bobs_in_a_second()).is_between(2, 3)
	_rig.sprint_shake_frequency = 6.0
	assert_int(_pitch_bobs_in_a_second()).is_between(5, 6)


func test_the_shake_does_not_run_off_the_ground_or_while_walking() -> void:
	_rig.sprint_shake_amplitude = 1.0
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	_settle()
	assert_vector(_rig.current_shake()).is_equal(Vector3.ZERO)


func test_aiming_brings_the_camera_in_and_narrows_the_view() -> void:
	await _aim()
	_settle()
	assert_float(_rig.aim_blend()).is_equal(1.0)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.aim_distance, 0.001)
	assert_float(_rig.current_fov()).is_equal_approx(_rig.aim_fov, 0.001)
	# Aiming zooms only: the arm's start stays where it is (the shoulder is the Camera node's).
	assert_vector(_rig.current_offset()).is_equal(_rig.offset)
	await InputSim.ticks(get_tree(), 4)
	assert_float(_camera.fov).is_equal_approx(_rig.aim_fov, 0.5)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await InputSim.ticks(get_tree(), 40)
	_settle()
	assert_float(_rig.current_distance()).is_equal_approx(_rig.distance, 0.001)
	assert_float(_rig.current_fov()).is_equal_approx(_rig.field_of_view, 0.001)


func test_the_aim_numbers_are_live() -> void:
	await _aim()
	_rig.aim_distance = 1.5
	_rig.aim_shifts_shoulder = true
	_rig.aim_shoulder = 0.8
	_rig.aim_fov = 40.0
	_settle()
	assert_float(_rig.current_distance()).is_equal_approx(1.5, 0.001)
	assert_float(_rig.current_view_offset().x).is_equal_approx(0.8, 0.001)
	assert_float(_rig.current_fov()).is_equal_approx(40.0, 0.001)
	var pcam := _rig.phantom_camera()
	assert_float(pcam.spring_length).is_equal_approx(1.5, 0.001)
	assert_float(pcam.camera_3d_resource.h_offset).is_equal_approx(0.8, 0.001)
	assert_float(pcam.camera_3d_resource.fov).is_equal_approx(40.0, 0.001)


func test_the_aim_in_and_out_speeds_are_how_fast_the_view_changes() -> void:
	await _aim()
	_rig._aim_blend = 0.0
	_rig.aim_in_speed = 2.0
	_rig.advance(0.25)
	assert_float(_rig.aim_blend()).is_equal_approx(0.5, 0.001)
	_rig.aim_in_speed = 20.0
	_rig.advance(0.25)
	assert_float(_rig.aim_blend()).is_equal(1.0)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await InputSim.ticks(get_tree(), 60)
	assert_bool(_player.aiming).is_false()
	_rig._aim_blend = 1.0
	_rig.aim_out_speed = 1.0
	_rig.advance(0.5)
	assert_float(_rig.aim_blend()).is_equal_approx(0.5, 0.001)
	_rig.aim_out_speed = 10.0
	_rig.advance(0.5)
	assert_float(_rig.aim_blend()).is_equal(0.0)


func test_the_rig_finds_the_player_when_none_is_set() -> void:
	assert_object(_rig.player).is_same(_player)
	var bare := auto_free(PlayerCamera.new()) as PlayerCamera
	bare.advance(0.1)
	assert_float(bare.current_fov()).is_equal(62.0)
