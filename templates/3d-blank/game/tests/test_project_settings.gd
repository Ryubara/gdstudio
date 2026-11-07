# The settings every GDStudio game keeps: the web build is WebGL2, so only Compatibility is used.
extends GdUnitTestSuite


func test_the_renderer_is_compatibility_on_every_platform() -> void:
	assert_str(ProjectSettings.get_setting("rendering/renderer/rendering_method")).is_equal(
		"gl_compatibility"
	)
	assert_str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")).is_equal(
		"gl_compatibility"
	)


func test_the_web_preset_leaves_tests_and_tools_out_of_the_export() -> void:
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	var excluded := str(presets.get_value("preset.0", "exclude_filter", ""))
	for folder in ["tests/*", "tools/*", "addons/gdUnit4/*", "reports/*"]:
		assert_str(excluded).contains(folder)
