# Using a bandage in the game through the real input path (kit #1342): key 3 starts a use that
# takes the bandage's `use_time`, plays its clip over the upper body with its sound and the HUD's
# sign, lowers the aim, and heals once, with the count and the health changing on the same tick.
# More presses during the use use nothing (one press, one bandage). Sprinting, the fire button, a
# new aim and a hit cut it short and change nothing; a press at full health is refused.
extends GdUnitTestSuite

const USE_TIME := 1.6
const HEAL := 25.0

var _scene: Node
var _player: Player
var _use: ItemUse
var _health: Health
var _sign: HudUse


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_player = _scene.get_node("PlayerRig/Player")
	_use = ItemUse.of(_player)
	_health = Health.of(_player)
	var hud: Hud = _scene.get_node("Hud")
	_sign = hud.region(&"BottomCenter").get_node("HudUse")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_scene)


func _tap_key(code: Key) -> void:
	InputSim.key(code, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(code, false)
	await InputSim.ticks(get_tree(), 2)


func _bandages() -> int:
	return _player.inventory.count_of_id(&"bandage")


func _wait_until_idle() -> void:
	for _tick in 240:
		if not _use.is_using():
			return
		await get_tree().physics_frame


func test_the_bandage_takes_time_and_plays_its_clip_on_the_upper_body() -> void:
	var bandage: ItemDef = Hotbar.of(_player).item_at(0)
	assert_float(bandage.use_time).is_equal(USE_TIME)
	assert_str(String(bandage.use_clip)).is_equal("ual2/Consume")
	assert_object(bandage.use_sound).is_not_null()
	_health.value = 40.0
	await _tap_key(KEY_3)
	assert_bool(_use.is_using()).is_true()
	var animation := _player.get_node("Animation") as CharacterAnimation
	assert_str(String(animation.last_action())).is_equal("ual2/Consume")
	assert_bool(animation.is_acting()).is_true()
	var root := animation.tree.tree_root as AnimationNodeBlendTree
	var action := root.get_node(&"Action") as AnimationNodeOneShot
	await InputSim.ticks(get_tree(), 2)
	# The clip holds the spine and the left arm; the right arm keeps the weapon's carry.
	assert_bool(action.filter_enabled).is_true()
	assert_bool(action.is_path_filtered(NodePath("Armature/Skeleton3D:upperarm_l"))).is_true()
	assert_bool(action.is_path_filtered(NodePath("Armature/Skeleton3D:upperarm_r"))).is_false()
	assert_bool(action.is_path_filtered(NodePath("Armature/Skeleton3D:thigh_l"))).is_false()
	# The chest is turned back to where the clip's hips have it (`UseTurn`), eased in.
	var turn := UseLayer.turn_of(animation, false)
	assert_object(turn).is_not_null()
	assert_bool(turn.is_following()).is_true()
	await InputSim.ticks(get_tree(), 10)
	assert_float(turn.weight()).is_equal(1.0)
	# The sign shows the bandage above the hotbar, and the sound plays.
	assert_bool(_sign.visible).is_true()
	assert_str(_sign.name_label.text).is_equal("Bandage")
	assert_bool(_use.sound.playing).is_true()
	# At the character, wherever it stands (a 3D node under a plain node sits at the origin).
	assert_float(_use.sound.global_position.distance_to(_player.global_position)).is_less(2.0)
	# Nothing has changed yet: the bandage works near the end of the use.
	assert_float(_health.value).is_equal(40.0)
	assert_int(_bandages()).is_equal(3)
	await _wait_until_idle()
	assert_float(_health.value).is_equal(40.0 + HEAL)
	assert_int(_bandages()).is_equal(2)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(turn.is_following()).is_false()
	# The sign lingers a moment, then goes.
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_sign.visible).is_false()


func test_one_press_uses_exactly_one_bandage_however_often_the_key_is_pressed() -> void:
	_health.value = 12.0
	# Three quick presses, as in the playtest that healed 12 to 87 and used three.
	await _tap_key(KEY_3)
	await _tap_key(KEY_3)
	await _tap_key(KEY_3)
	await _wait_until_idle()
	await InputSim.ticks(get_tree(), 4)
	assert_float(_health.value).is_equal(12.0 + HEAL)
	assert_int(_bandages()).is_equal(2)


