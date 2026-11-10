# The menus in the game scene: Esc pauses the real player and camera and Resume gives them back, the
# look settings reach the camera rig, the pause button follows the touch layer, and the touch layer
# lets go of its fingers when a menu covers it.
extends GdUnitTestSuite

var _scene: Node
var _rig: PlayerCamera
var _host: ScreenHost


func before_test() -> void:
	UIMotion.reduced = true
	Settings.reset_defaults()
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerCamera")
	_host = _scene.get_node("Screens")
	await get_tree().process_frame


func after_test() -> void:
	InputSim.release_all()
	UIMotion.reduced = false
	get_tree().paused = false
	await MenuFixture.clear(get_tree())
	Settings.reset_defaults()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


func test_the_game_scene_holds_the_host_with_the_pause_menu_and_the_look_bridge() -> void:
	assert_object(_host).is_not_null()
	assert_object(_host.pause_screen).is_not_null()
	assert_object(ScreenHost.current).is_same(_host)
	var look: LookSettings = _scene.get_node("LookSettings")
	assert_object(look.camera).is_same(_rig)


func test_escape_pauses_the_player_and_resume_gives_the_game_back() -> void:
	var player: Player = _scene.get_node("Player")
	var was := player.global_position
	InputSim.key(KEY_ESCAPE, true)
	InputSim.key(KEY_ESCAPE, false)
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_object(UIRouter.top()).is_instanceof(PauseMenu)
	# While paused, the key that walks does nothing.
	InputSim.key(KEY_W, true)
	for _frame in 20:
		await get_tree().physics_frame
	assert_float(player.global_position.distance_to(was)).is_less(0.05)
	InputSim.key(KEY_W, false)
	_host.close()
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	assert_bool(get_tree().paused).is_false()
	InputSim.key(KEY_W, true)
	for _frame in 40:
		await get_tree().physics_frame
	InputSim.key(KEY_W, false)
	assert_float(player.global_position.distance_to(was)).is_greater(0.3)


func test_the_mouse_look_is_the_designers_value_times_the_players() -> void:
	_rig.require_captured_mouse = false
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10.0, 0.0)
	var yaw := _rig.yaw
	_rig._unhandled_input(motion)
	var base := absf(angle_difference(deg_to_rad(yaw), deg_to_rad(_rig.yaw)))
	assert_float(rad_to_deg(base)).is_equal_approx(10.0 * _rig.mouse_sensitivity, 0.01)
	Settings.set_value(SettingsService.MOUSE_SENSITIVITY, 2.0)
	assert_float(_rig.player_sensitivity).is_equal_approx(2.0, 0.0001)
	yaw = _rig.yaw
	_rig._unhandled_input(motion)
	var doubled := absf(angle_difference(deg_to_rad(yaw), deg_to_rad(_rig.yaw)))
	assert_float(doubled).is_equal_approx(base * 2.0, 0.001)
	assert_float(_rig.mouse_sensitivity).is_equal_approx(0.12, 0.0001)


func test_the_players_invert_flips_the_vertical_look_and_twice_flips_it_back() -> void:
	_rig.pitch = 0.0
	_rig.orbit(Vector2(0.0, 5.0))
	var normal := _rig.pitch
	assert_float(normal).is_greater(0.0)
	Settings.set_value(SettingsService.INVERT_Y, true)
	assert_bool(_rig.player_invert_y).is_true()
	_rig.pitch = 0.0
	_rig.orbit(Vector2(0.0, 5.0))
	assert_float(_rig.pitch).is_equal_approx(-normal, 0.0001)
	_rig.invert_y = true
	_rig.pitch = 0.0
	_rig.orbit(Vector2(0.0, 5.0))
	assert_float(_rig.pitch).is_equal_approx(normal, 0.0001)
	_rig.invert_y = false


func test_the_look_settings_are_applied_when_the_game_scene_starts() -> void:
	Settings.set_value(SettingsService.MOUSE_SENSITIVITY, 1.5)
	Settings.set_value(SettingsService.INVERT_Y, true)
	var again := scene_runner("res://main.tscn").scene().get_node("PlayerCamera") as PlayerCamera
	assert_float(again.player_sensitivity).is_equal_approx(1.5, 0.0001)
	assert_bool(again.player_invert_y).is_true()


func test_a_setting_that_is_not_a_look_setting_leaves_the_camera_alone() -> void:
	Settings.set_value(SettingsService.MOUSE_SENSITIVITY, 2.5)
	Settings.set_value(SettingsService.VOLUME_SFX, 20)
	assert_float(_rig.player_sensitivity).is_equal_approx(2.5, 0.0001)


## A finger touching and lifting at once, which shows the touch layer (in its automatic mode).
func _show_touch(touch: TouchControls) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 7
		event.pressed = pressed
		event.position = Vector2(960.0, 100.0)
		touch._input(event)


func test_the_pause_button_waits_for_a_touch_screen() -> void:
	var button: PauseButton = _scene.get_node("MenuLayer/PauseButton")
	var touch: TouchControls = _scene.get_node("TouchControls")
	assert_bool(button.visible).is_equal(touch.is_shown())
	_show_touch(touch)
	assert_bool(touch.is_shown()).is_true()
	assert_bool(button.visible).is_true()
	# A key hides the touch layer again, and the button with it.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	touch._input(key)
	assert_bool(button.visible).is_false()


func test_pressing_the_pause_button_opens_the_pause_menu() -> void:
	var button: PauseButton = _scene.get_node("MenuLayer/PauseButton")
	button.pressed.emit()
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	assert_object(UIRouter.top()).is_instanceof(PauseMenu)
	assert_bool(get_tree().paused).is_true()


func test_the_touch_layer_lets_go_when_a_menu_opens() -> void:
	var touch: TouchControls = _scene.get_node("TouchControls")
	var connected := _host.opened.get_connections().any(
		func(connection: Dictionary) -> bool:
			return (connection["callable"] as Callable).get_object() == touch
	)
	assert_bool(connected).is_true()
	_show_touch(touch)
	Input.action_press(&"jump")
	touch._pressed[&"jump"] = 1.0
	_host.open_pause()
	await MenuFixture.settle(get_tree())
	assert_bool(Input.is_action_pressed(&"jump")).is_false()


func test_touch_still_presses_the_menus_buttons() -> void:
	var touch: TouchControls = _scene.get_node("TouchControls")
	_show_touch(touch)
	assert_bool(Input.emulate_mouse_from_touch).is_false()
	_host.open_pause()
	await MenuFixture.settle(get_tree())
	assert_bool(Input.emulate_mouse_from_touch).is_true()
	_host.close()
	await MenuFixture.settle(get_tree())
	assert_bool(Input.emulate_mouse_from_touch).is_false()
