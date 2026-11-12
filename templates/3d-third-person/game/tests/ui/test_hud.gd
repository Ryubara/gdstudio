# The HUD's parts: regions that hold widgets, a widget base that binds to the player's signals, the
# coin counter and the crosshair in them, health and ammo parts that show only while their data
# exists (and survive a death, a revive and a model swap), and one theme resource. Health and ammo
# are fed by a stand-in (`HudSubject`): the real player has neither yet. Where the parts sit, on a
# phone and with the touch controls, is `test_hud_layout.gd`.
extends GdUnitTestSuite

const HEALTH := "res://ui/hud/hud_health.tscn"
const AMMO := "res://ui/hud/hud_ammo.tscn"
const THEME := "res://ui/hud/hud_theme.tres"

var _scene: Node
var _hud: Hud
var _player: Player
var _window_size: Vector2i


func before_test() -> void:
	InputSim.release_all()
	# A headless window is 64 pixels square: give it a desktop's size, so the stretch is 2/3.
	_window_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	_scene = scene_runner("res://main.tscn").scene()
	_hud = _scene.get_node("Hud")
	_player = _scene.get_node("PlayerRig/Player")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	get_tree().root.size = _window_size
	AudioDrain.stop_all(_scene)


func _region(region_name: StringName) -> Control:
	return _hud.region(region_name)


# A stand-in subject in the tree, and a copy of the scene `path` bound to it in `region_name`.
func _fed_part(path: String, region_name: StringName, subject: HudSubject) -> HudStat:
	add_child(auto_free(subject))
	var part := (load(path) as PackedScene).instantiate() as HudStat
	part.player = subject
	_hud.add_widget(part, region_name)
	return part


func test_the_hud_scene_has_its_regions_and_widgets() -> void:
	for region_name in Hud.REGIONS:
		assert_object(_region(region_name)).is_not_null()
	assert_object(_hud.root.get_node("Center/Crosshair")).is_instanceof(Crosshair)
	assert_object(_region(&"TopLeft").get_node("ItemCounter")).is_instanceof(ItemCounter)
	assert_object(_region(&"BottomLeft").get_node("HudHealth")).is_instanceof(HudStat)
	assert_object(_region(&"BottomRight").get_node("HudAmmo")).is_instanceof(HudStat)
	assert_object(_region(&"BottomRight").get_node("HudWeaponSlots")).is_instanceof(HudWeaponSlots)
	assert_object(_region(&"BottomCenter").get_node("HudHotbar")).is_instanceof(HudHotbar)
	assert_object(_hud.minimap_slot.get_parent()).is_same(_region(&"TopRight"))
	assert_array(_hud._get_configuration_warnings()).is_empty()


