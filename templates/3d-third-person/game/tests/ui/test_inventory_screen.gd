# The inventory screen over a player in a small world, through the real input path: the `inventory`
# key (I) and the pad's right shoulder open it on the host and close it, the weapons are the
# loadout's (a second weapon of the test's own shows), a weapon chosen with the pad comes up once
# the game runs again, the d-pad and the arrows reach every slot, a stack is picked up and put down
# with keys and with mouse clicks, Drop leaves a pickup in front of the player and refuses a coin,
# the player's option keeps the game running with the player's own keys off, and the preview draws
# the live model and follows a mesh dropped into the model slot.
extends GdUnitTestSuite

const HOST_SCENE := preload("res://ui/menus/screen_host.tscn")
const INVENTORY := preload("res://ui/inventory/inventory_screen.tscn")
const BAG_BUTTON := preload("res://ui/menus/pause_button.tscn")

var _arena: PlayArena
var _player: Player
var _rifle: WeaponDef
var _host: ScreenHost
var _mode := Input.MOUSE_MODE_CAPTURED
var _window_size := Vector2i.ZERO


func before_test() -> void:
	InputSim.release_all()
	_window_size = get_window().size
	get_window().size = Vector2i(1920, 1080)
	UIMotion.reduced = true
	Settings.reset_defaults()
	_rifle = WeaponDef.new()
	_rifle.display_name = "Test rifle"
	_rifle.kind = WeaponDef.Kind.HITSCAN
	_rifle.magazine_size = 30
	_rifle.start_reserve = 60
	_rifle.holster_time = 0.1
	_rifle.draw_time = 0.1
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	var player := load("res://gameplay/player/player.tscn").instantiate() as Player
	player.start_at_spawn = false
	var slots: Array[WeaponDef] = [player.loadout.slots[0], _rifle]
	player.loadout.slots = slots
	_arena.add_child(player)
	_arena.player = player
	_player = player
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.3, 4.0)
	_arena.add_child(camera)
	camera.make_current()
	_host = HOST_SCENE.instantiate() as ScreenHost
	_host.pause_on_focus_loss = false
	_host.transition = UITransition.Kind.CUT
	_host.mouse_mode_reader = func() -> Input.MouseMode: return _mode
	_host.mouse_mode_writer = func(mode: Input.MouseMode) -> void: _mode = mode
	add_child(_host)
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	get_tree().paused = false
	await MenuFixture.clear(get_tree())
	if is_instance_valid(_host):
		_host.free()
	AudioDrain.stop_all(_arena)
	Settings.reset_defaults()
	UIMotion.reduced = false
	get_window().size = _window_size
	await get_tree().process_frame


func _settle() -> void:
	assert_bool(await MenuFixture.settle(get_tree())).is_true()


func _tap_key(code: Key) -> void:
	InputSim.key(code, true)
	InputSim.key(code, false)
	await get_tree().process_frame
	await get_tree().process_frame


func _tap_pad(button: JoyButton) -> void:
	InputSim.pad_button(button, true)
	InputSim.pad_button(button, false)
	await get_tree().process_frame
	await get_tree().process_frame


func _open() -> InventoryScreen:
	await _tap_key(KEY_I)
	await _settle()
	var screen := UIRouter.top() as InventoryScreen
	assert_object(screen).is_not_null()
	return screen


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _click(control: Control) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size / 2.0)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await get_tree().process_frame


func _tap(control: Control) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size / 2.0)
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = pressed
		touch.position = at
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await get_tree().process_frame


func _bag() -> Inventory:
	return _player.inventory


