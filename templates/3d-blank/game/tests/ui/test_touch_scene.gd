# The scene of the touch layer as a developer meets it: every part is a node in
# `touch_controls.tscn`, every export is live, and no script draws anything. What the fingers do
# is in test_touch_controls.gd.
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


func test_every_export_has_its_default_pinned() -> void:
	var fresh := TouchControls.new()
	var pins := {
		&"show_mode": TouchControls.ShowMode.AUTO,
		&"show_zones": false,
		&"move_left": &"move_left",
		&"move_right": &"move_right",
		&"move_forward": &"move_forward",
		&"move_back": &"move_back",
		&"sprint_action": &"sprint",
		&"stick_radius": 150.0,
		&"deadzone": 0.15,
		&"sprint_ring": 0.92,
		&"look_sensitivity": 0.1,
		&"look_smoothing": 30.0,
		&"buttons_also_look": true,
		&"opacity": 0.5,
		&"margin": 70.0,
		&"safe_area": null,
		&"stick": null,
		&"buttons_root": null,
		&"move_zone": null,
		&"look_zone": null,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	fresh.free()
	var button := TouchButton.new()
	var button_pins := {&"action": &"jump", &"label": "Jump"}
	assert_array(ExportPins.differences(button, button_pins)).is_empty()
	assert_array(ExportPins.wrong_values(button, button_pins)).is_empty()
	button.free()


func test_the_scene_holds_every_part_as_a_node_and_has_no_warning() -> void:
	assert_array(_touch._get_configuration_warnings()).is_empty()
	var parts := [_touch.safe_area, _touch.stick, _touch.buttons_root]
	parts.append_array([_touch.move_zone, _touch.look_zone])
	for part in parts:
		assert_object(part).is_not_null()
	assert_int(_touch.button_count()).is_equal(2)
	for part_name in ["Ring", "SprintRing", "Knob"]:
		assert_object(_touch.stick.find_child(part_name, true, false)).is_not_null()
	var bare := TouchControls.new()
	assert_array(bare._get_configuration_warnings()).has_size(5)
	bare.free()


func test_the_scripts_draw_nothing_and_are_tool_scripts() -> void:
	var paths := [
		"res://ui/touch/touch_controls.gd",
		"res://ui/touch/touch_stick.gd",
		"res://ui/touch/touch_button.gd",
	]
	for path: String in paths:
		var source := FileAccess.get_file_as_string(path)
		assert_bool(source.begins_with("@tool")).override_failure_message(path).is_true()
		for forbidden in ["_draw", "draw_circle", "draw_arc", "draw_string", "Control.new()"]:
			(
				assert_bool(source.contains(forbidden))
				. override_failure_message("%s holds %s" % [path, forbidden])
				. is_false()
			)


func test_the_move_actions_and_the_sprint_action_are_read_when_the_stick_moves() -> void:
	for action in [&"left2", &"right2", &"up2", &"down2", &"run2"]:
		InputMap.add_action(action)
		_added.append(action)
	_touch.move_left = &"left2"
	_touch.move_right = &"right2"
	_touch.move_forward = &"up2"
	_touch.move_back = &"down2"
	_touch.sprint_action = &"run2"
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(_touch.stick_radius * 1.4, 0.0))
	assert_bool(Input.is_action_pressed(&"right2")).is_true()
	assert_bool(Input.is_action_pressed(&"run2")).is_true()
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()
	_drag(0, _left_thumb() + Vector2(0.0, -80.0))
	assert_bool(Input.is_action_pressed(&"up2")).is_true()
	_drag(0, _left_thumb() + Vector2(0.0, 80.0))
	assert_bool(Input.is_action_pressed(&"down2")).is_true()
	_drag(0, _left_thumb() + Vector2(-80.0, 0.0))
	assert_bool(Input.is_action_pressed(&"left2")).is_true()


func test_an_empty_sprint_action_takes_the_sprint_ring_away() -> void:
	var ring := _touch.stick.find_child("SprintRing", true, false) as Control
	assert_bool(ring.visible).is_true()
	_touch.sprint_action = &""
	assert_bool(ring.visible).is_false()
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(_touch.stick_radius * 1.4, 0.0))
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()


func test_the_stick_radius_and_the_sprint_ring_size_the_rings_and_the_push() -> void:
	_touch.stick_radius = 100.0
	_touch.sprint_ring = 0.6
	var ring := _touch.stick.find_child("Ring", true, false) as Control
	var sprint := _touch.stick.find_child("SprintRing", true, false) as Control
	assert_vector(ring.size).is_equal(Vector2(200.0, 200.0))
	assert_vector(sprint.size).is_equal(Vector2(120.0, 120.0))
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(70.0, 0.0))
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	assert_float(_touch.stick_vector().x).is_greater(0.6)


