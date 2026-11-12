# The HUD's weapon slots and hotbar in the game, through the real input path: the slots show the
# loadout's round (the pistol on 1, the fists on 2) with the one in hand lit, keys 1 and 2 take a
# slot in hand, the lit slot follows a switch made by the wheel, the H key or the inventory's
# request, the hotbar shows the bandage on 3 with the bag's count and the other places their keys
# alone, key 3 uses a bandage on a hurt player and is refused at full health, a hotbar setting of
# six places shows six, and on a touch screen a finger on a place does what its key does.
extends GdUnitTestSuite

var _scene: Node
var _hud: Hud
var _player: Player
var _slots: HudWeaponSlots
var _hotbar: HudHotbar
var _window_size: Vector2i


func before_test() -> void:
	InputSim.release_all()
	_window_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	_scene = scene_runner("res://main.tscn").scene()
	_hud = _scene.get_node("Hud")
	_player = _scene.get_node("PlayerRig/Player")
	_slots = _hud.region(&"BottomRight").get_node("HudWeaponSlots")
	_hotbar = _hud.region(&"BottomCenter").get_node("HudHotbar")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	get_tree().root.size = _window_size
	AudioDrain.stop_all(_scene)


func _tap_key(code: Key) -> void:
	InputSim.key(code, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(code, false)
	await InputSim.ticks(get_tree(), 2)


# Waits until the loadout's switch is over (the pistol's and the fists' times are well under 1 s).
func _wait_for_the_switch() -> void:
	for _tick in 120:
		if not _player.loadout.is_switching():
			return
		await get_tree().physics_frame


func _keys(row: HudSlotRow) -> Array[String]:
	var found: Array[String] = []
	for cell in row.cells():
		found.append(cell.key_text())
	return found


func test_the_weapon_slots_show_the_pistol_lit_on_1_and_the_fists_on_2() -> void:
	assert_bool(_slots.visible).is_true()
	assert_array(_keys(_slots)).is_equal(["1", "2"] as Array[String])
	var cells := _slots.cells()
	assert_object(cells[0].picture()).is_same((_player.loadout.slots[0] as WeaponDef).icon)
	assert_object(cells[1].picture()).is_same(_player.loadout.unarmed.icon)
	assert_int(cells[0].state).is_equal(HudSlot.State.LIT)
	assert_int(cells[1].state).is_equal(HudSlot.State.IDLE)
	assert_str(String(cells[0].theme_type_variation)).is_equal("HudSlotLit")
	# No rounds here: the ammo card is their one home.
	assert_str(cells[0].count_text()).is_empty()


func test_keys_1_and_2_take_a_slot_in_hand_and_the_lit_slot_follows() -> void:
	var rest_rect := _slots.cells()[0].get_global_rect()
	await _tap_key(KEY_2)
	await _wait_for_the_switch()
	assert_int(_player.loadout.held_slot()).is_equal(WeaponLoadout.UNARMED)
	assert_int(_slots.lit_place()).is_equal(1)
	# The ammo card leaves for the fists and the slots stay where they were.
	await get_tree().process_frame
	assert_bool(_hud.region(&"BottomRight").get_node("HudAmmo").visible).is_false()
	assert_vector(_slots.cells()[0].get_global_rect().position).is_equal_approx(
		rest_rect.position, Vector2.ONE * 0.5
	)
	# The slot in hand does nothing.
	await _tap_key(KEY_2)
	assert_bool(_player.loadout.is_switching()).is_false()
	await _tap_key(KEY_1)
	await _wait_for_the_switch()
	assert_int(_player.loadout.held_slot()).is_equal(0)
	assert_int(_slots.lit_place()).is_equal(0)


func test_the_lit_slot_follows_a_switch_made_any_other_way() -> void:
	await _tap_key(KEY_H)
	await _wait_for_the_switch()
	assert_int(_slots.lit_place()).is_equal(1)
	InputSim.mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	InputSim.mouse_button(MOUSE_BUTTON_WHEEL_DOWN, false)
	await InputSim.ticks(get_tree(), 2)
	await _wait_for_the_switch()
	assert_int(_player.loadout.held_slot()).is_equal(0)
	assert_int(_slots.lit_place()).is_equal(0)
	# A screen's request lights the slot it asks for at once.
	(_player.controller as PlayerInput).request_weapon(WeaponLoadout.UNARMED)
	_slots.update()
	assert_int(_slots.lit_place()).is_equal(1)
	await _wait_for_the_switch()
	await InputSim.ticks(get_tree(), 2)
	await _wait_for_the_switch()
	assert_int(_player.loadout.held_slot()).is_equal(WeaponLoadout.UNARMED)


func test_a_weapon_added_to_the_loadout_takes_slot_2_and_the_fists_leave_the_row() -> void:
	var rifle := WeaponDef.new()
	rifle.display_name = "Test rifle"
	var slots: Array[Resource] = [_player.loadout.slots[0], rifle]
	_player.loadout.slots = slots
	_player.loadout._kept.append([0, 0])
	_slots.update()
	assert_int(_slots.slot_at(1)).is_equal(1)
	assert_int(_slots.cells()[1].state).is_equal(HudSlot.State.IDLE)
	await _tap_key(KEY_2)
	await _wait_for_the_switch()
	assert_int(_player.loadout.held_slot()).is_equal(1)
	assert_int(_slots.lit_place()).is_equal(1)


func test_the_hotbar_shows_the_bandage_on_3_and_the_other_places_their_keys_alone() -> void:
	assert_bool(_hotbar.visible).is_true()
	assert_array(_keys(_hotbar)).is_equal(["3", "4", "5", "6"] as Array[String])
	var cells := _hotbar.cells()
	assert_object(cells[0].picture()).is_same(_player.inventory.find_in_catalog(&"bandage").icon)
	assert_str(cells[0].count_text()).is_equal("3")
	assert_int(cells[0].state).is_equal(HudSlot.State.IDLE)
	for place in range(1, 4):
		assert_int(cells[place].state).is_equal(HudSlot.State.EMPTY)
		assert_object(cells[place].picture()).is_null()
		assert_str(cells[place].count_text()).is_empty()


func test_key_3_uses_a_bandage_on_a_hurt_player_and_is_refused_at_full_health() -> void:
	var health := Health.of(_player)
	await _tap_key(KEY_3)
	assert_int(_player.inventory.count_of_id(&"bandage")).is_equal(3)
	health.value = 50.0
	await _tap_key(KEY_3)
	assert_float(health.value).is_equal(75.0)
	assert_int(_player.inventory.count_of_id(&"bandage")).is_equal(2)
	assert_str(_hotbar.cells()[0].count_text()).is_equal("2")
	# An empty place's key does nothing.
	await _tap_key(KEY_4)
	assert_float(health.value).is_equal(75.0)


func test_the_last_bandage_leaves_the_place_dim_with_0() -> void:
	var health := Health.of(_player)
	health.value = 1.0
	for _use in 3:
		await _tap_key(KEY_3)
	assert_int(_player.inventory.count_of_id(&"bandage")).is_equal(0)
	assert_int(_hotbar.cells()[0].state).is_equal(HudSlot.State.SPENT)
	assert_str(_hotbar.cells()[0].count_text()).is_equal("0")


func test_the_places_keys_do_nothing_while_the_input_is_off() -> void:
	Health.of(_player).value = 50.0
	_player.input_enabled = false
	await _tap_key(KEY_3)
	await _tap_key(KEY_2)
	_player.input_enabled = true
	await InputSim.ticks(get_tree(), 2)
	assert_int(_player.inventory.count_of_id(&"bandage")).is_equal(3)
	assert_bool(_player.loadout.is_switching()).is_false()
	assert_int(_player.loadout.held_slot()).is_equal(0)


func test_the_hotbar_shows_as_many_places_as_the_players_hotbar_has() -> void:
	var data := Hotbar.of(_player)
	data.place_count = 6
	assert_int(_hotbar.cells().size()).is_equal(6)
	# Places past the project's actions show their number and take no finger.
	assert_str(_hotbar.cells()[5].key_text()).is_equal("8")
	assert_int(_hotbar.touch_zones().size()).is_equal(4)
	data.place_count = 2
	assert_int(_hotbar.cells().size()).is_equal(2)


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var touch: TouchControls = _scene.get_node("PlayerRig/TouchControls")
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	touch._input(event)


func test_a_finger_on_a_place_does_what_its_key_does() -> void:
	var touch: TouchControls = _scene.get_node("PlayerRig/TouchControls")
	touch.show_mode = TouchControls.ShowMode.ALWAYS
	touch._set_shown(true)
	get_tree().root.size = Vector2i(844, 390)
	await InputSim.ticks(get_tree(), 3)
	Health.of(_player).value = 40.0
	var zones := _hud.touch_zones()
	assert_int(zones.size()).is_equal(2 + 4)
	var bandage_place: Rect2 = _hotbar.touch_zones()[0]["rect"]
	assert_str(String(touch.zone_action_at(bandage_place.get_center()))).is_equal("hotbar_1")
	# A second finger on the stick at the same time does its own job.
	_touch(1, touch.stick_home(), true)
	_touch(2, bandage_place.get_center(), true)
	await InputSim.ticks(get_tree(), 2)
	_touch(2, bandage_place.get_center(), false)
	await InputSim.ticks(get_tree(), 2)
	assert_float(Health.of(_player).value).is_equal(65.0)
	assert_int(_player.inventory.count_of_id(&"bandage")).is_equal(2)
	var fists_place: Rect2 = _slots.touch_zones()[1]["rect"]
	_touch(3, fists_place.get_center(), true)
	await InputSim.ticks(get_tree(), 2)
	_touch(3, fists_place.get_center(), false)
	await _wait_for_the_switch()
	assert_int(_player.loadout.held_slot()).is_equal(WeaponLoadout.UNARMED)
	assert_int(_slots.lit_place()).is_equal(1)
	_touch(1, touch.stick_home(), false)
	# A finger on a place never turns the view or moves the stick.
	assert_vector(touch.stick_vector()).is_equal(Vector2.ZERO)


func test_an_online_client_shows_the_hotbar_but_never_uses_it_itself() -> void:
	var holder := auto_free(Node3D.new()) as Node3D
	add_child(holder)
	var player := load("res://gameplay/player/player.tscn").instantiate() as Player
	player.start_at_spawn = false
	var client := NetClient.new()
	client.join_on_ready = false
	client.player = player
	holder.add_child(player)
	holder.add_child(client)
	await InputSim.ticks(get_tree(), 2)
	var bar := Hotbar.of(player)
	assert_bool(bar.authoritative).is_false()
	Health.of(player).value = 30.0
	assert_bool(bar.use(0)).is_false()
	assert_float(Health.of(player).value).is_equal(30.0)
	assert_int(bar.count_at(0)).is_equal(3)


func test_every_export_of_the_rows_and_the_place_has_its_default_pinned() -> void:
	var cell_scene := load("res://ui/hud/hud_slot.tscn")
	var rows := {
		_slots:
		{
			&"action_format": "weapon_%d",
			&"first_key_number": 1,
			&"cell_scene": cell_scene,
			&"place_count": 2,
			&"touch_region": "BottomLeft",
		},
		_hotbar:
		{
			&"action_format": "hotbar_%d",
			&"first_key_number": 3,
			&"cell_scene": cell_scene,
			&"editor_places": 4,
			&"flash_time": 0.3,
			&"flash_scale": 1.15,
			&"touch_region": "TopLeft",
		},
	}
	for row: HudSlotRow in rows:
		var pins: Dictionary = rows[row]
		for pinned: StringName in pins:
			assert_array(ExportPins.names(row)).contains([pinned])
		assert_array(ExportPins.wrong_values(row, pins)).is_empty()
	var cell := _slots.cells()[0]
	var cell_pins := {
		&"panel_variations": [&"HudSlotEmpty", &"HudSlot", &"HudSlotLit", &"HudSlotEmpty"],
		&"key_variation_lit": &"HudSlotKeyLit",
		&"key_variation": &"HudSlotKey",
		&"spent_alpha": 0.35,
	}
	assert_array(ExportPins.wrong_values(cell, cell_pins)).is_empty()
	assert_vector(cell.custom_minimum_size).is_equal(Vector2(84, 84))
