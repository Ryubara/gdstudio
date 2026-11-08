# The touch layer: it appears at the first touch, a floating stick, a look drag and buttons each
# press their own actions, two fingers at once never swap jobs, and a mouse (or the browser
# sending a finger as mouse motion) does nothing. Events go to the layer as it receives them, in
# canvas pixels.
extends GdUnitTestSuite

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint", &"jump", &"interact"
]

var _touch: TouchControls
var _looks: Array[Vector2] = []
var _added: Array[StringName] = []


func before_test() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			_added.append(action)
	_touch = load("res://ui/touch/touch_controls.tscn").instantiate()
	var jump := TouchButton.new()
	jump.action = &"jump"
	jump.label = "Jump"
	jump.slot = 0
	var use := TouchButton.new()
	use.action = &"interact"
	use.label = "Use"
	use.slot = 1
	_touch.buttons = [jump, use] as Array[TouchButton]
	_touch.look_smoothing = 0.0
	add_child(_touch)
	_touch.look_turned.connect(func(degrees: Vector2) -> void: _looks.append(degrees))
	_looks.clear()
	await get_tree().process_frame


func after_test() -> void:
	_touch.free()
	for action in ACTIONS:
		Input.action_release(action)
	for action in _added:
		InputMap.erase_action(action)
	_added.clear()
	Input.emulate_mouse_from_touch = true


func _down(index: int, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = true
	_touch._input(event)


func _up(index: int, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = false
	_touch._input(event)


func _drag(index: int, at: Vector2, relative := Vector2.ZERO) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = relative
	_touch._input(event)


func _total_look() -> Vector2:
	var total := Vector2.ZERO
	for turn in _looks:
		total += turn
	return total


func _left_thumb() -> Vector2:
	return Vector2(400.0, 700.0)


func _right_thumb() -> Vector2:
	return Vector2(1500.0, 500.0)


func test_it_is_hidden_until_the_first_touch_and_then_takes_over_from_the_mouse() -> void:
	assert_bool(_touch.is_shown()).is_false()
	assert_bool(_touch.visible).is_false()
	_down(0, _right_thumb())
	assert_bool(_touch.is_shown()).is_true()
	assert_bool(_touch.visible).is_true()
	assert_bool(Input.emulate_mouse_from_touch).is_false()


func test_the_stick_appears_where_the_thumb_lands_and_presses_the_move_actions() -> void:
	_down(0, _left_thumb())
	assert_vector(_touch.stick_vector()).is_equal(Vector2.ZERO)
	_drag(0, _left_thumb() + Vector2(100.0, 0.0))
	var push := (100.0 / _touch.stick_radius - _touch.deadzone) / (1.0 - _touch.deadzone)
	assert_float(_touch.stick_vector().x).is_equal_approx(push, 0.001)
	assert_float(Input.get_action_strength(&"move_right")).is_equal_approx(push, 0.001)
	assert_float(Input.get_action_strength(&"move_left")).is_equal(0.0)
	_drag(0, _left_thumb() + Vector2(0.0, -80.0))
	assert_bool(Input.is_action_pressed(&"move_forward")).is_true()
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()
	_up(0, _left_thumb())
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		assert_bool(Input.is_action_pressed(action)).is_false()
	# The stick is where the next thumb lands, not where the last one was.
	_down(0, Vector2(700.0, 800.0))
	_drag(0, Vector2(700.0, 800.0) + Vector2(-60.0, 0.0))
	assert_bool(Input.is_action_pressed(&"move_left")).is_true()


func test_a_small_push_stays_inside_the_dead_zone() -> void:
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(_touch.stick_radius * _touch.deadzone * 0.9, 0.0))
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()


func test_pushing_the_stick_out_to_its_ring_presses_sprint() -> void:
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(_touch.stick_radius * 0.6, 0.0))
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	_drag(0, _left_thumb() + Vector2(_touch.stick_radius * 1.4, 0.0))
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	assert_float(_touch.stick_vector().length()).is_less_equal(1.001)
	_up(0, _left_thumb())
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()


