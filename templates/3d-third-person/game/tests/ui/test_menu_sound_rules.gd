# The menus' sounds follow their rules (`MenuSoundService`): each kind of press has its weight,
# hover and focus are one hint, hints are spaced and never sound for a finger, a screen's swish
# gives way to the press that opened it, Esc is Back, slider ticks are spaced and rise with the
# value, a toggle's two states have two pitches. Driven with real keys where a player would press.
extends GdUnitTestSuite

const SCENE := "res://ui/menus/menu_sound_service.tscn"
const SCREENS := {
	"main menu": "res://ui/menus/main_menu.tscn",
	"pause menu": "res://ui/menus/pause_menu.tscn",
	"settings": "res://ui/menus/settings_menu.tscn",
}
## Each player's volume (dB) and base pitch: the ladder of `gamedev/audio/ui-sounds.md`.
const LEVELS := {
	&"Hint": [-15.0, 1.0],
	&"Press": [-7.0, 1.0],
	&"Confirm": [-10.0, 1.0],
	&"Back": [-9.0, 0.8],
	&"Refuse": [-9.0, 0.67],
	&"Tab": [-13.0, 1.0],
	&"Select": [-13.0, 1.12],
	&"ToggleOn": [-13.0, 1.12],
	&"ToggleOff": [-13.0, 0.89],
	&"Tick": [-17.0, 1.0],
	&"Open": [-7.0, 1.0],
	&"Close": [-9.0, 0.85],
}

var _sounds: MenuSoundService
var _window_size := Vector2i.ZERO


func before_test() -> void:
	_window_size = get_window().size
	get_window().size = Vector2i(1920, 1080)
	UIMotion.reduced = true
	UIInputMode.touch = false
	_sounds = (load(SCENE) as PackedScene).instantiate() as MenuSoundService
	add_child(_sounds)


func after_test() -> void:
	InputSim.release_all()
	UIMotion.reduced = false
	UIInputMode.touch = false
	await MenuFixture.clear(get_tree())
	AudioSettings.stop_players(_sounds)
	_sounds.free()
	AudioSettings.drain_mixer()
	# The project's own service takes the cues again.
	var autoload := get_node_or_null(^"/root/MenuSounds") as MenuSoundService
	if autoload != null:
		UIAudio.handler = autoload.handle
	get_window().size = _window_size


func _open(path: String) -> Control:
	UIRouter.reset(path, UITransition.Kind.CUT)
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	await get_tree().process_frame
	_sounds.advance(1.0)
	_sounds.heard.clear()
	return UIRouter.top()


## The sounds heard since the list was cleared, `&""` for a cue that stayed silent.


func _heard() -> Array:
	return _sounds.heard.map(func(entry: Array) -> StringName: return entry[1])


func _played() -> Array:
	return _heard().filter(func(sound: StringName) -> bool: return sound != &"")


func test_each_kind_of_button_press_has_its_weight() -> void:
	var menu := await _open(SCREENS["main menu"])
	# The cue each button sends on its press (pressing Play itself would load the game).
	UIAudio.play(&"press", menu.get_node("%PlayButton"))
	_sounds.advance(1.0)
	UIAudio.play(&"press", menu.get_node("%SettingsButton"))
	assert_array(_heard()).is_equal([&"Confirm", &"Press"])


func test_a_settings_tab_sounds_as_a_tab_and_back_as_back_whatever_their_look() -> void:
	var settings := await _open(SCREENS["settings"])
	# The tabs and Back are drawn as primary or ghost buttons; their role is set on the node.
	(settings.get_node("%AudioTab") as UIButton).pressed.emit()
	_sounds.advance(1.0)
	(settings.get_node("%BackButton") as UIButton).pressed.emit()
	assert_array(_played().slice(0, 2)).is_equal([&"Tab", &"Back"])


func test_hover_and_focus_on_one_control_are_one_hint() -> void:
	var menu := await _open(SCREENS["main menu"])
	var settings := menu.get_node("%SettingsButton") as UIButton
	UIAudio.play(&"hover", settings)
	settings.grab_focus()
	await get_tree().process_frame
	assert_array(_heard()).is_equal([&"Hint", &""])


func test_a_pointer_swept_down_the_menu_is_spaced_not_a_drum_roll() -> void:
	var menu := await _open(SCREENS["main menu"])
	var buttons: Array[Node] = menu.find_children("*", "UIButton", true, false)
	get_viewport().gui_release_focus()
	# Ten hovers in half a second.
	for i in 10:
		UIAudio.play(&"hover", buttons[i % buttons.size()])
		_sounds.advance(0.05)
	var hints := _played().size()
	assert_int(hints).is_between(4, 6)


