# Sliding in the real game scene: the pad (the left shoulder to sprint, B to crouch) and the touch
# layer (the stick pushed to its ring sprints, the Crouch button) start a slide, the animation
# plays the slide's start, loop and exit, and the camera widens and comes down with the body.
extends GdUnitTestSuite

var _scene: Node
var _player: Player
var _rig: PlayerCamera
var _touch: TouchControls
var _animation: CharacterAnimation


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_player = _scene.get_node("PlayerRig/Player")
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_touch = _scene.get_node("PlayerRig/TouchControls")
	_animation = _player.get_node("Animation")
	# A copy: the file is a cached resource that other suites read.
	_player.slide_tuning = _player.slide_tuning.duplicate()
	# Somewhere open on the map, facing along it.
	_player.teleport(_open_spot(), PI)
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_scene)


# A floor of its own high above the map (40 m square, its top 60 m up), with room to sprint and
# slide north: the map's blocks and edges would end a slide early.
func _open_spot() -> Vector3:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, 59.5, 0.0)
	_scene.add_child(floor_body)
	return Vector3(0.0, 60.0, 15.0)


func _touch_event(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	_touch._input(event)


func _drag_event(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	_touch._input(event)


func test_the_pad_slides_from_a_sprint() -> void:
	InputSim.pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	InputSim.pad_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_player.is_sprinting()).is_true()
	InputSim.pad_button(JOY_BUTTON_B, true)
	await InputSim.ticks(get_tree(), 3)
	assert_bool(_player.sliding).is_true()


func test_the_touch_stick_at_its_ring_and_the_crouch_button_slide() -> void:
	var stick := _touch.stick as Control
	var start := stick.get_global_rect().get_center()
	_touch_event(1, start, true)
	_drag_event(1, start + Vector2(0.0, -_touch.stick_radius * 1.2))
	await InputSim.ticks(get_tree(), 40)
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	assert_float(_player.ground_speed()).is_greater(_player.slide_tuning.min_speed)
	var crouch := _touch.button_center(_touch.buttons_root.get_node("Crouch").get_index())
	_touch_event(2, crouch, true)
	await InputSim.ticks(get_tree(), 3)
	assert_bool(_player.sliding).is_true()
	_touch_event(2, crouch, false)
	_touch_event(1, start, false)


func test_the_animation_plays_the_start_the_loop_and_the_exit() -> void:
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 40)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 3)
	await get_tree().process_frame
	assert_str(String(_animation.body_state())).is_equal("slide_start")
	# The start clip runs into the loop when it ends, if the slide lasts that long.
	_player.slide_tuning.max_time = 3.0
	_player.slide_tuning.friction = 0.5
	await InputSim.ticks(get_tree(), 60)
	await get_tree().process_frame
	assert_str(String(_animation.body_state())).is_equal("slide")
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 3)
	await get_tree().process_frame
	assert_str(String(_animation.body_state())).is_equal("slide_exit")
	await InputSim.ticks(get_tree(), 50)
	await get_tree().process_frame
	assert_str(String(_animation.body_state())).is_equal("ground")


func test_the_camera_widens_and_comes_down_with_the_slide() -> void:
	var target := _player.get_node("%CameraTarget") as Node3D
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 40)
	var sprint_fov := _rig.current_fov()
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.sliding).is_true()
	assert_float(_rig.slide_blend()).is_greater(0.9)
	assert_float(_rig.current_fov()).is_equal_approx(sprint_fov + _rig.slide_fov_change, 0.5)
	assert_float(target.position.y).is_equal_approx(_player.slide_tuning.camera_height, 0.01)
	# The lens stays above the floor and does not dive into the body.
	var camera := _scene.get_node("PlayerRig/Camera") as Camera3D
	assert_float(camera.global_position.y - _player.global_position.y).is_greater(0.4)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_rig.slide_blend()).is_less(0.01)
