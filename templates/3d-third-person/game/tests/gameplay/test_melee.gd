# Melee for every weapon (gdstudio #1254), through simulated input in the real physics world: V
# throws the held weapon's category blow (the pistol's whip, the fists' punch) and it lands on a
# dressed character's hit zones in its hit window, once; the empty hands' left click is the same
# blow; a pad button and the touch button press it too; a blow spends no ammunition, cuts a reload
# short and keeps the gun from firing until it has cooled down; a definition overrides its
# category's numbers; and every category's hits to kill per zone are held to the design's target.
extends GdUnitTestSuite

const PISTOL := "res://gameplay/weapon/pistol.tres"
const FISTS := "res://gameplay/weapon/fists.tres"
const UNARMED := "res://gameplay/weapon/categories/unarmed.tres"
const PISTOL_CATEGORY := "res://gameplay/weapon/categories/pistol.tres"
const RIFLE_CATEGORY := "res://gameplay/weapon/categories/rifle.tres"
const WEAPON := "res://gameplay/weapon/weapon.tscn"
const TICK := 1.0 / 60.0

var _arena: PlayArena
var _player: Player
var _camera: Camera3D
var _target: Character


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	_target = HitRange.target(_arena, Vector3(0.0, 0.0, -1.0))
	await InputSim.ticks(get_tree(), 6)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _health(body: Character) -> float:
	return Health.of(body).value