func test_the_count_and_the_health_change_on_the_same_tick() -> void:
	_health.value = 30.0
	var ticks := {}
	var on_health := func(_value: float, _max: float) -> void:
		ticks["health"] = Engine.get_physics_frames()
	var on_count := func() -> void: ticks["count"] = Engine.get_physics_frames()
	_health.changed.connect(on_health)
	Hotbar.of(_player).changed.connect(on_count)
	await _tap_key(KEY_3)
	await _wait_until_idle()
	_health.changed.disconnect(on_health)
	Hotbar.of(_player).changed.disconnect(on_count)
	assert_bool(ticks.has("health") and ticks.has("count")).is_true()
	assert_int(ticks["count"]).is_equal(ticks["health"])


func test_the_aim_goes_down_while_the_hands_are_busy() -> void:
	_health.value = 30.0
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.aiming).is_true()
	await _tap_key(KEY_3)
	await InputSim.ticks(get_tree(), 4)
	# The aim held from before is lowered, not a cancel.
	assert_bool(_use.is_using()).is_true()
	assert_bool(_player.aiming).is_false()
	await _wait_until_idle()
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_player.aiming).is_true()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	assert_float(_health.value).is_equal(30.0 + HEAL)


func test_sprinting_cuts_the_use_short_and_changes_nothing() -> void:
	_health.value = 30.0
	var reasons: Array[StringName] = []
	_use.cancelled.connect(func(_p: int, _i: ItemDef, why: StringName) -> void: reasons.append(why))
	await _tap_key(KEY_3)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 30)
	InputSim.key(KEY_SHIFT, false)
	InputSim.key(KEY_W, false)
	assert_bool(_use.is_using()).is_false()
	assert_array(reasons).contains([&"sprint"])
	await InputSim.ticks(get_tree(), 90)
	assert_float(_health.value).is_equal(30.0)
	assert_int(_bandages()).is_equal(3)


func test_the_fire_button_cuts_the_use_short() -> void:
	_health.value = 30.0
	await _tap_key(KEY_3)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_use.is_using()).is_false()
	await InputSim.ticks(get_tree(), 120)
	assert_float(_health.value).is_equal(30.0)
	assert_int(_bandages()).is_equal(3)


func test_a_new_aim_press_cuts_the_use_short() -> void:
	_health.value = 30.0
	await _tap_key(KEY_3)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	assert_bool(_use.is_using()).is_false()


func test_a_hit_that_takes_health_cuts_the_use_short() -> void:
	_health.value = 60.0
	await _tap_key(KEY_3)
	await InputSim.ticks(get_tree(), 6)
	_player.hit(5.0)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_use.is_using()).is_false()
	await InputSim.ticks(get_tree(), 120)
	assert_float(_health.value).is_less(60.0)
	assert_int(_bandages()).is_equal(3)


func test_a_press_at_full_health_is_refused_and_starts_nothing() -> void:
	await _tap_key(KEY_3)
	assert_bool(_use.is_using()).is_false()
	assert_bool(_sign.visible).is_false()
	assert_int(_bandages()).is_equal(3)


func test_a_cut_use_lets_the_next_press_heal() -> void:
	_health.value = 30.0
	await _tap_key(KEY_3)
	_use.cancel(&"test")
	await _tap_key(KEY_3)
	await _wait_until_idle()
	assert_float(_health.value).is_equal(30.0 + HEAL)
	assert_int(_bandages()).is_equal(2)


func test_every_export_of_the_item_use_has_its_default_pinned() -> void:
	var fresh := ItemUse.new()
	assert_bool(fresh.cancel_on_sprint).is_true()
	assert_bool(fresh.cancel_on_fire).is_true()
	assert_bool(fresh.cancel_on_aim).is_true()
	assert_bool(fresh.cancel_on_jump).is_true()
	assert_bool(fresh.cancel_on_weapon_press).is_true()
	assert_bool(fresh.cancel_on_prone).is_true()
	assert_bool(fresh.cancel_on_hit).is_true()
	fresh.free()
	assert_float(_use.sound.volume_db).is_equal(-14.0)
	assert_str(String(_use.sound.bus)).is_equal("SFX")
	var shown := HudUse.new()
	assert_float(shown.linger_time).is_equal(0.35)
	shown.free()
