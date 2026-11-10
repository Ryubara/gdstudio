# The player rig scene on its own: what a second local player would instance. It wires its own
# parts and needs nothing from the world, the HUD or the screen host to stand.
extends GdUnitTestSuite

const RIG := "res://ui/player_rig/player_rig.tscn"


func _make() -> PlayerRig:
	var rig := auto_free((load(RIG) as PackedScene).instantiate()) as PlayerRig
	rig.get_node("Player").start_at_spawn = false
	add_child(rig)
	return rig


func test_the_exports_point_at_the_rigs_own_parts() -> void:
	var rig := _make()
	await await_idle_frame()
	assert_object(rig.player).is_same(rig.get_node("Player"))
	assert_object(rig.camera_rig).is_same(rig.get_node("PlayerCamera"))
	assert_object(rig.touch).is_same(rig.get_node("TouchControls"))


func test_the_touch_layers_look_turn_orbits_the_rigs_camera() -> void:
	var rig := _make()
	await await_idle_frame()
	var yaw_before := rig.camera_rig.yaw
	rig.touch.look_turned.emit(Vector2(12.0, 0.0))
	assert_float(rig.camera_rig.yaw).is_not_equal(yaw_before)


func test_the_pause_button_follows_the_rigs_touch_layer_and_needs_no_host_wire() -> void:
	var rig := _make()
	await await_idle_frame()
	var button: PauseButton = rig.get_node("MenuLayer/PauseButton")
	assert_object(button.touch).is_same(rig.touch)
	assert_object(button.host).is_null()
	assert_int(rig.get_node("MenuLayer").layer).is_equal(2)


func test_no_probe_is_made_off_the_web() -> void:
	var rig := _make()
	await await_idle_frame()
	assert_object(rig.get_node_or_null("WebProbe")).is_null()
	assert_bool(WebProbe.asked()).is_false()