func test_dragging_on_the_right_turns_the_view_by_the_designed_angle() -> void:
	_down(1, _right_thumb())
	_drag(1, _right_thumb() + Vector2(100.0, 40.0))
	await get_tree().process_frame
	await get_tree().process_frame
	var total := _total_look()
	assert_float(total.x).is_equal_approx(100.0 * _touch.look_sensitivity, 0.001)
	assert_float(total.y).is_equal_approx(40.0 * _touch.look_sensitivity, 0.001)
	assert_float(Input.get_action_strength(&"move_right")).is_equal(0.0)


func test_the_view_turns_over_several_frames_not_once_per_finger_sample() -> void:
	_touch.look_smoothing = 30.0
	_down(1, _right_thumb())
	_drag(1, _right_thumb() + Vector2(200.0, 0.0))
	# Sixty frames a second, by hand: the real frame time of a test run is not the point.
	for _frame in 40:
		_touch._turn_view(1.0 / 60.0)
	var frames_with_turn := 0
	for turn in _looks:
		if not turn.is_zero_approx():
			frames_with_turn += 1
	assert_int(frames_with_turn).is_greater(3)
	assert_float(_total_look().x).is_equal_approx(200.0 * _touch.look_sensitivity, 0.001)
	var biggest := 0.0
	for turn in _looks:
		biggest = maxf(biggest, turn.x)
	assert_float(biggest).is_less(200.0 * _touch.look_sensitivity * 0.6)


func test_two_fingers_each_do_only_their_own_job() -> void:
	_down(0, _left_thumb())
	_down(1, _right_thumb())
	# The look finger moves: the stick stays where it is, the view turns.
	_drag(1, _right_thumb() + Vector2(50.0, 0.0), Vector2(1454.0, 0.0))
	await get_tree().process_frame
	assert_vector(_touch.stick_vector()).is_equal(Vector2.ZERO)
	assert_float(_total_look().x).is_equal_approx(50.0 * _touch.look_sensitivity, 0.001)
	# The stick finger moves: the character moves, the view does not turn more.
	var before := _total_look()
	_drag(0, _left_thumb() + Vector2(0.0, 120.0), Vector2(0.0, 1454.0))
	await get_tree().process_frame
	assert_bool(Input.is_action_pressed(&"move_back")).is_true()
	assert_vector(_total_look()).is_equal(before)
	# Letting go of one leaves the other working.
	_up(1, _right_thumb())
	assert_bool(Input.is_action_pressed(&"move_back")).is_true()
	_drag(0, _left_thumb() + Vector2(0.0, 140.0))
	assert_bool(Input.is_action_pressed(&"move_back")).is_true()


func test_a_drag_is_measured_from_the_finger_position_and_never_from_relative() -> void:
	_down(1, _right_thumb())
	_drag(1, _right_thumb() + Vector2(10.0, 0.0), Vector2(5000.0, 5000.0))
	_drag(1, _right_thumb() + Vector2(30.0, 0.0), Vector2(-5000.0, 0.0))
	await get_tree().process_frame
	assert_float(_total_look().x).is_equal_approx(30.0 * _touch.look_sensitivity, 0.001)
	assert_float(_total_look().y).is_equal(0.0)


func test_a_button_presses_its_action_while_a_finger_is_on_it() -> void:
	var jump_at := _touch.button_center(0)
	_down(2, jump_at)
	assert_bool(Input.is_action_pressed(&"jump")).is_true()
	assert_bool(_touch.is_shown()).is_true()
	_up(2, jump_at)
	assert_bool(Input.is_action_pressed(&"jump")).is_false()
	var use_at := _touch.button_center(1)
	_down(2, use_at)
	assert_bool(Input.is_action_pressed(&"interact")).is_true()
	_up(2, use_at)


func test_the_stick_and_a_button_work_with_two_fingers_together() -> void:
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(100.0, 0.0))
	var jump_at := _touch.button_center(0)
	_down(1, jump_at)
	assert_bool(Input.is_action_pressed(&"jump")).is_true()
	assert_bool(Input.is_action_pressed(&"move_right")).is_true()
	_up(1, jump_at)
	assert_bool(Input.is_action_pressed(&"jump")).is_false()
	assert_bool(Input.is_action_pressed(&"move_right")).is_true()


