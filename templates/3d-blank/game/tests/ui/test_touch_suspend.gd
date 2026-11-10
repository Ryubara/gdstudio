# The touch layer under a menu: `suspend` lets go of every finger and action the layer holds and
# hides it, and `resume` shows it again only when the touch controls are in use.
extends GdUnitTestSuite

const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back"]

var _touch: TouchControls
var _added: Array[StringName] = []


func before_test() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			_added.append(action)
	_touch = load("res://ui/touch/touch_controls.tscn").instantiate()
	add_child(_touch)
	await get_tree().process_frame


func after_test() -> void:
	_touch.free()
	for action in ACTIONS:
		Input.action_release(action)
	for action in _added:
		InputMap.erase_action(action)
	_added.clear()
	Input.emulate_mouse_from_touch = true


func _touch_at(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	_touch._input(event)


func test_suspending_lets_go_of_a_held_stick_and_hides_the_layer() -> void:
	_touch_at(0, Vector2(400.0, 700.0), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(500.0, 700.0)
	_touch._input(drag)
	assert_bool(Input.is_action_pressed(&"move_right")).is_true()
	_touch.suspend()
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()
	assert_bool(_touch.visible).is_false()
	assert_vector(_touch.stick_vector()).is_equal(Vector2.ZERO)


func test_resuming_shows_the_layer_again_when_it_was_in_use() -> void:
	_touch_at(0, Vector2(1500.0, 500.0), true)
	_touch_at(0, Vector2(1500.0, 500.0), false)
	assert_bool(_touch.is_shown()).is_true()
	_touch.suspend()
	assert_bool(_touch.visible).is_false()
	_touch.resume()
	assert_bool(_touch.visible).is_true()


func test_resuming_leaves_the_layer_hidden_on_a_computer() -> void:
	assert_bool(_touch.is_shown()).is_false()
	_touch.suspend()
	_touch.resume()
	assert_bool(_touch.visible).is_false()