func test_every_hud_control_ignores_the_mouse() -> void:
	assert_int(_hud.widgets().size()).is_equal(6)
	for node in _hud.root.find_children("*", "Control", true, false):
		assert_int((node as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_a_part_with_no_data_is_hidden_and_takes_no_room() -> void:
	# The real player has health (#876) and the pistol's ammo, and has collected nothing.
	for widget in _hud.widgets():
		if widget is HudStat and (widget as HudStat).value_property == &"health":
			assert_bool(widget.has_data()).is_true()
			assert_bool(widget.visible).is_true()
		elif widget is HudStat and (widget as HudStat).value_property == &"ammo":
			assert_bool(widget.visible).is_true()
			assert_str((widget as HudStat).value_label.text).is_equal("12 | 36")
		elif widget is HudStat or widget is ItemCounter:
			assert_bool(widget.has_data()).is_false()
			assert_bool(widget.visible).is_false()


func test_the_health_shows_the_players_own_and_follows_a_hit() -> void:
	var health: HudStat = _region(&"BottomLeft").get_node("HudHealth")
	assert_str(health.value_label.text).is_equal("100 / 100")
	_player.take_hit(HitRecord.shot(34.0, &"chest", &"spine_03", Vector3.INF, Vector3.ZERO, 0.0))
	assert_str(health.value_label.text).is_equal("66 / 100")
	# The slot holds the template's minimap, so it shows.
	assert_bool(_hud.minimap_slot.visible).is_true()


func test_the_coin_counter_appears_at_the_first_coin_and_counts() -> void:
	var counter: ItemCounter = _region(&"TopLeft").get_node("ItemCounter")
	_player.collect(&"coin", 1)
	assert_bool(counter.visible).is_true()
	assert_str(counter.label.text).is_equal("coin 1")
	_player.collect(&"coin", 2)
	_player.collect(&"gem", 1)
	assert_str(counter.label.text).is_equal("coin 3   gem 1")


func test_health_shows_a_number_and_a_bar_and_follows_the_signal() -> void:
	var subject := HudSubject.new()
	var part := _fed_part(HEALTH, &"BottomLeft", subject)
	assert_bool(part.visible).is_false()
	subject.set_health(80.0)
	assert_bool(part.visible).is_true()
	assert_str(part.value_label.text).is_equal("80 / 100")
	assert_float(part.bar.value).is_equal(80.0)
	assert_float(part.bar.max_value).is_equal(100.0)
	subject.set_health(20.0)
	assert_str(part.value_label.text).is_equal("20 / 100")
	assert_object(part.bar.self_modulate).is_equal(part.low_color)
	subject.set_health(60.0)
	assert_object(part.bar.self_modulate).is_equal(Color.WHITE)


func test_a_part_whose_data_goes_away_hides_again() -> void:
	var subject := HudSubject.new()
	var part := _fed_part(HEALTH, &"BottomLeft", subject)
	subject.set_health(50.0)
	assert_bool(part.visible).is_true()
	subject.health = null
	subject.took_hit.emit(10.0, null)
	assert_bool(part.visible).is_false()


func test_health_without_a_largest_number_is_a_plain_number() -> void:
	var subject := HudSubject.new()
	var part := _fed_part(HEALTH, &"BottomLeft", subject)
	subject.health = 7.0
	subject.took_hit.emit(1.0, null)
	assert_bool(part.visible).is_true()
	assert_str(part.value_label.text).is_equal("7")
	assert_bool(part.bar.visible).is_false()


func test_ammo_reads_the_weapon_and_follows_a_swapped_weapon() -> void:
	var subject := HudSubject.new()
	var part := _fed_part(AMMO, &"BottomRight", subject)
	assert_bool(part.visible).is_false()
	var first := HudSubjectWeapon.new()
	subject.add_child(first)
	subject.weapon = first
	first.set_ammo(9)
	# Nobody told the part that the weapon arrived; any signal of the player makes it look again.
	assert_bool(part.visible).is_false()
	subject.died.emit()
	assert_str(part.value_label.text).is_equal("9 / 12")
	first.set_ammo(8)
	assert_str(part.value_label.text).is_equal("8 / 12")
	var second := HudSubjectWeapon.new()
	subject.add_child(second)
	subject.weapon = second
	second.set_ammo(30, 30)
	subject.revived.emit()
	assert_str(part.value_label.text).is_equal("30 / 30")
	first.set_ammo(1)
	assert_str(part.value_label.text).is_equal("30 / 30")


func test_a_part_looks_for_another_player_when_told_one() -> void:
	var part := (load(HEALTH) as PackedScene).instantiate() as HudStat
	_hud.add_widget(part, &"BottomLeft")
	# It bound to the real player.
	assert_object(part.bound_to()).is_same(_player)
	var subject := HudSubject.new()
	add_child(auto_free(subject))
	subject.set_health(40.0)
	part.player = subject
	assert_object(part.bound_to()).is_same(subject)
	assert_str(part.value_label.text).is_equal("40 / 100")


func test_a_part_lets_go_of_a_player_that_leaves() -> void:
	var subject := HudSubject.new()
	var part := _fed_part(HEALTH, &"BottomLeft", subject)
	subject.set_health(40.0)
	assert_bool(part.visible).is_true()
	subject.get_parent().remove_child(subject)
	assert_object(part.bound_to()).is_null()
	assert_bool(part.visible).is_false()
	assert_int(subject.health_changed.get_connections().size()).is_equal(0)


func test_the_hud_survives_a_death_and_a_revive() -> void:
	var counter: ItemCounter = _region(&"TopLeft").get_node("ItemCounter")
	var crosshair: Crosshair = _hud.root.get_node("Center/Crosshair")
	_player.collect(&"coin", 2)
	_player.die()
	await InputSim.ticks(get_tree(), 10)
	assert_bool(counter.visible).is_true()
	assert_str(counter.label.text).is_equal("coin 2")
	assert_bool(crosshair.visible).is_false()
	_player.revive()
	await InputSim.ticks(get_tree(), 10)
	_player.collect(&"coin", 1)
	assert_str(counter.label.text).is_equal("coin 3")
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 6)
	assert_bool(crosshair.visible).is_true()
	assert_object(counter.bound_to()).is_same(_player)


func test_the_hud_survives_a_model_swap() -> void:
	var counter: ItemCounter = _region(&"TopLeft").get_node("ItemCounter")
	var slot := _player.model
	var old := slot.rig()
	slot.remove_child(old)
	old.free()
	var male := load(CharacterBodies.MALE) as PackedScene
	var added := male.instantiate() as Node3D
	added.name = "MannequinMale"
	slot.add_child(added)
	added.owner = _player
	await get_tree().process_frame
	await get_tree().process_frame
	_player.collect(&"coin", 1)
	assert_str(counter.label.text).is_equal("coin 1")
	assert_object(counter.bound_to()).is_same(_player)


func test_one_theme_styles_every_part() -> void:
	assert_object(_hud.theme).is_same(load(THEME))
	assert_object(_hud.root.theme).is_same(_hud.theme)
	for widget in _hud.widgets():
		assert_object(widget.theme).is_null()
	var health: HudStat = _region(&"BottomLeft").get_node("HudHealth")
	var was_size := health.value_label.get_theme_font_size(&"font_size")
	var other := (load(THEME) as Theme).duplicate() as Theme
	other.set_font_size(&"font_size", &"HudNumber", was_size + 10)
	_hud.theme = other
	assert_int(health.value_label.get_theme_font_size(&"font_size")).is_equal(was_size + 10)


func test_every_export_of_the_hud_and_a_stat_has_its_default_pinned() -> void:
	var health := auto_free((load(HEALTH) as PackedScene).instantiate()) as HudStat
	var pins := {
		&"player": null,
		&"hide_without_data": true,
		&"touch_region": "TopLeft",
		&"source": HudStat.Source.PLAYER,
		&"value_property": &"health",
		&"max_property": &"max_health",
		&"extra_property": &"",
		&"refresh_signals": null,
		&"title": "Health",
		&"show_title": true,
		&"show_bar": true,
		&"value_format": "{value}",
		&"max_format": "{value} / {max}",
		&"extra_format": "",
		&"low_share": 0.25,
		&"low_color": Color(1.0, 0.4, 0.35, 1.0),
		&"title_label": null,
		&"value_label": null,
		&"bar": null,
	}
	assert_array(ExportPins.differences(health, pins)).is_empty()
	var values := pins.duplicate()
	for node_key in [&"player", &"refresh_signals", &"title_label", &"value_label", &"bar"]:
		values.erase(node_key)
	assert_array(ExportPins.wrong_values(health, values)).is_empty()
	assert_array(health.refresh_signals).contains_exactly(
		[&"health_changed", &"took_hit", &"died", &"revived"]
	)
	var fresh := auto_free((load("res://ui/hud/hud.tscn") as PackedScene).instantiate()) as Hud
	var hud_pins := {
		&"theme": null,
		&"margin": 32.0,
		&"min_text_size": 14.0,
		&"max_scale": 3.0,
		&"pixel_ratio": 0.0,
		&"touch_controls": null,
		&"player": null,
		&"root": null,
		&"safe_area": null,
		&"minimap_slot": null,
	}
	assert_array(ExportPins.differences(fresh, hud_pins)).is_empty()
	assert_float(fresh.margin).is_equal(32.0)
	assert_float(fresh.min_text_size).is_equal(14.0)


func test_the_minimap_slot_shows_while_something_is_in_it() -> void:
	for child in _hud.minimap_slot.get_children():
		child.free()
	assert_bool(_hud.minimap_slot.visible).is_false()
	var map := Control.new()
	_hud.minimap_slot.add_child(map)
	assert_bool(_hud.minimap_slot.visible).is_true()
	map.custom_minimum_size = Vector2(120.0, 120.0)
	await get_tree().process_frame
	assert_float(_hud.minimap_slot.size.x).is_equal(120.0)
	map.free()
	assert_bool(_hud.minimap_slot.visible).is_false()