func test_every_export_has_its_default_pinned() -> void:
	var screen := auto_free(INVENTORY.instantiate()) as InventoryScreen
	var pins := {
		&"player": null,
		&"cell_scene": load("res://ui/inventory/inventory_cell.tscn"),
		&"pause_setting": &"controls/pause_in_inventory",
		&"pauses_by_default": true,
		&"stop_player_input": true,
	}
	for pinned: StringName in pins:
		assert_array(ExportPins.names(screen)).contains([pinned])
	assert_array(ExportPins.wrong_values(screen, pins)).is_empty()
	var preview := (
		auto_free(load("res://ui/inventory/model_preview.tscn").instantiate()) as ModelPreview
	)
	var preview_pins := {
		&"model_slot": null,
		&"preview_layer": 20,
		&"distance": 3.2,
		&"camera_height": 1.15,
		&"look_height": 0.95,
		&"field_of_view": 34.0,
		&"start_angle": -25.0,
		&"drag_turn": 0.45,
		&"stick_turn": 160.0,
		&"max_height": 1440,
		&"msaa": Viewport.MSAA_4X,
	}
	assert_array(ExportPins.differences(preview, preview_pins)).is_empty()
	assert_array(ExportPins.wrong_values(preview, preview_pins)).is_empty()
	# The player's bag: sixteen slots, three bandages, the coin and the bandage in its catalog.
	assert_int(_bag().slot_count).is_equal(16)
	assert_int(_bag().count_of_id(&"bandage")).is_equal(3)
	(
		assert_array(_bag().catalog.map(func(i: ItemDef) -> StringName: return i.id))
		. is_equal([&"coin", &"bandage"])
	)


