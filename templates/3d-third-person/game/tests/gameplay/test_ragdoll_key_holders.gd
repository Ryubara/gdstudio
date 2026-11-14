# `RagdollKeyHolders`: a key stays on the action while one holder holds it, and the last holder
# takes it off (the counts every `PlayerInput` shares, gdstudio #1500).
extends GdUnitTestSuite

const ACTION := &"test_ragdoll_key_holders"


func before_test() -> void:
	InputMap.add_action(ACTION)


func after_test() -> void:
	InputMap.erase_action(ACTION)


func test_a_key_stays_on_the_action_until_its_last_holder_lets_go() -> void:
	RagdollKeyHolders.hold(ACTION, KEY_F9)
	RagdollKeyHolders.hold(ACTION, KEY_F9)
	assert_int(InputMap.action_get_events(ACTION).size()).is_equal(1)
	assert_int(RagdollKeyHolders.count(KEY_F9)).is_equal(2)
	RagdollKeyHolders.release(ACTION, KEY_F9)
	assert_int(InputMap.action_get_events(ACTION).size()).is_equal(1)
	RagdollKeyHolders.release(ACTION, KEY_F9)
	assert_array(InputMap.action_get_events(ACTION)).is_empty()
	assert_int(RagdollKeyHolders.count(KEY_F9)).is_equal(0)


func test_two_keys_are_counted_apart() -> void:
	RagdollKeyHolders.hold(ACTION, KEY_F9)
	RagdollKeyHolders.hold(ACTION, KEY_F10)
	RagdollKeyHolders.release(ACTION, KEY_F9)
	var events := InputMap.action_get_events(ACTION)
	assert_int(events.size()).is_equal(1)
	assert_int((events[0] as InputEventKey).physical_keycode).is_equal(KEY_F10)
	RagdollKeyHolders.release(ACTION, KEY_F10)
	assert_int(RagdollKeyHolders.count(KEY_F10)).is_equal(0)
