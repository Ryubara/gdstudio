# The camera zooms from the buttons, not from the arm: it starts back out on the next frame after
# aim and fire are let go, and so does the character's aim (`test_aim_release.gd`). Firing
# without aiming has its own zoom, which a toggle turns off.
extends GdUnitTestSuite

var _scene: Node
var _rig: PlayerCamera
var _player: Player


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerCamera")
	_player = _scene.get_node("Player")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


func _hold_fire() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 40)


func test_firing_without_aiming_zooms_to_the_fire_view_which_is_not_the_aim_view() -> void:
	await _hold_fire()
	assert_float(_rig.fire_blend()).is_equal(1.0)
	assert_float(_rig.aim_blend()).is_equal(0.0)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.fire_distance, 0.001)
	assert_float(_rig.current_fov()).is_equal_approx(_rig.fire_fov, 0.001)
	assert_float(_rig.fire_distance).is_not_equal(_rig.aim_distance)
	assert_float(_rig.fire_distance).is_less(_rig.distance)


func test_with_zoom_when_firing_off_firing_leaves_the_framing_alone() -> void:
	_rig.zoom_when_firing = false
	await _hold_fire()
	assert_bool(_player.fire_held).is_true()
	assert_bool(_player.aiming).is_true()
	assert_float(_rig.fire_blend()).is_equal(0.0)
	assert_float(_rig.aim_blend()).is_equal(0.0)
	assert_float(_rig.current_distance()).is_equal(_rig.distance)
	assert_float(_rig.current_fov()).is_equal(_rig.field_of_view)
	assert_float(_rig.phantom_camera().spring_length).is_equal_approx(_rig.distance, 0.001)
	# Aiming still zooms.
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.aim_distance, 0.001)


func test_the_fire_zoom_numbers_are_live() -> void:
	await _hold_fire()
	_rig.fire_distance = 1.0
	_rig.fire_fov = 45.0
	_rig.advance(0.0)
	assert_float(_rig.current_distance()).is_equal_approx(1.0, 0.001)
	assert_float(_rig.current_fov()).is_equal_approx(45.0, 0.001)
	_rig._fire_blend = 0.0
	_rig.fire_in_speed = 2.0
	_rig.advance(0.25)
	assert_float(_rig.fire_blend()).is_equal_approx(0.5, 0.001)
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 2)
	_rig._fire_blend = 1.0
	_rig.fire_out_speed = 1.0
	_rig.advance(0.5)
	assert_float(_rig.fire_blend()).is_equal_approx(0.5, 0.001)


func test_the_zoom_out_after_a_shot_starts_on_the_next_frame_not_after_the_aim_pose() -> void:
	await _hold_fire()
	var held := _rig.current_distance()
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	var distances: Array[float] = []
	for _tick in 6:
		await get_tree().physics_frame
		distances.append(_rig.current_distance())
	# Neither the camera nor the character's aim waits.
	assert_bool(_player.aiming).is_false()
	assert_bool(_player.fire_held).is_false()
	assert_float(distances[1]).is_greater(held + 0.005)
	for index in range(1, distances.size()):
		assert_float(distances[index]).is_greater_equal(distances[index - 1])


func test_the_zoom_out_after_letting_go_of_aim_starts_on_the_next_frame() -> void:
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 30)
	var held := _rig.current_distance()
	assert_float(held).is_equal_approx(_rig.aim_distance, 0.001)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await InputSim.ticks(get_tree(), 3)
	assert_float(_rig.current_distance()).is_greater(held + 0.005)


func test_a_shot_while_aiming_and_letting_go_of_both_zooms_out_at_once() -> void:
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 30)
	var held := _rig.current_distance()
	assert_float(held).is_equal_approx(_rig.aim_distance, 0.001)
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 3)
	assert_float(_rig.current_distance()).is_greater(held + 0.005)
	await InputSim.ticks(get_tree(), 60)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.distance, 0.02)