func test_the_deadzone_is_read_when_the_stick_moves() -> void:
	_touch.deadzone = 0.5
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(_touch.stick_radius * 0.4, 0.0))
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()
	_touch.deadzone = 0.0
	_drag(0, _left_thumb() + Vector2(_touch.stick_radius * 0.4, 0.0))
	assert_float(_touch.stick_vector().x).is_equal_approx(0.4, 0.001)


func test_the_look_sensitivity_scales_the_turn() -> void:
	_touch.look_sensitivity = 0.4
	_down(1, _right_thumb())
	_drag(1, _right_thumb() + Vector2(50.0, 0.0))
	await get_tree().process_frame
	assert_float(_total_look().x).is_equal_approx(20.0, 0.001)


func test_the_opacity_and_the_margin_follow_the_inspector() -> void:
	_touch.opacity = 0.8
	assert_float(_touch.safe_area.modulate.a).is_equal_approx(0.8, 0.001)
	_touch.margin = 120.0
	assert_float(_touch.safe_area.offset_left).is_equal(120.0)
	assert_float(_touch.safe_area.offset_bottom).is_equal(-120.0)
	var view := _touch.get_viewport().get_visible_rect()
	assert_float(_touch.button_center(0).y).is_less(view.end.y - 120.0)
	assert_float(_touch.button_center(0).x).is_less(view.end.x - 120.0)


func test_the_zones_decide_which_finger_does_what_and_show_on_request() -> void:
	assert_bool(_touch.move_zone.visible).is_false()
	_touch.show_zones = true
	assert_bool(_touch.move_zone.visible).is_true()
	assert_bool(_touch.look_zone.visible).is_true()
	_touch.show_zones = false
	assert_bool(_touch.look_zone.visible).is_false()
	# Shrink the move zone to a corner: a finger outside it does nothing.
	_touch.move_zone.anchor_right = 0.1
	_touch.move_zone.anchor_bottom = 0.2
	await get_tree().process_frame
	_down(0, _left_thumb())
	_drag(0, _left_thumb() + Vector2(100.0, 0.0))
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()


func test_a_button_moved_in_the_editor_is_where_it_is_pressed() -> void:
	var jump := _touch.buttons_root.get_child(0) as TouchButton
	var earlier := _touch.button_center(0)
	jump.position += Vector2(-500.0, -300.0)
	assert_vector(_touch.button_center(0)).is_equal_approx(
		earlier + Vector2(-500.0, -300.0), Vector2.ONE * 0.5
	)
	_down(2, earlier)
	assert_bool(Input.is_action_pressed(&"jump")).is_false()
	_up(2, earlier)
	_down(2, _touch.button_center(0))
	assert_bool(Input.is_action_pressed(&"jump")).is_true()
	_up(2, _touch.button_center(0))


func test_a_button_node_added_to_the_scene_is_a_button() -> void:
	var extra := preload("res://ui/touch/touch_button.tscn").instantiate() as TouchButton
	extra.action = &"sprint"
	extra.label = "Run"
	extra.set_anchors_preset(Control.PRESET_TOP_LEFT)
	extra.position = Vector2(700.0, 300.0)
	_touch.buttons_root.add_child(extra)
	await get_tree().process_frame
	assert_int(_touch.button_count()).is_equal(3)
	_down(3, _touch.button_center(2))
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	assert_bool(extra.held).is_true()
	_up(3, _touch.button_center(2))
	assert_bool(extra.held).is_false()
	assert_str((extra.get_node("%Label") as Label).text).is_equal("Run")


func test_a_button_shows_when_a_finger_is_on_it() -> void:
	var jump := _touch.buttons_root.get_child(0) as TouchButton
	var fill := jump.get_node("%Fill") as Control
	assert_float(fill.self_modulate.a).is_equal_approx(TouchButton.IDLE_FILL, 0.001)
	_down(2, _touch.button_center(0))
	assert_float(fill.self_modulate.a).is_equal_approx(TouchButton.HELD_FILL, 0.001)
	_up(2, _touch.button_center(0))
	assert_float(fill.self_modulate.a).is_equal_approx(TouchButton.IDLE_FILL, 0.001)


func test_the_stick_rings_move_to_where_the_thumb_landed() -> void:
	var pad := _touch.stick.find_child("Pad", true, false) as Control
	assert_vector(pad.position).is_equal(Vector2.ZERO)
	_down(0, _left_thumb())
	assert_vector(pad.global_position).is_equal_approx(_left_thumb(), Vector2.ONE * 0.5)
	_up(0, _left_thumb())
	assert_vector(pad.position).is_equal(Vector2.ZERO)
