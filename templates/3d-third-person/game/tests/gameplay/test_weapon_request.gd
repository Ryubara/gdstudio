# A weapon chosen on a screen reaches the hands through the weapon presses a player makes: the
# player's input presses next, previous or the empty hands one tick at a time until the loadout is
# heading for the slot, with the keys turned off as they are while a menu is up, and a weapon added
# to the loadout is reached too. The command never carries anything but those presses.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _input: PlayerInput
var _rifle: WeaponDef
var _launcher: WeaponDef


func before_test() -> void:
	InputSim.release_all()
	_rifle = _definition("Test rifle", 30)
	_launcher = _definition("Test launcher", 1)
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	# A loadout of three weapons and the fists, set before the player is in the tree, as a
	# pickup that adds a weapon would leave it.
	var player := load("res://gameplay/player/player.tscn").instantiate() as Player
	player.start_at_spawn = false
	var slots: Array[Resource] = [player.loadout.slots[0], _rifle, _launcher]
	player.loadout.slots = slots
	_arena.add_child(player)
	_arena.player = player
	_player = player
	_input = _player.controller as PlayerInput
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _definition(title: String, magazine: int) -> WeaponDef:
	var definition := WeaponDef.new()
	definition.display_name = title
	definition.kind = WeaponDef.Kind.HITSCAN
	definition.magazine_size = magazine
	definition.start_reserve = magazine
	definition.holster_time = 0.1
	definition.draw_time = 0.1
	return definition


# Waits until the loadout is ready with nothing more asked, or the limit passes.
func _settle_switch(limit := 120) -> void:
	for _tick in limit:
		await InputSim.ticks(get_tree(), 1)
		if _input.weapon_request() == PlayerInput.NO_REQUEST and not _player.loadout.is_switching():
			return


func test_the_chooser_takes_the_shorter_way_round_and_the_empty_hands_by_their_press() -> void:
	var loadout := _player.loadout
	assert_array(WeaponChooser.round_of(loadout)).is_equal([0, 1, 2, WeaponLoadout.UNARMED])
	assert_int(WeaponChooser.press_toward(loadout, 1)).is_equal(WeaponChooser.NEXT)
	assert_int(WeaponChooser.press_toward(loadout, 2)).is_equal(WeaponChooser.NEXT)
	assert_int(WeaponChooser.press_toward(loadout, WeaponLoadout.UNARMED)).is_equal(
		WeaponChooser.UNARMED
	)
	assert_int(WeaponChooser.press_toward(loadout, 0)).is_equal(WeaponChooser.NONE)
	assert_int(WeaponChooser.press_toward(loadout, 7)).is_equal(WeaponChooser.NONE)


func test_a_requested_weapon_comes_up_through_the_weapon_presses() -> void:
	var presses := []
	_player.loadout.switch_started.connect(func(d: WeaponDef) -> void: presses.append(d))
	_input.request_weapon(2)
	await _settle_switch()
	assert_int(_player.loadout.held_slot()).is_equal(2)
	assert_object(_player.weapon.definition).is_same(_launcher)
	# Two presses of next: the switch went past the rifle on its way to the launcher.
	assert_array(presses).is_equal([_rifle, _launcher])


func test_the_last_slot_is_reached_backwards_and_the_empty_hands_directly() -> void:
	_input.request_weapon(WeaponLoadout.UNARMED)
	await _settle_switch()
	assert_int(_player.loadout.held_slot()).is_equal(WeaponLoadout.UNARMED)
	# From the empty hands the launcher is one step back.
	var presses := []
	_player.loadout.switch_started.connect(func(d: WeaponDef) -> void: presses.append(d))
	_input.request_weapon(2)
	await _settle_switch()
	assert_int(_player.loadout.held_slot()).is_equal(2)
	assert_array(presses).is_equal([_launcher])


func test_a_request_works_while_the_keys_are_off_and_a_command_has_no_other_press() -> void:
	_player.input_enabled = false
	_input.request_weapon(1)
	var command := _input.sample()
	assert_bool(command.next_weapon_pressed).is_true()
	assert_bool(command.previous_weapon_pressed).is_false()
	assert_bool(command.unarmed_pressed).is_false()
	assert_bool(command.reload_pressed).is_false()
	assert_bool(command.fire_pressed).is_false()
	await _settle_switch()
	assert_int(_player.loadout.held_slot()).is_equal(1)
	_player.input_enabled = true


func test_a_slot_that_cannot_be_reached_ends_the_request_at_once() -> void:
	_input.request_weapon(9)
	await InputSim.ticks(get_tree(), 2)
	assert_int(_input.weapon_request()).is_equal(PlayerInput.NO_REQUEST)
	assert_int(_player.loadout.held_slot()).is_equal(0)