func test_the_inventory_key_and_the_pads_shoulder_open_and_close_it_over_a_paused_game() -> void:
	var screen := await _open()
	assert_bool(_host.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_object(screen.player).is_same(_player)
	await _tap_key(KEY_I)
	await _settle()
	assert_bool(_host.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	await _tap_pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _settle()
	assert_object(UIRouter.top()).is_instanceof(InventoryScreen)
	# Back (Esc, a pad's B) closes it too.
	await _tap_pad(JOY_BUTTON_B)
	await _settle()
	assert_bool(_host.is_open()).is_false()


func test_the_weapons_are_the_loadouts_with_the_one_in_the_hands_marked() -> void:
	var screen := await _open()
	var cells := screen.weapon_cells()
	(
		assert_array(cells.map(func(c: InventoryCell) -> int: return c.slot))
		. is_equal([0, 1, WeaponLoadout.UNARMED])
	)
	(
		assert_array(cells.map(func(c: InventoryCell) -> String: return c.tooltip_text))
		. is_equal(["Pistol", "Test rifle", "Fists"])
	)
	assert_bool(cells[0].is_equipped()).is_true()
	assert_bool(cells[1].is_equipped()).is_false()
	assert_str(cells[0].count_text()).is_equal("12/36")
	assert_str(cells[1].count_text()).is_equal("30/60")
	assert_str(cells[2].count_text()).is_empty()


func test_a_weapon_chosen_with_the_pad_comes_up_when_the_game_runs_again() -> void:
	var screen := await _open()
	assert_object(_focus()).is_same(screen.weapon_cells()[0])
	await _tap_pad(JOY_BUTTON_DPAD_RIGHT)
	assert_object(_focus()).is_same(screen.weapon_cells()[1])
	await _tap_pad(JOY_BUTTON_A)
	assert_bool(screen.weapon_cells()[1].is_equipped()).is_true()
	assert_bool(screen.weapon_cells()[0].is_equipped()).is_false()
	# Paused: nothing has moved yet.
	await InputSim.ticks(get_tree(), 10)
	assert_int(_player.loadout.held_slot()).is_equal(0)
	await _tap_key(KEY_I)
	await _settle()
	for _tick in 60:
		await InputSim.ticks(get_tree(), 1)
		if _player.loadout.held_slot() == 1 and not _player.loadout.is_switching():
			break
	assert_int(_player.loadout.held_slot()).is_equal(1)
	assert_object(_player.weapon.definition).is_same(_rifle)


func test_the_arrows_and_the_dpad_reach_every_slot_and_both_buttons() -> void:
	var screen := await _open()
	await get_tree().process_frame
	var start := _focus()
	assert_object(start).is_same(screen.weapon_cells()[0])
	var all := MenuFixture.focusables(screen)
	var cells: Array[Control] = []
	cells.append_array(screen.weapon_cells())
	cells.append_array(screen.item_cells())
	assert_int(cells.size()).is_equal(3 + 16)
	var reached := MenuFixture.reachable(start)
	for control in all:
		assert_bool(control in reached).override_failure_message(str(control.name)).is_true()
		(
			assert_bool(start in MenuFixture.reachable(control))
			. override_failure_message("no way back from %s" % control.name)
			. is_true()
		)
	for cell in cells:
		assert_bool(cell in reached).override_failure_message(str(cell.name)).is_true()
	# The real presses walk the same road: down to the bag, right along it, down its rows.
	await _tap_pad(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(screen.item_cells()[0])
	await _tap_key(KEY_RIGHT)
	assert_object(_focus()).is_same(screen.item_cells()[1])
	for row in 3:
		await _tap_pad(JOY_BUTTON_DPAD_DOWN)
		assert_object(_focus()).is_same(screen.item_cells()[1 + 4 * (row + 1)])
	await _tap_key(KEY_LEFT)
	await _tap_key(KEY_LEFT)
	assert_str(_focus().name).is_equal("CloseButton")


func test_a_stack_is_picked_up_and_put_down_with_the_keys() -> void:
	var screen := await _open()
	await _tap_key(KEY_DOWN)
	assert_object(_focus()).is_same(screen.item_cells()[0])
	await _tap_key(KEY_ENTER)
	assert_int(screen.picked()).is_equal(0)
	assert_bool(screen.item_cells()[0].is_held()).is_true()
	await _tap_key(KEY_RIGHT)
	await _tap_key(KEY_DOWN)
	assert_object(_focus()).is_same(screen.item_cells()[5])
	await _tap_key(KEY_ENTER)
	assert_int(screen.picked()).is_equal(-1)
	assert_bool(_bag().is_empty(0)).is_true()
	assert_int(_bag().count_at(5)).is_equal(3)
	assert_str(screen.item_cells()[5].count_text()).is_equal("3")
	# Picked up again, Esc puts it down where it was and leaves the screen open.
	await _tap_key(KEY_ENTER)
	assert_int(screen.picked()).is_equal(5)
	await _tap_key(KEY_ESCAPE)
	assert_int(screen.picked()).is_equal(-1)
	assert_bool(_host.is_open()).is_true()
	assert_int(_bag().count_at(5)).is_equal(3)


func test_mouse_clicks_move_a_stack_onto_another_of_its_kind() -> void:
	_bag().add(_bag().find_in_catalog(&"bandage"), 3)
	assert_int(_bag().count_at(0)).is_equal(5)
	assert_int(_bag().count_at(1)).is_equal(1)
	var screen := await _open()
	_bag().remove(0, 2)
	await _click(screen.item_cells()[1])
	assert_int(screen.picked()).is_equal(1)
	await _click(screen.item_cells()[0])
	assert_int(_bag().count_at(0)).is_equal(4)
	assert_bool(_bag().is_empty(1)).is_true()


func test_a_finger_picks_a_stack_up_and_puts_it_down() -> void:
	var screen := await _open()
	# The host turns touch-to-mouse on while a screen is up: a tap is a click on the slot.
	assert_bool(Input.emulate_mouse_from_touch).is_true()
	await _tap(screen.item_cells()[0])
	assert_int(screen.picked()).is_equal(0)
	await _tap(screen.item_cells()[7])
	assert_int(_bag().count_at(7)).is_equal(3)
	assert_bool(_bag().is_empty(0)).is_true()


func test_drop_leaves_a_pickup_in_front_of_the_player_and_a_coin_cannot_be_dropped() -> void:
	_player.collect(&"coin", 4)
	assert_int(_bag().count_of_id(&"coin")).is_equal(4)
	var screen := await _open()
	var drop: Button = screen.find_child("DropButton", true, false)
	# The coin's slot shown: Drop is off.
	var coin_slot := _bag().find(_bag().find_in_catalog(&"coin"))
	screen.item_cells()[coin_slot].grab_focus()
	await get_tree().process_frame
	assert_bool(drop.disabled).is_true()
	# The bandages' slot shown: Drop takes them out and leaves one pickup worth three.
	screen.item_cells()[0].grab_focus()
	await get_tree().process_frame
	assert_bool(drop.disabled).is_false()
	drop.grab_focus()
	await _tap_key(KEY_ENTER)
	assert_int(_bag().count_of_id(&"bandage")).is_zero()
	var dropped := _arena.find_children("*", "Pickup", true, false)
	assert_int(dropped.size()).is_equal(1)
	var pickup := dropped[0] as Pickup
	assert_str(String(pickup.item_id)).is_equal("bandage")
	assert_int(pickup.amount).is_equal(3)
	var front := Vector3.BACK.rotated(Vector3.UP, _player.facing)
	var offset := pickup.global_position - _player.global_position
	assert_float(Vector2(offset.x, offset.z).dot(Vector2(front.x, front.z))).is_greater(1.2)
	# Walked over, it goes back into the bag.
	await _tap_key(KEY_I)
	await _settle()
	_player.teleport(pickup.global_position - Vector3.UP * 0.6)
	await InputSim.ticks(get_tree(), 6)
	assert_int(_bag().count_of_id(&"bandage")).is_equal(3)


func test_with_the_option_off_the_game_runs_and_the_players_keys_are_off_until_it_closes() -> void:
	Settings.set_value(SettingsService.PAUSE_IN_INVENTORY, false)
	var screen := await _open()
	assert_bool(screen.pauses_game()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_bool(_player.input_enabled).is_false()
	var at := _player.global_position
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 20)
	InputSim.key(KEY_W, false)
	assert_float(_player.global_position.distance_to(at)).is_less(0.05)
	await _tap_key(KEY_I)
	await _settle()
	assert_bool(_player.input_enabled).is_true()
	Settings.set_value(SettingsService.PAUSE_IN_INVENTORY, true)
	var paused := await _open()
	assert_bool(paused.pauses_game()).is_true()
	assert_bool(get_tree().paused).is_true()


func test_the_preview_draws_the_live_model_and_follows_a_mesh_put_in_the_slot() -> void:
	var screen := await _open()
	var preview := screen.preview()
	var bit := 1 << 19
	assert_int(preview.camera().cull_mask).is_equal(bit)
	# The camera's mask culls lights by their layers too: the preview's key light is on its layer.
	var key_light := preview.camera().get_node("KeyLight") as DirectionalLight3D
	assert_int(key_light.layers).is_equal(bit)
	assert_int(key_light.light_cull_mask).is_equal(bit)
	assert_bool(key_light.visible).is_true()
	assert_int(preview.viewport().render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)
	var meshes := _player.model.find_children("*", "MeshInstance3D", true, false)
	assert_bool(meshes.is_empty()).is_false()
	for mesh: MeshInstance3D in meshes:
		assert_int(mesh.layers & bit).override_failure_message(str(mesh.name)).is_equal(bit)
		assert_int(mesh.layers & 1).is_equal(1)
	# A model swap: a mesh dropped into the slot while the screen is up is drawn too.
	var swapped := MeshInstance3D.new()
	swapped.mesh = BoxMesh.new()
	_player.model.add_child(swapped)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(swapped.layers & bit).is_equal(bit)
	# The view turns from a drag and from the right stick.
	var angle := preview.angle
	preview.turn(30.0)
	assert_float(preview.angle).is_equal_approx(angle + 30.0, 0.001)
	InputSim.pad_axis(JOY_AXIS_RIGHT_X, 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	InputSim.pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	assert_float(preview.angle).is_greater(angle + 30.0)
	# Closed: the layer is taken off again.
	await _tap_key(KEY_I)
	await _settle()
	for mesh: MeshInstance3D in meshes:
		assert_int(mesh.layers & bit).is_zero()
	assert_int(swapped.layers & bit).is_zero()


func test_the_preview_draws_at_the_windows_pixels_under_the_phone_layout() -> void:
	var screen := await _open()
	var fit := screen.get_node("Fit") as MenuFit
	var preview := screen.preview()
	# The window is the design size: one unit is one pixel, so the viewport is the control's size.
	fit.force = 1
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(preview.viewport().size.y).is_equal(roundi(preview.size.y))
	# The phone layout draws the menu 1.75 times bigger: the viewport follows, so it is not blurred.
	fit.force = 2
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(preview.viewport().size.y).is_equal(roundi(preview.size.y * fit.phone_factor))


func test_the_bag_button_opens_the_inventory_on_a_touch_screen() -> void:
	var button := BAG_BUTTON.instantiate() as PauseButton
	button.screen = INVENTORY
	button.always_shown = true
	add_child(button)
	button.pressed.emit()
	await _settle()
	assert_object(UIRouter.top()).is_instanceof(InventoryScreen)
	button.free()
