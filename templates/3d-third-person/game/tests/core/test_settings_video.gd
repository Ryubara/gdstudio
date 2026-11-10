# The video options of the Settings service: the resolution scale reaches the 3D view, each quality
# step sets what its preset says (and a preset edited in the inspector is what the step does), and
# the window mode goes to the window while a browser leaves it alone.
extends GdUnitTestSuite

const SCENE := "res://core/settings/settings_service.tscn"

var _service: SettingsService
var _modes: Array[int] = []
var _msaa: Viewport.MSAA
var _scale: float


func before_test() -> void:
	_msaa = get_tree().root.msaa_3d
	_scale = get_tree().root.scaling_3d_scale
	_modes.clear()
	var service := load(SCENE).instantiate() as SettingsService
	service.path = ""
	service.is_web = false
	service.window_setter = func(mode: int) -> void: _modes.append(mode)
	add_child(service)
	_service = auto_free(service)


func after_test() -> void:
	get_tree().root.msaa_3d = _msaa
	get_tree().root.scaling_3d_scale = _scale


func test_a_computer_starts_on_high_and_a_browser_or_phone_on_medium() -> void:
	var expected := 1 if OS.has_feature("web") or OS.has_feature("mobile") else 2
	assert_int(SettingsService.default_quality()).is_equal(expected)


func test_the_resolution_scale_reaches_the_3d_view() -> void:
	_service.set_value(SettingsService.RESOLUTION_SCALE, 75)
	assert_float(get_tree().root.scaling_3d_scale).is_equal_approx(0.75, 0.0001)


func test_each_quality_step_sets_what_its_preset_says() -> void:
	for step in 3:
		_service.set_value(SettingsService.QUALITY, step)
		var preset := _service.presets[step]
		assert_int(get_tree().root.msaa_3d).override_failure_message(preset.title).is_equal(
			preset.msaa
		)
		assert_object(_service.current_preset()).is_same(preset)
	assert_int(_service.presets[0].msaa).is_not_equal(_service.presets[2].msaa)


func test_a_preset_edited_in_the_inspector_is_what_the_step_does() -> void:
	_service.presets[0].msaa = Viewport.MSAA_8X
	_service.set_value(SettingsService.QUALITY, 1)
	_service.set_value(SettingsService.QUALITY, 0)
	assert_int(get_tree().root.msaa_3d).is_equal(Viewport.MSAA_8X)


func test_the_window_mode_goes_to_the_window_and_a_browser_leaves_it_alone() -> void:
	_service.set_value(SettingsService.WINDOW_MODE, SettingsService.WindowMode.FULLSCREEN)
	assert_array(_modes).contains([DisplayServer.WINDOW_MODE_FULLSCREEN])
	var count := _modes.size()
	_service.is_web = true
	_service.set_value(SettingsService.WINDOW_MODE, SettingsService.WindowMode.WINDOWED)
	assert_int(_modes.size()).is_equal(count)