func test_a_finger_and_a_disabled_button_make_no_hint() -> void:
	var menu := await _open(SCREENS["main menu"])
	var play := menu.get_node("%PlayButton") as UIButton
	var quit := menu.get_node("%QuitButton") as UIButton
	UIInputMode.touch = true
	UIAudio.play(&"hover", quit)
	UIInputMode.touch = false
	_sounds.advance(1.0)
	play.disabled = true
	UIAudio.play(&"hover", play)
	assert_array(_played()).is_empty()


func test_the_press_is_the_sound_of_the_screen_it_opens() -> void:
	var menu := await _open(SCREENS["main menu"])
	var settings := menu.get_node("%SettingsButton") as UIButton
	settings.grab_focus()
	_sounds.advance(1.0)
	_sounds.heard.clear()
	settings.pressed.emit()
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	# The press, then the push and the new screen's first focus stay silent.
	assert_array(_played()).is_equal([&"Press"])
	assert_bool(_sounds.heard.any(func(e: Array) -> bool: return e[0] == &"push")).is_true()


func test_a_screen_opened_with_nothing_pressed_swishes_in_and_out() -> void:
	UIAudio.play(&"push", UIRouter)
	_sounds.advance(1.0)
	UIAudio.play(&"pop", UIRouter)
	assert_array(_heard()).is_equal([&"Open", &"Close"])


func test_escape_is_back_and_the_screen_it_closes_stays_quiet() -> void:
	var menu := await _open(SCREENS["main menu"])
	(menu.get_node("%SettingsButton") as UIButton).pressed.emit()
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	_sounds.advance(1.0)
	_sounds.heard.clear()
	InputSim.key(KEY_ESCAPE, true)
	InputSim.key(KEY_ESCAPE, false)
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_array(_played()).is_equal([&"Back"])


func test_the_arrow_keys_move_the_focus_with_a_hint() -> void:
	var menu := await _open(SCREENS["main menu"])
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.get_node("%PlayButton"))
	InputSim.key(KEY_DOWN, true)
	InputSim.key(KEY_DOWN, false)
	await get_tree().process_frame
	assert_object(get_viewport().gui_get_focus_owner()).is_not_same(menu.get_node("%PlayButton"))
	assert_array(_played()).is_equal([&"Hint"])


func test_slider_ticks_are_spaced_and_rise_with_the_value() -> void:
	var slider := UISlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	add_child(slider)
	await get_tree().process_frame
	_sounds.advance(1.0)
	_sounds.heard.clear()
	# A fast drag over all 20 steps in a third of a second.
	for i in 20:
		slider.value = (i + 1) * slider.step
		_sounds.advance(1.0 / 60.0)
	var ticks := _played().size()
	assert_int(ticks).is_between(4, 8)
	var tick := _sounds.get_node("Tick") as AudioStreamPlayer
	slider.set_value_no_signal(slider.min_value)
	_sounds.advance(1.0)
	UIAudio.play(&"tick", slider)
	var low := tick.pitch_scale
	slider.set_value_no_signal(slider.max_value)
	_sounds.advance(1.0)
	UIAudio.play(&"tick", slider)
	assert_float(low).is_equal_approx(0.9, 0.001)
	assert_float(tick.pitch_scale).is_equal_approx(1.25, 0.001)
	slider.free()


func test_a_toggle_says_its_new_state_with_two_pitches() -> void:
	var settings := await _open(SCREENS["settings"])
	var toggle := settings.find_children("*", "UIToggle", true, false)[0] as UIToggle
	UIAudio.play(&"on", toggle)
	_sounds.advance(1.0)
	UIAudio.play(&"off", toggle)
	assert_array(_heard()).is_equal([&"ToggleOn", &"ToggleOff"])
	var on := (_sounds.get_node("ToggleOn") as AudioStreamPlayer).pitch_scale
	assert_float(on).is_greater((_sounds.get_node("ToggleOff") as AudioStreamPlayer).pitch_scale)


func test_typing_is_silent_and_an_unknown_cue_is_reported_not_played() -> void:
	var menu := await _open(SCREENS["main menu"])
	var field := menu.get_node("%AddressField")
	assert_bool(MenuSoundService.knows(&"press", field)).is_false()
	UIAudio.play(&"press", field)
	assert_array(_played()).is_empty()


func test_off_plays_nothing() -> void:
	_sounds.enabled = false
	UIAudio.play(&"confirm")
	assert_array(_played()).is_empty()
