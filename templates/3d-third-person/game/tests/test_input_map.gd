# The character input actions: each has a key, the ones that matter have a pad binding too, and
# no two gameplay actions share a pad button or a stick direction.
extends GdUnitTestSuite

const ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_forward",
	&"move_back",
	&"look_left",
	&"look_right",
	&"look_up",
	&"look_down",
	&"jump",
	&"sprint",
	&"walk",
	&"interact",
	&"crouch",
	&"prone",
	&"aim",
	&"fire",
	&"reload",
	&"next_weapon",
	&"previous_weapon",
	&"toggle_unarmed",
]


func test_every_action_exists_and_is_bound_for_every_device() -> void:
	for action in ACTIONS:
		assert_bool(InputMap.has_action(action)).override_failure_message(action).is_true()
		for event in InputMap.action_get_events(action):
			assert_int(event.device).override_failure_message(action).is_equal(-1)


func test_the_move_jump_and_interact_actions_work_from_a_pad_and_a_keyboard() -> void:
	for action: StringName in [
		&"move_left",
		&"move_forward",
		&"jump",
		&"interact",
		&"sprint",
		&"crouch",
		&"prone",
		&"aim",
		&"fire",
		&"reload",
		&"next_weapon",
		&"previous_weapon",
		&"toggle_unarmed",
	]:
		var has_pad := false
		var has_key := false
		for event in InputMap.action_get_events(action):
			has_pad = has_pad or event is InputEventJoypadButton or event is InputEventJoypadMotion
			has_key = has_key or event is InputEventKey or event is InputEventMouseButton
		assert_bool(has_pad).override_failure_message("%s has no pad" % action).is_true()
		assert_bool(has_key).override_failure_message("%s has no key" % action).is_true()


func test_no_two_actions_share_a_pad_button_or_a_stick_direction() -> void:
	var seen := {}
	for action in ACTIONS:
		for event in InputMap.action_get_events(action):
			var key := ""
			if event is InputEventJoypadButton:
				key = "button %d" % (event as InputEventJoypadButton).button_index
			elif event is InputEventJoypadMotion:
				var motion := event as InputEventJoypadMotion
				key = "axis %d %s" % [motion.axis, signf(motion.axis_value)]
			if key == "":
				continue
			(
				assert_bool(seen.has(key))
				. override_failure_message("%s and %s both use %s" % [seen.get(key), action, key])
				. is_false()
			)
			seen[key] = action
