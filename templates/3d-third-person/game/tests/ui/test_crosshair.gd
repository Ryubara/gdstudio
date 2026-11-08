# The crosshair: a node in the HUD scene that the game shows only while the player aims, that sits
# at the middle of the screen by its anchors (where the weapon aims), and whose look is its
# exports. It draws itself, so there is no texture to find.
extends GdUnitTestSuite

const SCENE := "res://ui/hud/crosshair.tscn"

var _scene: Node
var _crosshair: Crosshair
var _player: Player


func before_test() -> void:
	_scene = scene_runner("res://main.tscn").scene()
	_crosshair = _scene.get_node("Hud/Crosshair")
	_player = _scene.get_node("Player")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_scene)


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(load(SCENE).instantiate()) as Crosshair
	var pins := {
		&"player": null,
		&"radius": 6.0,
		&"color": Color(1.0, 1.0, 1.0, 1.0),
		&"outline_color": Color(0.04, 0.05, 0.08, 0.5),
		&"outline_width": 1.5,
		&"only_while_aiming": true,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()


func test_it_is_hidden_until_the_player_aims_and_hides_again() -> void:
	assert_bool(_crosshair.visible).is_false()
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_crosshair.visible).is_true()
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_crosshair.visible).is_false()


func test_firing_shows_it_too_and_the_right_mouse_button_does() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_crosshair.visible).is_true()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_crosshair.visible).is_false()
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_crosshair.visible).is_true()


func test_always_visible_when_it_is_told_not_to_hide() -> void:
	_crosshair.only_while_aiming = false
	assert_bool(_crosshair.visible).is_true()
	_crosshair.only_while_aiming = true
	assert_bool(_crosshair.visible).is_false()


func test_it_sits_at_the_middle_of_the_screen_where_the_weapon_aims() -> void:
	var viewport := _crosshair.get_viewport().get_visible_rect().size
	var middle := _crosshair.get_global_rect().get_center()
	assert_vector(middle).is_equal_approx(viewport / 2.0, Vector2.ONE * 0.6)
	# The weapon's ray goes through the same point, so the shot ends under the circle.
	var camera := _crosshair.get_viewport().get_camera_3d()
	var ray := camera.project_ray_normal(middle)
	var aimed := camera.project_ray_normal(viewport / 2.0)
	assert_float(ray.dot(aimed)).is_greater(0.99999)


func test_a_bigger_radius_keeps_it_centred() -> void:
	var viewport := _crosshair.get_viewport().get_visible_rect().size
	_crosshair.radius = 20.0
	_crosshair.outline_width = 4.0
	await get_tree().process_frame
	assert_vector(_crosshair.get_global_rect().get_center()).is_equal_approx(
		viewport / 2.0, Vector2.ONE * 0.6
	)
	assert_float(_crosshair.get_global_rect().size.x).is_equal_approx((20.0 + 4.0) * 2.0 + 2.0, 0.5)


func test_the_colours_and_the_ring_follow_the_exports() -> void:
	_crosshair.color = Color(0.2, 1.0, 0.2)
	_crosshair.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	_crosshair.outline_width = 0.0
	assert_object(_crosshair.color).is_equal(Color(0.2, 1.0, 0.2))
	assert_float(_crosshair.get_global_rect().size.x).is_equal_approx((6.0 + 0.0) * 2.0 + 2.0, 0.5)


func test_it_sits_in_the_hud_layer_not_in_an_inset_box_and_ignores_the_mouse() -> void:
	assert_object(_crosshair.get_parent()).is_instanceof(CanvasLayer)
	assert_int(_crosshair.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_float(_crosshair.anchor_left).is_equal(0.5)
	assert_float(_crosshair.anchor_right).is_equal(0.5)
	assert_float(_crosshair.anchor_top).is_equal(0.5)
	assert_float(_crosshair.anchor_bottom).is_equal(0.5)


func test_the_script_is_a_tool_script_so_the_editor_shows_it() -> void:
	var source := FileAccess.get_file_as_string("res://ui/hud/crosshair.gd")
	assert_bool(source.begins_with("@tool")).is_true()
	assert_bool(source.contains("draw_circle")).is_true()
	assert_bool(source.contains("Texture")).is_false()
