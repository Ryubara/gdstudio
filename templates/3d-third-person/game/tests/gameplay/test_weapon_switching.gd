# Ammunition, reloading and switching through simulated input in the real physics world: the
# fire button spends the pistol's magazine, R reloads it from the reserve, H puts it away for the
# fists and brings it back with its ammunition, the mouse wheel goes to the next and the previous
# weapon, a switch cuts a reload short, a pull on an empty magazine clicks, a punch knocks a target
# down, and a box of rounds fills the reserve.
extends GdUnitTestSuite

const TARGET := "res://gameplay/target/target.tscn"
const PICKUP := "res://gameplay/pickup/pickup.tscn"

var _arena: PlayArena
var _player: Player
var _camera: Camera3D


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _weapon() -> Weapon:
	return _player.weapon


func _loadout() -> WeaponLoadout:
	return _player.loadout


func _tap_key(code: Key) -> void:
	InputSim.key(code, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(code, false)
	await InputSim.ticks(get_tree(), 1)


func _wheel(button: MouseButton) -> void:
	# A wheel notch: the press and the release in one frame, as a real wheel sends them.
	InputSim.mouse_button(button, true)
	InputSim.mouse_button(button, false)
	await InputSim.ticks(get_tree(), 2)


# One click of the left mouse button, held long enough for the arm to come up and the shot to
# leave, then the rest of the pistol's cooldown.
func _click_fire() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 12)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), 6)


func _seconds(seconds: float) -> void:
	await InputSim.ticks(get_tree(), ceili(seconds * Engine.physics_ticks_per_second) + 1)


# Waits for a whole switch: the held weapon's way down and the next one's way up.
func _switch_time() -> float:
	return 0.2 + 0.25 + 0.1


func test_the_player_starts_with_the_pistol_full_and_the_fists_in_the_loadout() -> void:
	assert_object(_loadout()).is_not_null()
	assert_str(_weapon().definition.display_name).is_equal("Pistol")
	assert_int(_loadout().held_slot()).is_equal(0)
	assert_str(_loadout().unarmed.display_name).is_equal("Fists")
	assert_int(_weapon().ammo).is_equal(12)
	assert_int(_weapon().reserve).is_equal(36)
	assert_bool((_player.model.get_node("PistolHeld") as Node3D).visible).is_true()


func test_each_click_of_fire_spends_a_round_to_the_end_of_the_magazine_and_then_it_reloads(
) -> void:
	var shots := [0]
	_weapon().fired.connect(func(_shot: Projectile) -> void: shots[0] += 1)
	for click in 12:
		await _click_fire()
		assert_int(_weapon().ammo).override_failure_message("click %d" % click).is_equal(11 - click)
	assert_int(shots[0]).is_equal(12)
	# Empty with rounds in reserve: it reloads by itself, and the rounds go in at the end.
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_weapon().is_reloading()).is_true()
	await _seconds(1.6)
	assert_int(_weapon().ammo).is_equal(12)
	assert_int(_weapon().reserve).is_equal(24)


func test_r_reloads_from_the_reserve() -> void:
	for _click in 3:
		await _click_fire()
	assert_int(_weapon().ammo).is_equal(9)
	await _tap_key(KEY_R)
	assert_bool(_weapon().is_reloading()).is_true()
	assert_bool(_player.get_node("Animation").is_reloading()).is_true()
	await _seconds(1.6)
	assert_int(_weapon().ammo).is_equal(12)
	assert_int(_weapon().reserve).is_equal(33)


func test_a_pull_on_an_empty_magazine_with_no_reserve_clicks() -> void:
	_weapon().set_ammo(0, 0)
	var clicks := [0]
	_weapon().dry_fired.connect(func() -> void: clicks[0] += 1)
	var shots := [0]
	_weapon().fired.connect(func(_shot: Projectile) -> void: shots[0] += 1)
	await _click_fire()
	assert_int(clicks[0]).is_equal(1)
	assert_int(shots[0]).is_equal(0)
	await _tap_key(KEY_R)
	assert_bool(_weapon().is_reloading()).is_false()


