# What a press of aim or fire does belongs to the weapon (`WeaponDef`'s Aim and zoom group): the
# fists punch without zooming the view, and each toggle (`fire_zooms`, `can_aim`,
# `fire_needs_aim`, `show_crosshair`, the zoom override) works through simulated input in the
# player's own scene and applies while the game runs.
extends GdUnitTestSuite

const PISTOL := "res://gameplay/weapon/pistol.tres"
const FISTS := "res://gameplay/weapon/fists.tres"

var _scene: Node
var _rig: PlayerCamera
var _player: Player
var _crosshair: Crosshair
var _window_size: Vector2i


func before_test() -> void:
	_window_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_player = _scene.get_node("PlayerRig/Player")
	_crosshair = _scene.get_node("Hud/Root/Center/Crosshair")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	get_tree().root.size = _window_size
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


# The held weapon's definition, a copy of its own so a change touches this test alone.
func _own_definition() -> WeaponDef:
	_player.weapon.definition = _player.weapon.definition.duplicate()
	return _player.weapon.definition


func _hold_fire(ticks := 40) -> void:
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), ticks)


func _hold_aim(ticks := 40) -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), ticks)


func test_the_defaults_keep_todays_behaviour_and_the_fists_do_not_zoom_on_fire() -> void:
	var fresh := WeaponDef.new()
	var pistol := load(PISTOL) as WeaponDef
	for definition: WeaponDef in [fresh, pistol]:
		assert_bool(definition.can_aim).is_true()
		assert_bool(definition.fire_needs_aim).is_false()
		assert_bool(definition.fire_zooms).is_true()
		assert_bool(definition.show_crosshair).is_true()
		assert_bool(definition.override_zoom).is_false()
	var fists := load(FISTS) as WeaponDef
	assert_bool(fists.fire_zooms).is_false()
	assert_bool(fists.can_aim).is_true()
	assert_bool(fists.fire_needs_aim).is_false()


func test_a_click_with_the_fists_punches_without_zooming_the_view() -> void:
	InputSim.key(KEY_H, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_H, false)
	await InputSim.ticks(get_tree(), 40)
	assert_str(_player.weapon.definition.display_name).is_equal("Fists")
	await _hold_fire()
	assert_bool(_player.fire_held).is_true()
	assert_float(_rig.fire_blend()).is_equal(0.0)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.distance, 0.001)
	assert_float(_rig.current_fov()).is_equal_approx(_rig.field_of_view, 0.001)


func test_fire_zooms_off_lets_go_of_the_fire_view_while_the_button_is_held() -> void:
	var definition := _own_definition()
	await _hold_fire()
	assert_float(_rig.fire_blend()).is_equal(1.0)
	definition.fire_zooms = false
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_player.fire_held).is_true()
	assert_float(_rig.fire_blend()).is_equal(0.0)
	assert_float(_rig.current_fov()).is_equal_approx(_rig.field_of_view, 0.001)


func test_can_aim_off_makes_the_aim_button_do_nothing_until_it_is_on_again() -> void:
	var definition := _own_definition()
	definition.can_aim = false
	await _hold_aim()
	assert_bool(_player.aim_held).is_false()
	assert_bool(_player.aiming).is_false()
	assert_float(_rig.aim_blend()).is_equal(0.0)
	definition.can_aim = true
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_player.aim_held).is_true()
	assert_float(_rig.aim_blend()).is_equal(1.0)


func test_fire_needs_aim_shoots_only_with_the_aim_button_held() -> void:
	var definition := _own_definition()
	definition.fire_needs_aim = true
	var full: int = _player.weapon.ammo
	await _hold_fire()
	assert_bool(_player.fire_held).is_false()
	assert_bool(_player.aiming).is_false()
	assert_int(_player.weapon.ammo).is_equal(full)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await _hold_aim()
	await _hold_fire(20)
	assert_bool(_player.fire_held).is_true()
	assert_int(_player.weapon.ammo).is_equal(full - 1)


func test_fire_needs_aim_with_can_aim_off_never_shoots() -> void:
	var definition := _own_definition()
	definition.fire_needs_aim = true
	definition.can_aim = false
	var full: int = _player.weapon.ammo
	await _hold_aim(10)
	await _hold_fire()
	assert_int(_player.weapon.ammo).is_equal(full)


func test_show_crosshair_off_hides_it_while_aiming_and_on_brings_it_back() -> void:
	var definition := _own_definition()
	await _hold_aim(8)
	assert_bool(_crosshair.visible).is_true()
	definition.show_crosshair = false
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_crosshair.visible).is_false()
	definition.show_crosshair = true
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_crosshair.visible).is_true()


func test_the_zoom_override_replaces_the_cameras_aim_and_fire_framing_live() -> void:
	var definition := _own_definition()
	definition.override_zoom = true
	definition.aim_fov = 40.0
	definition.aim_distance = 2.0
	definition.fire_fov = 62.0
	definition.fire_distance = 1.8
	definition.zoom_offset = Vector2(0.3, 0.2)
	var rest := _rig.current_view_offset()
	await _hold_fire()
	assert_float(_rig.current_fov()).is_equal_approx(62.0, 0.001)
	assert_float(_rig.current_distance()).is_equal_approx(1.8, 0.001)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await _hold_aim()
	assert_float(_rig.current_fov()).is_equal_approx(40.0, 0.001)
	assert_float(_rig.current_distance()).is_equal_approx(2.0, 0.001)
	var zoomed := _rig.current_view_offset()
	# Right shoulder: further right and up by the offset.
	assert_float(zoomed.x - rest.x).is_equal_approx(0.3 * signf(rest.x), 0.01)
	assert_float(zoomed.y - rest.y).is_equal_approx(0.2, 0.01)
	definition.aim_fov = 45.0
	_rig.advance(0.0)
	assert_float(_rig.current_fov()).is_equal_approx(45.0, 0.001)
	definition.override_zoom = false
	_rig.advance(0.0)
	assert_float(_rig.current_fov()).is_equal_approx(_rig.aim_fov, 0.001)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.aim_distance, 0.001)
