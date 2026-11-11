# The Settings service: defaults, a value coerced into its range, applied the moment it changes
# (volume, resolution scale, quality, window mode), saved after a pause, read back, and a damaged
# file falling back to the defaults. The service is made from its scene on a file of its own, so the
# autoload and the person's file are never touched.
extends GdUnitTestSuite

const SCENE := "res://core/settings/settings_service.tscn"

var _service: SettingsService
## This run's own file, so a run beside it never reads or deletes it (TempUserFile).
var _path := TempUserFile.path("settings_test")
var _modes: Array[int] = []
var _msaa: Viewport.MSAA
var _scale: float


func before_test() -> void:
	TempUserFile.remove(_path)
	_msaa = get_tree().root.msaa_3d
	_scale = get_tree().root.scaling_3d_scale
	_modes.clear()
	_service = _make()


func after_test() -> void:
	AudioSettings.reset_player_gain()
	get_tree().root.msaa_3d = _msaa
	get_tree().root.scaling_3d_scale = _scale
	for bus in [&"Master", &"SFX", &"Ambient", &"UI"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), false)
	TempUserFile.remove(_path)


## A service from the scene, on a file of its own, with a stand-in for the real window.
func _make(path := "") -> SettingsService:
	var service := load(SCENE).instantiate() as SettingsService
	service.path = path
	service.is_web = false
	service.window_setter = func(mode: int) -> void: _modes.append(mode)
	add_child(service)
	return auto_free(service)


func test_every_export_has_its_default_pinned() -> void:
	var pins := {&"save_delay": 0.6, &"presets": _service.presets}
	assert_array(ExportPins.differences(_service, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_service, pins)).is_empty()
	assert_int(_service.presets.size()).is_equal(3)
	(
		assert_array(_service.presets.map(func(p: QualityPreset) -> String: return p.title))
		. is_equal(["Low", "Medium", "High"])
	)


func test_a_run_of_the_tests_keeps_the_options_in_memory() -> void:
	assert_bool(SettingsService.is_harness_run()).is_true()
	assert_str(SettingsService.default_path()).is_empty()
	assert_str(Settings.path).is_empty()


func test_the_defaults_are_what_the_screen_shows_on_a_first_start() -> void:
	var want := {
		SettingsService.WINDOW_MODE: SettingsService.WindowMode.WINDOWED,
		SettingsService.RESOLUTION_SCALE: 100,
		SettingsService.VSYNC: true,
		SettingsService.QUALITY: SettingsService.default_quality(),
		SettingsService.VOLUME_MASTER: 100,
		SettingsService.VOLUME_SFX: 100,
		SettingsService.VOLUME_AMBIENT: 100,
		SettingsService.VOLUME_UI: 100,
		SettingsService.MOUSE_SENSITIVITY: 1.0,
		SettingsService.INVERT_Y: false,
		SettingsService.PAUSE_IN_INVENTORY: true,
	}
	for key: StringName in want:
		assert_that(_service.get_value(key)).override_failure_message(str(key)).is_equal(want[key])


func test_a_value_is_coerced_into_its_range_and_type() -> void:
	_service.set_value(SettingsService.RESOLUTION_SCALE, 10)
	assert_int(_service.get_value(SettingsService.RESOLUTION_SCALE)).is_equal(50)
	_service.set_value(SettingsService.MOUSE_SENSITIVITY, 99.0)
	assert_float(_service.get_value(SettingsService.MOUSE_SENSITIVITY)).is_equal(3.0)
	_service.set_value(SettingsService.INVERT_Y, "yes")
	assert_bool(_service.get_value(SettingsService.INVERT_Y)).is_false()
	_service.set_value(SettingsService.VOLUME_SFX, NAN)
	assert_int(_service.get_value(SettingsService.VOLUME_SFX)).is_equal(100)
	_service.set_value(SettingsService.VOLUME_SFX, 42.4)
	assert_int(_service.get_value(SettingsService.VOLUME_SFX)).is_equal(42)


func test_an_unknown_key_is_ignored() -> void:
	_service.set_value(&"video/nothing", 3)
	assert_that(_service.get_value(&"video/nothing")).is_null()


func test_a_change_is_announced_once_and_the_same_value_is_not() -> void:
	var seen: Array = []
	_service.changed.connect(
		func(key: StringName, value: Variant) -> void: seen.append([key, value])
	)
	_service.set_value(SettingsService.VSYNC, false)
	_service.set_value(SettingsService.VSYNC, false)
	assert_array(seen).is_equal([[SettingsService.VSYNC, false]])


func test_a_volume_reaches_its_bus_at_once() -> void:
	var was := AudioSettings.bus_volume_db(&"SFX")
	_service.set_value(SettingsService.VOLUME_SFX, 50)
	assert_float(AudioSettings.player_gain(&"SFX")).is_equal_approx(0.5, 0.0001)
	assert_float(AudioSettings.bus_volume_db(&"SFX")).is_equal_approx(was + linear_to_db(0.5), 0.05)
	_service.set_value(SettingsService.VOLUME_SFX, 0)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX"))).is_true()
	_service.set_value(SettingsService.VOLUME_MASTER, 80)
	assert_float(AudioSettings.player_gain(&"Master")).is_equal_approx(0.8, 0.0001)
	_service.set_value(SettingsService.VOLUME_AMBIENT, 30)
	_service.set_value(SettingsService.VOLUME_UI, 10)
	assert_float(AudioSettings.player_gain(&"Ambient")).is_equal_approx(0.3, 0.0001)
	assert_float(AudioSettings.player_gain(&"UI")).is_equal_approx(0.1, 0.0001)