func test_h_puts_the_pistol_away_for_the_fists_and_brings_it_back_with_its_rounds() -> void:
	for _click in 2:
		await _click_fire()
	var changed: Array[String] = []
	_loadout().weapon_changed.connect(
		func(definition: WeaponDef) -> void: changed.append(definition.display_name)
	)
	await _tap_key(KEY_H)
	assert_bool(_loadout().is_switching()).is_true()
	# On the way down the pistol is still in the hand, and it does not fire.
	assert_str(_weapon().definition.display_name).is_equal("Pistol")
	assert_bool(_weapon().can_fire()).is_false()
	await _seconds(_switch_time())
	assert_bool(_loadout().is_switching()).is_false()
	assert_int(_loadout().held_slot()).is_equal(WeaponLoadout.UNARMED)
	assert_str(_weapon().definition.display_name).is_equal("Fists")
	assert_bool((_player.model.get_node("PistolHeld") as Node3D).visible).is_false()
	# No ammunition: the HUD's ammo has nothing to show.
	assert_object(_weapon().ammo).is_null()
	await _tap_key(KEY_H)
	await _seconds(_switch_time())
	assert_str(_weapon().definition.display_name).is_equal("Pistol")
	assert_bool((_player.model.get_node("PistolHeld") as Node3D).visible).is_true()
	assert_int(_weapon().ammo).is_equal(10)
	assert_int(_weapon().reserve).is_equal(36)
	assert_array(changed).is_equal(["Fists", "Pistol"])


func test_the_wheel_goes_to_the_next_and_the_previous_weapon() -> void:
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	assert_int(_loadout().target_slot()).is_equal(WeaponLoadout.UNARMED)
	await _seconds(_switch_time())
	assert_int(_loadout().held_slot()).is_equal(WeaponLoadout.UNARMED)
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	assert_int(_loadout().target_slot()).is_equal(0)
	await _seconds(_switch_time())
	assert_int(_loadout().held_slot()).is_equal(0)


func test_a_switch_during_a_reload_cuts_it_short_and_puts_nothing_in() -> void:
	for _click in 4:
		await _click_fire()
	await _tap_key(KEY_R)
	await _seconds(0.8)
	assert_bool(_weapon().is_reloading()).is_true()
	var cancelled := [0]
	_weapon().reload_cancelled.connect(func() -> void: cancelled[0] += 1)
	await _tap_key(KEY_H)
	assert_int(cancelled[0]).is_equal(1)
	assert_bool(_weapon().is_reloading()).is_false()
	assert_bool(_player.get_node("Animation").is_reloading()).is_false()
	await _seconds(2.0)
	await _tap_key(KEY_H)
	await _seconds(_switch_time())
	# Back to the pistol: the magazine and the reserve are as they were before the reload.
	assert_int(_weapon().ammo).is_equal(8)
	assert_int(_weapon().reserve).is_equal(36)


func test_asking_again_on_the_way_down_goes_back_up_with_the_same_weapon() -> void:
	await _tap_key(KEY_H)
	assert_bool(_loadout().is_switching()).is_true()
	await _tap_key(KEY_H)
	await _seconds(_switch_time())
	assert_int(_loadout().held_slot()).is_equal(0)
	assert_bool(_loadout().is_switching()).is_false()
	assert_bool(_weapon().can_fire()).is_true()


func test_a_punch_knocks_down_a_target_in_front() -> void:
	var target := load(TARGET).instantiate() as Target
	target.position = Vector3(0.0, 0.0, -0.9)
	_arena.add_child(target)
	await _tap_key(KEY_H)
	await _seconds(_switch_time())
	var hits: Array[Dictionary] = []
	_weapon().hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	await _click_fire()
	assert_int(hits.size()).is_equal(1)
	assert_bool(target.is_down()).is_true()


func test_a_box_of_rounds_fills_the_reserve() -> void:
	var box := load(PICKUP).instantiate() as Pickup
	box.item_id = &"pistol_ammo"
	box.amount = 20
	box.position = Vector3(0.0, 0.5, -1.5)
	_arena.add_child(box)
	InputSim.key(KEY_W, true)
	await _seconds(1.0)
	InputSim.key(KEY_W, false)
	assert_int(_weapon().reserve).is_equal(56)


func test_the_weapon_layer_lets_go_of_the_hand_for_the_fists() -> void:
	var animation := _player.get_node("Animation") as CharacterAnimation
	await InputSim.ticks(get_tree(), 4)
	assert_float(animation.pistol_weights().x).is_equal(1.0)
	await _tap_key(KEY_H)
	await _seconds(_switch_time())
	await get_tree().process_frame
	assert_float(animation.pistol_weights().x).is_equal(0.0)
	# The fists' blows are the melee layer's (gdstudio #1254), built on the first of their clips.
	var blow_clip := (animation.tree.tree_root as AnimationNodeBlendTree).get_node("MeleeClip")
	assert_str(String((blow_clip as AnimationNodeAnimation).animation)).is_equal(
		"melee/Melee_Unarmed_Jab"
	)
