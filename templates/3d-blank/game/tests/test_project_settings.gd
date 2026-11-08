# The settings every GDStudio game keeps: the web build is WebGL2, so the web and phone builds use
# Compatibility and the desktop build uses Forward+ on top of the same level.
extends GdUnitTestSuite


func test_the_renderer_is_forward_plus_on_desktop_and_compatibility_on_web_and_phones() -> void:
	assert_str(ProjectSettings.get_setting("rendering/renderer/rendering_method")).is_equal(
		"forward_plus"
	)
	assert_str(ProjectSettings.get_setting("rendering/renderer/rendering_method.web")).is_equal(
		"gl_compatibility"
	)
	assert_str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")).is_equal(
		"gl_compatibility"
	)


func test_the_grid_cell_and_the_editor_snap_come_from_one_shader_global() -> void:
	var cell: Dictionary = ProjectSettings.get_setting("shader_globals/prototype_cell_size")
	assert_float(cell["value"]).is_greater(0.0)
	var project := ConfigFile.new()
	assert_int(project.load("res://project.godot")).is_equal(OK)
	var enabled := PackedStringArray(project.get_value("editor_plugins", "enabled", []))
	assert_bool(enabled.has("res://addons/prototype_grid/plugin.cfg")).is_true()


func test_the_web_preset_leaves_tests_and_tools_out_of_the_export() -> void:
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	var excluded := str(presets.get_value("preset.0", "exclude_filter", ""))
	for folder in ["tests/*", "tools/*", "addons/gdUnit4/*", "reports/*"]:
		assert_str(excluded).contains(folder)


func test_the_kit_ui_addon_is_registered_the_way_its_plugin_registers_itself() -> void:
	# A synced addon is not enabled for the game: without these two lines its scripts that
	# name `UIRouter` fail to parse (the demo, the focus ring) and the editor shows errors.
	assert_bool(ProjectSettings.has_setting("autoload/UIRouter")).is_true()
	assert_str(str(ProjectSettings.get_setting("autoload/UIRouter"))).is_equal(
		"*res://addons/gds_ui/router/ui_router.gd"
	)
	# The editor-only section is not a runtime setting, so the project file itself is read.
	var project := ConfigFile.new()
	assert_int(project.load("res://project.godot")).is_equal(OK)
	var enabled := PackedStringArray(
		project.get_value("editor_plugins", "enabled", PackedStringArray())
	)
	assert_bool(enabled.has("res://addons/gds_ui/plugin.cfg")).is_true()
