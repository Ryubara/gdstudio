# The minimap's inspector contract: every export has its default pinned, the shader's own defaults
# are the exports' defaults (what the editor shows is what the game starts with), and a change
# to a look export reaches the picture at run time.
extends GdUnitTestSuite

const SCENE := "res://ui/minimap/minimap.tscn"

var _root: Control
var _minimap: Minimap


func before_test() -> void:
	_root = auto_free(Control.new()) as Control
	_root.size = Vector2(800.0, 600.0)
	add_child(_root)
	_minimap = load(SCENE).instantiate() as Minimap
	_root.add_child(_minimap)
	await get_tree().process_frame
	await get_tree().process_frame


func _material() -> ShaderMaterial:
	return (_minimap.get_node("%Map") as ColorRect).material as ShaderMaterial


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(load(SCENE).instantiate()) as Minimap
	var pins := {
		&"target": null,
		&"target_group": &"player",
		&"shape": 0,
		&"map_size": 220.0,
		&"max_screen_fraction": 0.25,
		&"corner_ratio": 0.25,
		&"range_m": 30.0,
		&"range_min": 12.0,
		&"range_max": 90.0,
		&"zoom_step": 1.3,
		&"zoom_smoothing": 10.0,
		&"rotation_mode": 2,
		&"turn_smoothing": 8.0,
		&"follow_target": true,
		&"fixed_centre": Vector2.ZERO,
		&"zoom_in_action": &"map_zoom_in",
		&"zoom_out_action": &"map_zoom_out",
		&"source": 0,
		&"image": null,
		&"image_world_rect": Rect2(-25.0, -25.0, 50.0, 50.0),
		&"live_layers": 1,
		&"live_height": 40.0,
		&"live_depth": 30.0,
		&"live_resolution_scale": 1.0,
		&"live_unshaded": true,
		&"background_color": Color(0.04, 0.06, 0.09, 0.85),
		&"border_color": Color(0.9, 0.93, 1.0, 0.9),
		&"border_width": 3.0,
		&"edge_fade": 0.12,
		&"opacity": 1.0,
		&"tint_enabled": true,
		&"tint_dark": Color(0.1, 0.14, 0.2, 1.0),
		&"tint_light": Color(0.62, 0.76, 0.85, 1.0),
		&"marker_scale": 1.0,
		&"show_north": true,
		&"show_self": true,
		&"default_icon": load("res://assets/ui/minimap/dot.png"),
		&"default_edge_icon": load("res://assets/ui/minimap/arrow.png"),
		&"hidden_kinds": PackedStringArray(),
		&"pool_prewarm": 32,
		&"max_markers": 1000,
		&"map_update_rate": 0.0,
		&"marker_update_rate": 0.0,
		&"still_refresh_seconds": 1.0,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()


func test_the_shaders_own_defaults_are_the_exports_defaults() -> void:
	var code := _material().shader.code
	var fresh := auto_free(load(SCENE).instantiate()) as Minimap
	var pairs := {
		&"circular": true,
		&"corner_ratio": fresh.corner_ratio,
		&"background_color": fresh.background_color,
		&"border_color": fresh.border_color,
		&"border_px": fresh.border_width,
		&"edge_fade": fresh.edge_fade,
		&"opacity": fresh.opacity,
		&"tint_enabled": fresh.tint_enabled,
		&"tint_dark": fresh.tint_dark,
		&"tint_light": fresh.tint_light,
	}
	for uniform in pairs:
		var default: Variant = _shader_default(code, uniform)
		var want: Variant = pairs[uniform]
		var message := String(uniform)
		if want is Color:
			(
				assert_bool((default as Color).is_equal_approx(want))
				. override_failure_message(message)
				. is_true()
			)
		elif want is float:
			assert_float(default).override_failure_message(message).is_equal_approx(want, 0.0001)
		else:
			assert_bool(default == want).override_failure_message(message).is_true()


# The default written in the shader's source for `uniform`: a bool, a float or a vec4 as a Color
# (a headless run has no renderer to ask).
func _shader_default(code: String, uniform: StringName) -> Variant:
	var pattern := RegEx.create_from_string("uniform\\s+(\\w+)\\s+%s[^=;]*=\\s*([^;]+);" % uniform)
	var found := pattern.search(code)
	if found == null:
		return null
	var text := found.get_string(2).strip_edges()
	match found.get_string(1):
		"bool":
			return text == "true"
		"float":
			return text.to_float()
		"vec4":
			var parts := text.trim_prefix("vec4(").trim_suffix(")").split(",")
			return Color(
				parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float()
			)
	return null


func test_a_look_export_reaches_the_shader_at_run_time() -> void:
	_minimap.background_color = Color(1.0, 0.0, 0.0, 0.5)
	_minimap.border_color = Color(0.0, 1.0, 0.0, 1.0)
	_minimap.border_width = 9.0
	_minimap.edge_fade = 0.4
	_minimap.opacity = 0.6
	_minimap.tint_enabled = false
	_minimap.tint_dark = Color.BLUE
	_minimap.tint_light = Color.YELLOW
	_minimap.corner_ratio = 0.5
	var material := _material()
	(
		assert_bool(
			(material.get_shader_parameter(&"background_color") as Color).is_equal_approx(
				Color(1.0, 0.0, 0.0, 0.5)
			)
		)
		. is_true()
	)
	(
		assert_bool(
			(material.get_shader_parameter(&"border_color") as Color).is_equal_approx(
				Color(0.0, 1.0, 0.0, 1.0)
			)
		)
		. is_true()
	)
	assert_float(material.get_shader_parameter(&"border_px")).is_equal(9.0)
	assert_float(material.get_shader_parameter(&"edge_fade")).is_equal_approx(0.4, 0.0001)
	assert_float(material.get_shader_parameter(&"opacity")).is_equal_approx(0.6, 0.0001)
	assert_bool(material.get_shader_parameter(&"tint_enabled")).is_false()
	(
		assert_bool(
			(material.get_shader_parameter(&"tint_dark") as Color).is_equal_approx(Color.BLUE)
		)
		. is_true()
	)
	(
		assert_bool(
			(material.get_shader_parameter(&"tint_light") as Color).is_equal_approx(Color.YELLOW)
		)
		. is_true()
	)
	assert_float(material.get_shader_parameter(&"corner_ratio")).is_equal_approx(0.5, 0.0001)
	assert_float((_minimap.get_node("%Icons") as Control).modulate.a).is_equal_approx(0.6, 0.0001)


func test_the_shape_switches_between_a_circle_and_a_square() -> void:
	assert_bool(_material().get_shader_parameter(&"circular")).is_true()
	_minimap.shape = Minimap.Shape.SQUARE
	assert_bool(_material().get_shader_parameter(&"circular")).is_false()
	_minimap.refresh_now()
	assert_bool(_minimap.projector().circular).is_false()
	_minimap.shape = Minimap.Shape.CIRCLE
	_minimap.refresh_now()
	assert_bool(_minimap.projector().circular).is_true()


func test_the_size_sets_the_widgets_side_and_the_square_inside_follows() -> void:
	_minimap.map_size = 300.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(_minimap.custom_minimum_size).is_equal(Vector2(300.0, 300.0))
	assert_vector((_minimap.get_node("%Square") as Control).size).is_equal(Vector2(300.0, 300.0))
	assert_float(_material().get_shader_parameter(&"widget_px")).is_equal(300.0)
	_minimap.refresh_now()
	assert_float(_minimap.projector().half_extent).is_equal(150.0)


func test_the_range_export_sets_the_zoom_goal() -> void:
	_minimap.range_m = 50.0
	_minimap.refresh_now()
	assert_float(_minimap.current_range()).is_equal_approx(50.0, 0.001)
	_minimap.range_m = 1000.0
	_minimap.refresh_now()
	assert_float(_minimap.current_range()).is_equal_approx(90.0, 0.001)


func test_the_picture_is_a_node_of_the_scene_with_its_parts_beside_it() -> void:
	for part in [
		"Square", "Map", "Icons", "Self", "North", "SectionTitle", "LiveView", "MapCamera"
	]:
		(
			assert_object(_minimap.get_node_or_null("%" + part))
			. override_failure_message(part)
			. is_not_null()
		)
	(
		assert_bool(
			(
				(_minimap.get_node("%MapCamera") as Camera3D).projection
				== Camera3D.PROJECTION_ORTHOGONAL
			)
		)
		. is_true()
	)


func test_a_scaled_up_parent_does_not_grow_the_map_past_its_share_of_the_screen() -> void:
	var holder := auto_free(Control.new()) as Control
	holder.scale = Vector2(3.0, 3.0)
	add_child(holder)
	var map := load(SCENE).instantiate() as Minimap
	holder.add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	var shown := map.get_viewport().get_visible_rect().size
	var want := minf(220.0, 0.25 * minf(shown.x, shown.y) / 3.0)
	assert_float(want).is_less(220.0)
	assert_float(map.custom_minimum_size.x).is_equal_approx(want, 0.01)
	map.max_screen_fraction = 0.0
	assert_float(map.custom_minimum_size.x).is_equal(220.0)
