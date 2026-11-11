# The inventory screen's hotbar row (gdstudio #1148), through the real input path: the row shows
# the player's `Hotbar` with the bandage on place 3, a bag slot dragged onto a place is assigned
# there, a hotbar key pressed on a bag slot assigns it and a press on a filled place takes it off.
extends GdUnitTestSuite

const HOST_SCENE := preload("res://ui/menus/screen_host.tscn")
const INVENTORY := preload("res://ui/inventory/inventory_screen.tscn")
const BAG_BUTTON := preload("res://ui/menus/pause_button.tscn")
# The parts the player sees around the details text: none may move while the hovered slot changes.
const STEADY_PARTS: Array[NodePath] = [
	^"Fit/Margin/Center/Card",
	^"%Title",
	^"%Preview",
	^"%CloseButton",
	^"%Weapons",
	^"%Scroll",
	^"%DetailName",
	^"%DetailText",
	^"%DropButton",
]

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
	var slots: Array[Resource] = [player.loadout.slots[0], _rifle]
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


func _bag() -> Inventory:
	return _player.inventory


func test_the_hotbar_row_shows_the_players_hotbar_with_the_bandage_on_3() -> void:
	var screen := await _open()
	var cells := screen.hotbar_cells()
	assert_int(cells.size()).is_equal(Hotbar.of(_player).place_count)
	assert_bool(cells[0].filled).is_true()
	assert_str(cells[0].count_text()).is_equal("3")
	assert_bool(cells[1].filled).is_false()
	assert_str(cells[1].tooltip_text).is_empty()


func test_a_bag_slot_dragged_onto_a_hotbar_place_is_assigned_there() -> void:
	var coin := _bag().find_in_catalog(&"coin")
	_bag().add(coin, 4)
	var coin_slot := _bag().find(coin)
	var screen := await _open()
	var from := screen.item_cells()[coin_slot]
	var onto := screen.hotbar_cells()[2]
	assert_bool(onto._can_drop_data(Vector2.ZERO, from)).is_true()
	# A weapon or an empty bag slot is not taken.
	assert_bool(onto._can_drop_data(Vector2.ZERO, screen.weapon_cells()[0])).is_false()
	assert_bool(onto._can_drop_data(Vector2.ZERO, screen.item_cells()[15])).is_false()
	onto._drop_data(Vector2.ZERO, from)
	assert_object(Hotbar.of(_player).item_at(2)).is_same(coin)
	assert_str(screen.hotbar_cells()[2].count_text()).is_equal("4")
	# The bag is untouched.
	assert_int(_bag().count_at(coin_slot)).is_equal(4)


func test_a_hotbar_key_on_a_bag_slot_assigns_it_and_a_press_takes_it_off() -> void:
	var screen := await _open()
	var bar := Hotbar.of(_player)
	await _tap_key(KEY_DOWN)
	await _tap_key(KEY_DOWN)
	assert_object(_focus()).is_same(screen.item_cells()[0])
	await _tap_key(KEY_5)
	assert_object(bar.item_at(2)).is_same(_bag().item_at(0))
	assert_object(bar.item_at(0)).is_null()
	assert_bool(_host.is_open()).is_true()
	# The game behind it used nothing.
	assert_int(_bag().count_at(0)).is_equal(3)
	await _click(screen.hotbar_cells()[2])
	assert_object(bar.item_at(2)).is_null()
	# Picked up, then pressed on a place, it goes there.
	await _click(screen.item_cells()[0])
	assert_int(screen.picked()).is_equal(0)
	await _click(screen.hotbar_cells()[1])
	assert_object(bar.item_at(1)).is_same(_bag().item_at(0))
	assert_int(screen.picked()).is_equal(-1)