func _tap(code: Key) -> void:
	InputSim.key(code, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(code, false)
	await InputSim.ticks(get_tree(), 1)


func _seconds(seconds: float) -> void:
	await InputSim.ticks(get_tree(), ceili(seconds * Engine.physics_ticks_per_second) + 1)


func _to_fists() -> void:
	await _tap(KEY_H)
	await _seconds(0.6)
	assert_str(_player.weapon.definition.display_name).is_equal("Fists")


func test_the_project_has_melee_on_v_a_pad_button_and_a_touch_button() -> void:
	assert_bool(InputMap.has_action(&"melee")).is_true()
	var keys := []
	var pads := []
	for event in InputMap.action_get_events(&"melee"):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
		elif event is InputEventJoypadButton:
			pads.append((event as InputEventJoypadButton).button_index)
	assert_array(keys).contains([KEY_V])
	assert_array(pads).contains([JOY_BUTTON_LEFT_STICK])
	var touch := (
		load("res://ui/touch/third_person_touch_controls.tscn").instantiate() as CanvasLayer
	)
	var button := touch.get_node("SafeArea/Buttons/Melee")
	assert_str(String(button.get(&"action"))).is_equal("melee")
	touch.free()


func test_v_with_the_pistol_whips_a_character_and_spends_no_round() -> void:
	var weapon := _player.weapon
	assert_str(weapon.definition.display_name).is_equal("Pistol")
	var category := load(PISTOL_CATEGORY) as WeaponCategory
	assert_object(weapon.definition.category).is_same(category)
	var started: Array[int] = []
	weapon.melee_started.connect(func(blow: int) -> void: started.append(blow))
	var hits: Array[Dictionary] = []
	weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	var full := _health(_target)
	await _tap(KEY_V)
	assert_array(started).is_equal([0])
	assert_bool(weapon.meleeing).is_true()
	await _seconds(category.melee_hit_end)
	assert_int(hits.size()).is_equal(1)
	assert_bool(hits[0]["melee"]).is_true()
	assert_object(hits[0]["record"]).is_not_null()
	var record := hits[0]["record"] as HitRecord
	# The zone's multiplier is in the record's damage: the blow's damage, scaled by its part.
	assert_float(full - _health(_target)).is_equal_approx(record.damage, 0.01)
	var part := HitRange.zones_of(_target).zone(record.zone)
	assert_float(record.damage).is_equal_approx(
		category.melee_damage * part.damage_multiplier, 0.01
	)
	# No round spent, and the clip of the category played on the upper body.
	assert_int(weapon.ammo).is_equal(12)
	var animation := _player.get_node("Animation") as CharacterAnimation
	assert_bool(category.melee_clips.has(animation.melee.clip)).is_true()


func test_left_click_with_the_empty_hands_is_the_same_blow_as_v() -> void:
	await _to_fists()
	var category := load(UNARMED) as WeaponCategory
	var weapon := _player.weapon
	var hits: Array[Dictionary] = []
	weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	var started: Array[int] = []
	weapon.melee_started.connect(func(blow: int) -> void: started.append(blow))
	var full := _health(_target)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await _seconds(category.melee_hit_end)
	assert_array(started).is_equal([0])
	assert_int(hits.size()).is_equal(1)
	var after_click := _health(_target)
	assert_float(after_click).is_less(full)
	await _seconds(category.melee_cooldown)
	await _tap(KEY_V)
	await _seconds(category.melee_hit_end)
	assert_array(started).is_equal([0, 1])
	assert_int(hits.size()).is_equal(2)
	# The same blow: the same damage on the same part.
	assert_float(after_click - _health(_target)).is_equal_approx(full - after_click, 0.01)


func test_the_pad_button_and_the_touch_button_throw_the_blow() -> void:
	var weapon := _player.weapon
	var started: Array[int] = []
	weapon.melee_started.connect(func(blow: int) -> void: started.append(blow))
	InputSim.pad_button(JOY_BUTTON_LEFT_STICK, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.pad_button(JOY_BUTTON_LEFT_STICK, false)
	await _seconds(weapon.definition.blow_cooldown())
	assert_int(started.size()).is_equal(1)
	# A touch button presses its action (`TouchButton` calls `Input.action_press`).
	Input.action_press(&"melee")
	await InputSim.ticks(get_tree(), 2)
	Input.action_release(&"melee")
	await InputSim.ticks(get_tree(), 1)
	assert_int(started.size()).is_equal(2)


# The chest's turn in the player's own space (its +Z is behind it).
func _chest(skeleton: Skeleton3D, bone: int) -> Basis:
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	return (_player.global_transform.affine_inverse() * pose).basis.orthonormalized()


func test_a_pistol_blow_never_folds_the_body_back() -> void:
	# A blow turns the body as an aim does but raises no aim pose: with one, the aim offset pointed
	# the carried pistol at the aim before the clip held the body and after it let go, and the
	# chest folded 66 degrees back for those frames (pull request #1315). Read after the skeleton's
	# modifiers, on every frame of the blow and of the aim coming down after it.
	var skeleton := _player.model.skeleton()
	var bone := skeleton.find_bone(&"spine_03")
	var animation := _player.get_node("Animation") as CharacterAnimation
	var upright := _chest(skeleton, bone)
	var worst := [0.0, 0.0, 0]
	var read := func() -> void:
		var up := (_chest(skeleton, bone) * upright.inverse()) * Vector3.UP
		worst[0] = maxf(worst[0], rad_to_deg(atan2(up.z, up.y)))
		worst[1] = maxf(worst[1], animation.pistol_weights().y)
		worst[2] += 1
	skeleton.skeleton_updated.connect(read)
	await _tap(KEY_V)
	assert_bool(_player.aiming).is_true()
	await _seconds(1.2)
	skeleton.skeleton_updated.disconnect(read)
	assert_int(worst[2]).is_greater(30)
	assert_float(worst[1]).is_equal(0.0)
	assert_float(worst[0]).is_less(4.0)


func test_the_blow_lands_in_its_window_and_once() -> void:
	var weapon := _player.weapon
	var category := load(PISTOL_CATEGORY) as WeaponCategory
	var hits: Array[Dictionary] = []
	weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	InputSim.key(KEY_V, true)
	await InputSim.ticks(get_tree(), 1)
	InputSim.key(KEY_V, false)
	# Before the window opens nothing is hit, however near the character stands.
	var early := floori(category.melee_hit_start / TICK) - 2
	await InputSim.ticks(get_tree(), early)
	assert_int(hits.size()).is_equal(0)
	await _seconds(category.melee_hit_end - category.melee_hit_start + 0.05)
	assert_int(hits.size()).is_equal(1)
	# A second V while the blow cools down throws nothing.
	await _tap(KEY_V)
	await _seconds(category.melee_hit_end)
	assert_int(hits.size()).is_equal(1)
	assert_int(weapon.blows).is_equal(1)


func test_a_blow_cuts_a_reload_short_and_holds_the_trigger_until_it_cools_down() -> void:
	var weapon := _player.weapon
	weapon.set_ammo(5, 30)
	assert_bool(weapon.reload()).is_true()
	await InputSim.ticks(get_tree(), 3)
	await _tap(KEY_V)
	assert_bool(weapon.is_reloading()).is_false()
	assert_int(weapon.ammo).is_equal(5)
	assert_bool(weapon.can_fire()).is_false()
	assert_bool(weapon.can_reload()).is_false()
	await _seconds(weapon.definition.blow_cooldown())
	assert_bool(weapon.can_fire()).is_true()


func test_a_blow_out_of_reach_misses() -> void:
	_target.global_position = Vector3(0.0, 0.0, -3.0)
	await InputSim.ticks(get_tree(), 2)
	var full := _health(_target)
	var hits: Array[Dictionary] = []
	_player.weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	await _tap(KEY_V)
	await _seconds(_player.weapon.definition.blow_cooldown())
	assert_int(hits.size()).is_equal(0)
	assert_float(_health(_target)).is_equal(full)


func test_a_definition_overrides_its_category_numbers_and_keeps_its_clips() -> void:
	var pistol := (load(PISTOL) as WeaponDef).duplicate() as WeaponDef
	var category := pistol.category
	assert_float(pistol.blow_damage()).is_equal(category.melee_damage)
	assert_float(pistol.blow_reach()).is_equal(category.melee_reach)
	assert_float(pistol.blow_cooldown()).is_equal(category.melee_cooldown)
	pistol.override_melee = true
	pistol.melee_damage = 99.0
	pistol.melee_reach = 2.0
	pistol.melee_hit_start = 0.4
	pistol.melee_hit_end = 0.1
	assert_float(pistol.blow_damage()).is_equal(99.0)
	assert_float(pistol.blow_reach()).is_equal(2.0)
	# A window that ends before it starts is held to its start.
	assert_float(pistol.blow_hit_end()).is_equal(0.4)
	assert_array(pistol.blow_clips()).is_equal(category.melee_clips)
	# No category: its own numbers and no clip.
	pistol.category = null
	pistol.override_melee = false
	assert_float(pistol.blow_damage()).is_equal(99.0)
	assert_array(pistol.blow_clips()).is_empty()
	# A category's clip change rebuilds whatever holds a definition of it (`changed`).
	var copy := (load(PISTOL) as WeaponDef).duplicate() as WeaponDef
	copy.category = category.duplicate() as WeaponCategory
	var told := [0]
	copy.changed.connect(func() -> void: told[0] += 1)
	copy.category.melee_clips = [&"ual1/Punch_Jab"] as Array[StringName]
	assert_int(told[0]).is_equal(1)


func test_the_weapons_point_at_their_categories() -> void:
	assert_object((load(PISTOL) as WeaponDef).category).is_same(load(PISTOL_CATEGORY))
	assert_object((load(FISTS) as WeaponDef).category).is_same(load(UNARMED))
	assert_int((load(FISTS) as WeaponDef).kind).is_equal(WeaponDef.Kind.MELEE)
	for path: String in [UNARMED, PISTOL_CATEGORY, RIFLE_CATEGORY]:
		var category := load(path) as WeaponCategory
		assert_float(category.melee_hit_end).is_greater_equal(category.melee_hit_start)
		assert_float(category.melee_cooldown).is_greater(category.melee_hit_end)
		assert_object(category.melee_sound).is_not_null()
	# Every clip a category names is in the player's animation.
	var player := _player.get_node("AnimationPlayer") as AnimationPlayer
	for path: String in [UNARMED, PISTOL_CATEGORY, RIFLE_CATEGORY]:
		for clip in (load(path) as WeaponCategory).melee_clips:
			assert_bool(player.has_animation(clip)).override_failure_message(clip).is_true()


# Hits to kill per zone through the real blow, hit zones and health (gamedev/balance.md
# #shots-to-kill): no blow kills at once anywhere, and each category meets its written target.
func test_every_category_meets_its_hits_to_kill_target() -> void:
	var targets := {
		UNARMED: {&"head": 3, &"chest": 7, &"arm_l": 12, &"thigh_l": 10},
		PISTOL_CATEGORY: {&"head": 2, &"chest": 4, &"arm_l": 7, &"thigh_l": 6},
		RIFLE_CATEGORY: {&"head": 2, &"chest": 4, &"arm_l": 6, &"thigh_l": 5},
	}
	_target.global_position = Vector3(0.0, 0.0, -6.0)
	await InputSim.ticks(get_tree(), 4)
	HitRange.freeze(_target)
	var zones := HitRange.zones_of(_target)
	var table := {}
	for path: String in targets:
		var weapon := load(WEAPON).instantiate() as Weapon
		weapon.self_ticking = false
		_arena.add_child(weapon)
		var definition := (load(PISTOL) as WeaponDef).duplicate() as WeaponDef
		definition.category = load(path) as WeaponCategory
		weapon.definition = definition
		var row := {}
		for zone_name: StringName in targets[path]:
			var part := zones.zone(zone_name)
			var line := HitRange.line_to(_target, part)
			assert_array(line).override_failure_message(String(zone_name)).is_not_empty()
			var way: Vector3 = line[1]
			var from: Vector3 = part.global_position - way * 0.6
			weapon.global_position = from
			Health.of(_target).reset()
			# One real blow on the part: its record (the zone's multiplier applied) says how many
			# such blows the full health takes. A loop of blows would let the flinch of each one
			# move the next onto another part.
			var records: Array[HitRecord] = []
			var take := func(record: HitRecord) -> void: records.append(record)
			_target.hit_received.connect(take)
			weapon.make_ready()
			assert_int(weapon.melee(from, way)).is_equal(Weapon.Pull.FIRED)
			for _tick in ceili(definition.blow_hit_end() / TICK) + 1:
				weapon.tick(TICK)
			_target.hit_received.disconnect(take)
			assert_int(records.size()).override_failure_message(String(zone_name)).is_equal(1)
			assert_str(String(records[0].zone)).is_equal(String(zone_name))
			assert_bool(records[0].killed).is_false()
			row[zone_name] = ceili(Health.of(_target).max_value / records[0].damage - 0.0001)
		table[path.get_file()] = row
		weapon.queue_free()
	for path: String in targets:
		(
			assert_dict(table[path.get_file()])
			. override_failure_message("hits to kill %s" % str(table))
			. is_equal(targets[path])
		)