func test_a_finger_on_a_button_also_turns_the_view_when_it_drags() -> void:
	var jump_at := _touch.button_center(0)
	_down(1, jump_at)
	_drag(1, jump_at + Vector2(-80.0, 0.0))
	await get_tree().process_frame
	assert_float(_total_look().x).is_equal_approx(-80.0 * _touch.look_sensitivity, 0.001)
	assert_bool(Input.is_action_pressed(&"jump")).is_true()
	_touch.buttons_also_look = false
	_looks.clear()
	_drag(1, jump_at + Vector2(-200.0, 0.0))
	await get_tree().process_frame
	assert_float(_total_look().x).is_less(0.001)


func test_a_second_finger_on_the_left_does_not_take_over_the_stick() -> void:
	_down(0, _left_thumb())
	_down(1, Vector2(600.0, 600.0))
	_drag(1, Vector2(700.0, 600.0))
	assert_vector(_touch.stick_vector()).is_equal(Vector2.ZERO)
	_up(1, Vector2(700.0, 600.0))
	_drag(0, _left_thumb() + Vector2(100.0, 0.0))
	assert_bool(Input.is_action_pressed(&"move_right")).is_true()


func test_mouse_motion_never_turns_the_view_or_hides_the_layer() -> void:
	_down(1, _right_thumb())
	_up(1, _right_thumb())
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(900.0, 500.0)
	motion.relative = Vector2(500.0, 300.0)
	_touch._input(motion)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	_touch._input(click)
	await get_tree().process_frame
	assert_array(_looks).is_empty()
	assert_bool(_touch.is_shown()).is_true()


func test_a_key_or_a_pad_button_hides_the_layer_and_lets_go_of_everything() -> void:
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(100.0, 0.0))
	assert_bool(Input.is_action_pressed(&"move_right")).is_true()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = true
	_touch._input(key)
	assert_bool(_touch.is_shown()).is_false()
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()
	assert_bool(Input.emulate_mouse_from_touch).is_true()
	_down(0, _right_thumb())
	assert_bool(_touch.is_shown()).is_true()
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	_touch._input(pad)
	assert_bool(_touch.is_shown()).is_false()


func test_the_always_and_never_modes_ignore_the_device() -> void:
	_touch.show_mode = TouchControls.ShowMode.ALWAYS
	_touch._set_shown(true)
	assert_bool(_touch.is_shown()).is_true()
	var key := InputEventKey.new()
	key.pressed = true
	_touch._input(key)
	assert_bool(_touch.is_shown()).is_true()
	_touch.show_mode = TouchControls.ShowMode.NEVER
	_touch._set_shown(false)
	_down(0, _right_thumb())
	assert_bool(_touch.is_shown()).is_false()


func test_the_controls_stay_inside_the_screen_and_the_buttons_do_not_overlap() -> void:
	var view := _touch.get_viewport().get_visible_rect()
	for index in 2:
		var spot := _touch.button_center(index)
		var reach := _touch.button_size / 2.0
		(
			assert_bool(view.grow(-_touch.margin + 1.0).has_point(spot + Vector2(reach, reach)))
			. is_true()
		)
		(
			assert_bool(view.grow(-_touch.margin + 1.0).has_point(spot - Vector2(reach, reach)))
			. is_true()
		)
	var apart := _touch.button_center(0).distance_to(_touch.button_center(1))
	assert_float(apart).is_greater(_touch.button_size * 1.1)
	var home := _touch.stick_home()
	assert_bool(view.has_point(home)).is_true()
	assert_float(home.x).is_less(view.size.x * 0.5)


func test_the_buttons_are_large_enough_for_a_thumb_on_a_phone() -> void:
	# A phone in landscape is about 390 points high for the 1080-high canvas: 44 points (Apple's
	# default size for a control) is 122 canvas pixels.
	assert_float(_touch.button_size).is_greater_equal(44.0 * 1080.0 / 390.0)


func test_a_touch_sent_through_the_engine_reaches_the_layer() -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = true
	# Window pixels: the engine maps them to the canvas.
	event.position = get_viewport().get_final_transform() * _right_thumb()
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	assert_bool(_touch.is_shown()).is_true()
