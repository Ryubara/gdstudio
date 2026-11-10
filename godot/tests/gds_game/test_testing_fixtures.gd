# The test fixtures of `gds_game` every game's suites use: `ExportPins` and `InputSim`.
extends GdUnitTestSuite


class Pinned:
	extends Node
	@export var speed := 4.0
	@export var tint := Color.RED
	var hidden := 1


func after_test() -> void:
	InputSim.release_all()


func test_export_pins_lists_the_exports_only() -> void:
	var node: Pinned = auto_free(Pinned.new())
	assert_array(ExportPins.names(node)).contains_exactly([&"speed", &"tint"])


func test_export_pins_names_a_new_or_a_dropped_export() -> void:
	var node: Pinned = auto_free(Pinned.new())
	assert_array(ExportPins.differences(node, {&"speed": 4.0, &"tint": Color.RED})).is_empty()
	var found := ExportPins.differences(node, {&"speed": 4.0, &"gone": 1})
	assert_array(found).contains_exactly(
		["gone is pinned but not an export", "tint is an export with no pinned default"]
	)


func test_export_pins_compares_floats_to_a_millionth() -> void:
	var node: Pinned = auto_free(Pinned.new())
	var close := {&"speed": 4.0000001, &"tint": Color.RED}
	assert_array(ExportPins.wrong_values(node, close)).is_empty()
	assert_array(ExportPins.wrong_values(node, {&"speed": 5})).has_size(1)


func test_input_sim_presses_through_the_input_map() -> void:
	InputSim.key(KEY_ENTER, true)
	assert_bool(Input.is_action_pressed(&"ui_accept")).is_true()
	InputSim.key(KEY_ENTER, false)
	InputSim.pad_button(JOY_BUTTON_B, true)
	assert_bool(Input.is_action_pressed(&"ui_cancel")).is_true()


func test_input_sim_release_all_lets_go_of_every_action() -> void:
	# A game's own action with no key, pad button or mouse button that the fixture lets go of.
	InputMap.add_action(&"gds_test_own_action")
	Input.action_press(&"gds_test_own_action")
	InputSim.release_all()
	var still_down := Input.is_action_pressed(&"gds_test_own_action")
	InputMap.erase_action(&"gds_test_own_action")
	assert_bool(still_down).is_false()


func test_input_sim_waits_in_physics_ticks() -> void:
	var start := Engine.get_physics_frames()
	await InputSim.ticks(get_tree(), 3)
	assert_int(Engine.get_physics_frames() - start).is_equal(3)