func test_values_saved_and_read_back_are_the_same() -> void:
	var first := _make(_path)
	first.set_value(SettingsService.VOLUME_UI, 35)
	first.set_value(SettingsService.RESOLUTION_SCALE, 60)
	first.set_value(SettingsService.INVERT_Y, true)
	first.set_value(SettingsService.MOUSE_SENSITIVITY, 1.75)
	first.set_value(SettingsService.QUALITY, 0)
	assert_int(first.save()).is_equal(OK)
	var second := _make(_path)
	assert_int(second.get_value(SettingsService.VOLUME_UI)).is_equal(35)
	assert_int(second.get_value(SettingsService.RESOLUTION_SCALE)).is_equal(60)
	assert_bool(second.get_value(SettingsService.INVERT_Y)).is_true()
	assert_float(second.get_value(SettingsService.MOUSE_SENSITIVITY)).is_equal_approx(1.75, 0.0001)
	assert_int(second.get_value(SettingsService.QUALITY)).is_equal(0)


func test_what_was_read_is_applied_at_start() -> void:
	var first := _make(_path)
	first.set_value(SettingsService.VOLUME_AMBIENT, 20)
	first.set_value(SettingsService.RESOLUTION_SCALE, 70)
	first.save()
	AudioSettings.reset_player_gain()
	get_tree().root.scaling_3d_scale = 1.0
	_make(_path)
	assert_float(AudioSettings.player_gain(&"Ambient")).is_equal_approx(0.2, 0.0001)
	assert_float(get_tree().root.scaling_3d_scale).is_equal_approx(0.7, 0.0001)


func test_an_idle_service_does_not_process_or_write_anything() -> void:
	var service := _make(_path)
	assert_bool(service.is_processing()).is_false()
	service.save_delay = 0.05
	await InputSim.ticks(get_tree(), 18)
	assert_int(service.write_count).is_zero()
	assert_bool(FileAccess.file_exists(_path)).is_false()
	service.set_value(SettingsService.VSYNC, false)
	assert_bool(service.is_processing()).is_true()
	await InputSim.ticks(get_tree(), 18)
	assert_bool(service.is_processing()).is_false()


func test_a_change_is_written_after_the_delay_and_a_drag_is_one_write() -> void:
	var service := _make(_path)
	service.save_delay = 0.1
	service.set_value(SettingsService.VOLUME_SFX, 90)
	service.set_value(SettingsService.VOLUME_SFX, 80)
	service.set_value(SettingsService.VOLUME_SFX, 70)
	assert_int(service.write_count).is_zero()
	await InputSim.ticks(get_tree(), 30)
	assert_int(service.write_count).is_equal(1)
	assert_bool(FileAccess.file_exists(_path)).is_true()


func test_a_damaged_file_falls_back_to_the_defaults_value_by_value() -> void:
	var file := ConfigFile.new()
	file.set_value("video", "resolution_scale", 9000)
	file.set_value("video", "vsync", "maybe")
	file.set_value("audio", "master", NAN)
	file.set_value("audio", "sfx", "loud")
	file.set_value("audio", "ui", 40)
	file.set_value("controls", "mouse_sensitivity", -5.0)
	file.set_value("controls", "invert_y", 1)
	file.save(_path)
	var service := _make(_path)
	assert_int(service.get_value(SettingsService.RESOLUTION_SCALE)).is_equal(100)
	assert_bool(service.get_value(SettingsService.VSYNC)).is_true()
	assert_int(service.get_value(SettingsService.VOLUME_MASTER)).is_equal(100)
	assert_int(service.get_value(SettingsService.VOLUME_SFX)).is_equal(100)
	assert_int(service.get_value(SettingsService.VOLUME_UI)).is_equal(40)
	assert_float(service.get_value(SettingsService.MOUSE_SENSITIVITY)).is_equal_approx(0.2, 0.0001)
	assert_bool(service.get_value(SettingsService.INVERT_Y)).is_false()


func test_a_file_that_is_not_a_config_file_leaves_the_defaults() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("this = is not [ a config")
	file.close()
	var service := _make(_path)
	assert_int(service.get_value(SettingsService.VOLUME_MASTER)).is_equal(100)


func test_reset_gives_every_value_its_default_and_applies_it() -> void:
	_service.set_value(SettingsService.VOLUME_SFX, 10)
	_service.set_value(SettingsService.RESOLUTION_SCALE, 55)
	_service.set_value(SettingsService.INVERT_Y, true)
	_service.reset_defaults()
	assert_int(_service.get_value(SettingsService.VOLUME_SFX)).is_equal(100)
	assert_int(_service.get_value(SettingsService.RESOLUTION_SCALE)).is_equal(100)
	assert_bool(_service.get_value(SettingsService.INVERT_Y)).is_false()
	assert_float(AudioSettings.player_gain(&"SFX")).is_equal(1.0)
	assert_float(get_tree().root.scaling_3d_scale).is_equal(1.0)
