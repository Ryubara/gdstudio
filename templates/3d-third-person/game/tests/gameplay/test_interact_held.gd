# Using a door or a lever plays the interact clip's reach whatever is held (kit #1336): the clip
# reaches with the left arm, and with a weapon in both hands the hold kept that arm on the weapon,
# so nothing showed with the rifle held, nor with the pistol aimed. On the live player, with
# every `WeaponDef` of `gameplay/weapon/` in the hands (and one no list could name), at rest and
# aiming: the action layer plays the interact clip and the left hand goes where it goes with
# empty hands; the hand that still holds the weapon stays within the hold's limits
# (`HandContact`: 2 mm in, a holding part 5 mm off), the hand that reaches passes no deeper
# through the weapon than a hand may between two places, nothing is in the torso, and both hands
# hold again after. On both bodies posed by hand (`RifleStage`, `HoldStage`): the same through the
# whole let-go and return.
extends GdUnitTestSuite

const WEAPONS := "res://gameplay/weapon/"
const RIFLE := "res://gameplay/weapon/rifle.tres"
const MODELS: Array[String] = ["female", "male"]
## The updates after the press over which the clip's arm has the hand whole, whatever is held
## (every hold has let go by 0.16 s and none comes back before 0.44 s of the 0.7 s).
const FREE_UPDATES := Vector2i(11, 25)
## How far the reaching hand may be from where it is with empty hands, in the chest's space.
const SAME_REACH := 0.015
## How far the hand travels from where it hangs when the reach shows, in metres.
const REACH_SHOWS := 0.25
## How deep the reaching hand may pass through the weapon between its places, in metres (the
## reload's own limit).
const PASSING_DEPTH := 0.006
## How deep any point of the weapon may be in the torso's skin, in metres (the rifle's stock).
const WEAPON_IN_BODY := 0.01
## How far a hand's bone may be from its place on the rifle, in metres.
const ON_PLACE := 0.005
## The action's time, and its layer's time to blend in and out, in seconds (the tuning's
## `interact_time`, the animation's `action_blend_time`).
const SECONDS := 0.7
const BLEND := 0.1
## The right hand's parts that are the trigger finger: on its way between the trigger and the
## weapon's side it is held to the passing depth, and to no contact.
const TRIGGER_FINGER: Array[String] = ["index_base", "index_mid", "index_tip"]
## How deep it may pass, in metres: the pistol's has no solved way round the guard as the rifle's
## has, and on the male it passes 7.0 mm on the straight way, in an interact as in every aim.
const TRIGGER_PASSING := 0.008
## The left arm's points that are looked for in the torso: each bone's own place.
const ARM_POINTS: Array[StringName] = [&"lowerarm_l", &"hand_l", &"middle_01_l", &"middle_03_l"]

var _holder: Node3D
var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _contact: HandContact
var _clearance: BodyClearance
var _weapon_view: Node3D
var _held_parts: Array[String] = []
var _recording := false
# One entry an update since the press: the left hand in the chest's space, what plays, and what
# each hand and the weapon are in.
var _updates: Array[Dictionary] = []


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		_end_arena()


func test_the_hand_is_let_go_and_comes_back_over_the_actions_time() -> void:
	var timer := FreeHand.new()
	timer.release_time = 0.16
	timer.return_time = 0.26
	assert_float(timer.amount()).is_equal(0.0)
	assert_bool(timer.is_free()).is_false()
	timer.start(0.7)
	assert_float(timer.amount()).is_equal(0.0)
	var last := 0.0
	var seen: Dictionary[int, float] = {}
	for tick in 42:
		timer.step(1.0 / 60.0)
		var now := timer.amount()
		# Never a jump: a tick moves it by a tick of the shorter of the two times at most.
		assert_float(absf(now - last)).is_less(1.0 / 60.0 / 0.16 + 0.001)
		last = now
		seen[tick + 1] = now
	assert_float(seen[5]).is_equal_approx(0.52, 0.01)
	for tick in range(10, 27):
		assert_float(seen[tick]).is_equal(1.0)
	assert_float(seen[34]).is_equal_approx(0.51, 0.02)
	assert_float(seen[42]).is_equal_approx(0.0, 0.001)
	assert_bool(timer.is_free()).is_false()
	# The first half is the hand's way off the weapon, the second the clip's arm taking it.
	assert_float(FreeHand.off(0.25)).is_equal_approx(0.5, 0.001)
	assert_float(FreeHand.gone(0.25)).is_equal(0.0)
	assert_float(FreeHand.off(0.5)).is_equal(1.0)
	assert_float(FreeHand.gone(0.75)).is_equal_approx(0.5, 0.001)
	assert_float(FreeHand.gone(1.0)).is_equal(1.0)
	# An action shorter than the two times never gets the hand all the way off, and never jumps.
	timer.start(0.2)
	var most := 0.0
	for tick in 12:
		timer.step(1.0 / 60.0)
		most = maxf(most, timer.amount())
	assert_float(most).is_between(0.3, 0.6)
	timer.start(0.7)
	timer.step(0.3)
	timer.stop()
	assert_float(timer.amount()).is_equal(0.0)


# The reach itself, read on every update: the same with every weapon as with empty hands.
func test_the_interact_reach_plays_with_every_weapon_held() -> void:
	var definitions := _definitions()
	assert_int(definitions.size()).override_failure_message("no weapon found").is_greater(3)
	var empty: Array[Dictionary] = []
	for aiming: bool in [false, true]:
		for definition in definitions:
			var tag := "%s%s" % [definition.display_name, ", aiming" if aiming else ""]
			await _player_holding(definition)
			await _interact(aiming, false)
			_assert_played(tag)
			if definition == _player.loadout.unarmed and not aiming:
				empty = _updates.duplicate()
				_assert_reach_shows(tag)
			_assert_same_reach(tag, empty)
			_end_arena()


# The hands on the weapon through it, and the weapon and the arm against the body.
func test_the_hands_stay_within_the_hold_limits_through_an_interact() -> void:
	for aiming: bool in [false, true]:
		for definition in _definitions():
			if definition.view.is_empty():
				continue
			var tag := "%s%s" % [definition.display_name, ", aiming" if aiming else ""]
			await _player_holding(definition)
			await _measure_at_rest(aiming)
			await _interact(aiming, true)
			_assert_played(tag)
			_assert_hands_hold(tag)
			_end_arena()


# The rifle on both bodies, posed by hand at every tick of an interact (the idle blended into the
# interact clip and out of it as the action layer does): the right hand holds, the left passes
# through nothing and has the clip's own arm in the middle, and the rifle that the right hand
# alone takes down stays out of the chest.
func test_the_rifles_left_hand_lets_go_clean_on_both_bodies() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		var held := stage.hold as TwoHandHold
		var clearance := BodyClearance.new(stage.skeleton, stage.contact, _near(stage.rifle))
		var timer := FreeHand.new()
		timer.release_time = held.free_release_time
		timer.return_time = held.free_return_time
		timer.start(SECONDS)
		var deepest := 0.0
		for tick in roundi(SECONDS * 60.0) + 1:
			var freed := timer.amount()
			held.posed_free = freed
			stage.pose_rifle(CharacterClips.IDLE, 0.0)
			_blend_in_the_action(stage, tick)
			await stage.settle()
			var tag := "%s tick %d free %.2f" % [model, tick, freed]
			var right := stage.contact.measure("r")
			var right_fails := HandContact.failures(tag, right, RifleStage.RIFLE_RIGHT_CONTACTS)
			assert_array(right_fails).is_empty()
			assert_float(stage.hand_gap("r")).is_less(ON_PLACE)
			var left := stage.contact.measure("l")
			if freed <= 0.0:
				var left_fails := HandContact.failures(tag, left, RifleStage.RIFLE_LEFT_CONTACTS)
				assert_array(left_fails).is_empty()
				assert_float(stage.hand_gap("l")).is_less(ON_PLACE)
			deepest = maxf(deepest, _assert_passes(tag, left, "gun"))
			if freed >= 1.0:
				(
					assert_float(_off_the_clip(stage))
					. override_failure_message("%s: the left hand is not the clip's" % tag)
					. is_less(0.001)
				)
			var found := clearance.deepest(_near(stage.rifle))
			(
				assert_float(found.depth)
				. override_failure_message(
					"%s: the rifle is %.1f mm in the %s" % [tag, found.depth * 1e3, found.bone]
				)
				. is_less_equal(WEAPON_IN_BODY)
			)
			timer.step(1.0 / 60.0)
		prints(model, "the left hand's deepest pass through the rifle: %.1f mm" % (deepest * 1e3))
		stage.free()


# The pistol aimed on both bodies, at every tick of an interact (the aim pose blended into the
# interact clip and out of it): the right hand holds, with its index finger on its way off the
# trigger and back, and the left hand comes off the right hand and the grip along its own way and
# passes through neither.
func test_the_pistols_left_hand_lets_go_clean_on_both_bodies() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		var timer := FreeHand.new()
		timer.release_time = stage.hold.get(&"free_release_time")
		timer.return_time = stage.hold.get(&"free_return_time")
		timer.start(SECONDS)
		var deepest := 0.0
		var continue_ticks := 0
		for tick in roundi(SECONDS * 60.0) + 1:
			var freed := timer.amount()
			stage.hold.set(&"free_weight", freed)
			stage.pose(CharacterClips.PISTOL_AIM, 0.16, 1.0)
			_blend_in_the_action(stage, tick)
			await stage.settle()
			var tag := "%s tick %d free %.2f" % [model, tick, freed]
			var right := stage.contact.measure("r")
			_assert_passes(tag, right, "gun", TRIGGER_FINGER, TRIGGER_PASSING)
			var holding: Array[String] = []
			for part in HoldStage.RIGHT_CONTACTS:
				if not TRIGGER_FINGER.has(part):
					holding.append(part)
			for part in TRIGGER_FINGER:
				right.erase(part)
			assert_array(HandContact.failures(tag, right, holding)).is_empty()
			if freed >= 1.0:
				assert_float(_off_the_clip(stage)).is_less(0.001)
			# While the weapon's arm goes down and comes up it is out of the left arm's reach (kit
			# #1078, the aim's own blend): the left hand is measured where its arm reaches.
			var short: float = stage.hold.call(&"support_shortfall")
			if short > ON_PLACE and freed < 1.0:
				continue_ticks += 1
			else:
				var left := stage.contact.measure("l", true)
				deepest = maxf(deepest, _assert_passes(tag, left, "distance"))
			timer.step(1.0 / 60.0)
		assert_int(continue_ticks).is_less(14)
		prints(
			model,
			"the left hand's deepest pass off the pistol: %.1f mm" % (deepest * 1e3),
			"(%d ticks out of the arm's reach)" % continue_ticks
		)
		stage.free()


# A reload keeps the rifle's left hand: the magazine is in it.
func test_a_reload_keeps_the_rifles_left_hand() -> void:
	await _player_holding(load(RIFLE) as WeaponDef)
	var hold := _weapon_view as TwoHandHold
	_player.weapon.set_ammo(3, 60)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.weapon.is_reloading()).is_true()
	await _interact(false, false)
	_assert_played("reloading")
	for entry in _updates:
		assert_float(entry.freed).is_equal(0.0)
	assert_float(hold.free_amount()).is_equal(0.0)
	_end_arena()


# Every `WeaponDef` in the weapons' folder, the empty hands first (the reach the others are held
# to), and a rifle under a name no list has.
func _definitions() -> Array[WeaponDef]:
	var found: Array[WeaponDef] = []
	for file in DirAccess.get_files_at(WEAPONS):
		if not file.ends_with(".tres"):
			continue
		var definition := load(WEAPONS + file) as WeaponDef
		if definition == null:
			continue
		if definition.kind == WeaponDef.Kind.MELEE:
			found.push_front(definition)
		else:
			found.append(definition)
	var unlisted := (load(RIFLE) as WeaponDef).duplicate() as WeaponDef
	unlisted.display_name = "Unlisted"
	found.append(unlisted)
	return found


# A player in an arena with `definition` in its hands, up and ready, and a lever in reach.
func _player_holding(definition: WeaponDef) -> void:
	_arena = PlayArena.new()
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	var lever := Node3D.new()
	lever.position = Vector3(0.0, 0.0, -1.0)
	_arena.add_child(lever)
	var usable := Interactable.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	usable.add_child(shape)
	lever.add_child(usable)
	await InputSim.ticks(get_tree(), 10)
	var loadout := _player.loadout
	if loadout.unarmed != null and definition.resource_path == loadout.unarmed.resource_path:
		loadout.select(WeaponLoadout.UNARMED)
	else:
		var slot := -1
		for index in loadout.slots.size():
			if (loadout.slots[index] as WeaponDef).resource_path == definition.resource_path:
				slot = index
		if slot >= 0 and definition.resource_path != "":
			loadout.select(slot)
		else:
			loadout.give(definition, 60)
	await InputSim.ticks(get_tree(), 70)
	assert_str(_player.weapon.definition.display_name).is_equal(definition.display_name)
	assert_bool(loadout.is_switching()).is_false()
	_skeleton = _player.model.skeleton()
	_weapon_view = null
	if not definition.view.is_empty():
		_weapon_view = _player.model.get_node(definition.view) as Node3D
	_contact = null
	_clearance = null
	_held_parts.clear()
	_updates.clear()


# The parts of each hand that hold the weapon before the press (none is listed by weapon), and
# the measures an update is read with.
func _measure_at_rest(aiming: bool) -> void:
	if aiming:
		InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	_contact = HandContact.new(_skeleton)
	_contact.set_weapon(_near(_weapon_view))
	_clearance = BodyClearance.new(_skeleton, _contact, _near(_weapon_view))
	_skeleton.skeleton_updated.connect(_contact.snapshot)
	await InputSim.ticks(get_tree(), 2)
	_skeleton.skeleton_updated.disconnect(_contact.snapshot)
	for side: String in ["r", "l"]:
		var parts := _contact.measure(side)
		for part: String in parts:
			assert_float(parts[part].gun).is_greater_equal(-HandContact.MAX_DEPTH)
			if parts[part].gun <= HandContact.MAX_FLOAT and not part.ends_with("_base"):
				_held_parts.append("%s %s" % [side, part])
	assert_int(_held_parts.size()).override_failure_message("no hand holds it").is_greater(5)


# Presses the interact key (holding the aim with `aiming`) and reads every update until the hands
# are back: 0.7 s of the action and a third of a second more.
func _interact(aiming: bool, measured: bool) -> void:
	if aiming:
		InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
		await InputSim.ticks(get_tree(), 40)
	_updates.clear()
	_recording = false
	var started := func(_target: Node3D) -> void: _recording = true
	_player.interacted.connect(started)
	var reader := _read_update.bind(measured)
	_skeleton.skeleton_updated.connect(reader)
	InputSim.key(KEY_E, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_E, false)
	await InputSim.ticks(get_tree(), 62)
	_skeleton.skeleton_updated.disconnect(reader)
	_player.interacted.disconnect(started)
	InputSim.release_all()


func _read_update(measured: bool) -> void:
	if not _recording:
		return
	var animation := _player.get_node("Animation") as CharacterAnimation
	var chest := _skeleton.get_bone_global_pose(_skeleton.find_bone(&"spine_03"))
	var hand := _skeleton.get_bone_global_pose(_skeleton.find_bone(&"hand_l"))
	var entry := {
		"hand": chest.affine_inverse() * hand.origin,
		"acting": animation.is_acting(),
		"clip": animation.last_action(),
		"freed": 0.0,
	}
	if _weapon_view is TwoHandHold:
		entry.freed = (_weapon_view as TwoHandHold).free_amount()
		entry.right = _place_gap("RightHandTarget", &"hand_r")
	var pistol_hold := _player.get_node_or_null("WeaponHold") as WeaponHold
	entry.short = 0.0
	# Only while the hold's arm has the hand: it keeps its last number once it lets go.
	if pistol_hold != null and pistol_hold.support_weights().x > 0.0:
		if not _weapon_view is TwoHandHold:
			entry.short = pistol_hold.support_shortfall()
	# Every update is measured on the skin: the hands on the weapon, the weapon and the left arm
	# against the torso.
	if measured:
		_contact.snapshot()
		entry.right_parts = _contact.measure("r")
		entry.left_parts = _contact.measure("l")
		entry.weapon_in = _clearance.deepest(_near(_weapon_view))
		var region := AABB(chest.origin, Vector3.ZERO).grow(0.6)
		_clearance.pose_skin(region)
		entry.arm_in = 0.0
		entry.arm_bone = &""
		for bone_name in ARM_POINTS:
			var depth: float = _clearance.depth_at(_contact.bone_pose(bone_name).origin).depth
			if depth > entry.arm_in:
				entry.arm_in = depth
				entry.arm_bone = bone_name
	_updates.append(entry)


# How far the bone `bone_name` is from the rifle's marker `marker`, in metres.
func _place_gap(marker: String, bone_name: StringName) -> float:
	var target := _weapon_view.find_child(marker, true, false) as Node3D
	var pose := (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name))
	)
	return pose.origin.distance_to(target.global_position)


func _assert_played(tag: String) -> void:
	assert_int(_updates.size()).override_failure_message("%s: no interact" % tag).is_greater(50)
	for index in range(2, 38):
		var entry := _updates[index]
		(
			assert_bool(entry.acting and entry.clip == CharacterClips.INTERACT)
			. override_failure_message("%s: update %d plays no interact clip" % [tag, index])
			. is_true()
		)
	assert_bool(_updates[-1].acting).is_false()


# With empty hands the left hand travels from where it hangs: the reach is there to compare with.
func _assert_reach_shows(tag: String) -> void:
	var farthest := 0.0
	for entry in _updates:
		farthest = maxf(farthest, (entry.hand as Vector3).distance_to(_updates[-1].hand))
	(
		assert_float(farthest)
		. override_failure_message("%s: the hand reaches %.2f m" % [tag, farthest])
		. is_greater(REACH_SHOWS)
	)


# The left hand is where it is with empty hands on every update the clip's arm has it whole.
func _assert_same_reach(tag: String, empty: Array[Dictionary]) -> void:
	assert_int(empty.size()).is_greater(FREE_UPDATES.y)
	var worst := 0.0
	var worst_at := -1
	for index in range(FREE_UPDATES.x, FREE_UPDATES.y + 1):
		var off := (_updates[index].hand as Vector3).distance_to(empty[index].hand)
		if off > worst:
			worst = off
			worst_at = index
	(
		assert_float(worst)
		. override_failure_message(
			(
				"%s: the left hand is %.0f mm from the interact clip's reach (update %d)"
				% [tag, worst * 1e3, worst_at]
			)
		)
		. is_less(SAME_REACH)
	)


# The hand that holds stays in the hold's limits on every measured update, the left passes no
# deeper than a hand may, the weapon and the arm stay out of the torso, and at the end every
# part that held before the press holds again.
func _assert_hands_hold(tag: String) -> void:
	var measured := 0
	var out_of_reach := 0
	var deepest_pass := 0.0
	var last: Dictionary = {}
	for index in _updates.size():
		var entry := _updates[index]
		if entry.has("right"):
			(
				assert_float(entry.right)
				. override_failure_message(
					"%s update %d: the right hand is %.1f mm off" % [tag, index, entry.right * 1e3]
				)
				. is_less(ON_PLACE)
			)
		if not entry.has("right_parts"):
			continue
		measured += 1
		last = entry
		var at := "%s update %d" % [tag, index]
		var right: Dictionary = (entry.right_parts as Dictionary).duplicate()
		_assert_passes(at + " right", right, "gun", TRIGGER_FINGER, TRIGGER_PASSING)
		var holding: Array[String] = []
		for part: String in right:
			if _held_parts.has("r " + part) and not TRIGGER_FINGER.has(part):
				holding.append(part)
		for part in TRIGGER_FINGER:
			right.erase(part)
		assert_array(HandContact.failures(at + " right", right, holding)).is_empty()
		# A left arm the weapon's arm has gone out of the reach of is the aim's own blend (kit #1078).
		if entry.short <= ON_PLACE:
			deepest_pass = maxf(deepest_pass, _assert_passes(at + " left", entry.left_parts, "gun"))
		else:
			out_of_reach += 1
		(
			assert_float(entry.weapon_in.depth)
			. override_failure_message(
				(
					"%s: the weapon is %.1f mm in the %s"
					% [at, entry.weapon_in.depth * 1e3, entry.weapon_in.bone]
				)
			)
			. is_less_equal(WEAPON_IN_BODY)
		)
		# The arm against the torso while the action plays: after it the aim's own rise has it.
		if entry.acting:
			(
				assert_float(entry.arm_in)
				. override_failure_message(
					(
						"%s: the left %s is %.1f mm in the torso"
						% [at, entry.arm_bone, entry.arm_in * 1e3]
					)
				)
				. is_equal(0.0)
			)
	assert_int(measured).is_greater(50)
	assert_int(out_of_reach).is_less(14)
	var back: Array[String] = []
	for part: String in last.left_parts:
		if _held_parts.has("l " + part):
			back.append(part)
	assert_array(HandContact.failures(tag + " after, left", last.left_parts, back)).is_empty()
	prints(
		tag,
		"the left hand's deepest pass through the weapon: %.1f mm" % (deepest_pass * 1e3),
		"(%d updates out of the arm's reach)" % out_of_reach
	)


# How far the left hand is from where the clip alone has it, in the chest's space, in metres.
func _off_the_clip(stage: HoldStage) -> float:
	var chest := stage.skeleton.find_bone(&"spine_03")
	var hand := stage.skeleton.find_bone(&"hand_l")
	var clip_hand := (
		HandPoseModifier.global_pose(stage.skeleton, chest).affine_inverse()
		* HandPoseModifier.global_pose(stage.skeleton, hand).origin
	)
	var posed := (
		stage.contact.bone_pose(&"spine_03").affine_inverse()
		* stage.contact.bone_pose(&"hand_l").origin
	)
	return clip_hand.distance_to(posed)


# The meshes a weapon is measured on: its near level when it has levels.
func _near(weapon: Node3D) -> Node3D:
	var near := weapon.find_child("Near", true, false) as Node3D
	return near if near != null else weapon


func _end_arena() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)
	_arena.free()
	_arena = null


# Blends the interact clip over the pose the stage has, as the action layer does at `tick` of
# the action: in over `BLEND`, whole in the middle, out over the clip's last `BLEND`.
func _blend_in_the_action(stage: HoldStage, tick: int) -> void:
	var elapsed := tick / 60.0
	var weight := clampf(minf(elapsed, SECONDS - elapsed) / BLEND, 0.0, 1.0)
	var clip := stage.clip(CharacterClips.INTERACT)
	var time := elapsed / SECONDS * clip.length
	var skeleton := stage.skeleton
	for track in clip.get_track_count():
		var bone := skeleton.find_bone(
			String(clip.track_get_path(track).get_concatenated_subnames())
		)
		if bone < 0:
			continue
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				var turned := clip.rotation_track_interpolate(track, time)
				skeleton.set_bone_pose_rotation(
					bone, skeleton.get_bone_pose_rotation(bone).slerp(turned, weight)
				)
			Animation.TYPE_POSITION_3D:
				var placed := clip.position_track_interpolate(track, time)
				skeleton.set_bone_pose_position(
					bone, skeleton.get_bone_pose_position(bone).lerp(placed, weight)
				)


# No part of `parts` (or only those of `only`) is deeper than a hand may pass, by the measure's
# `field` ("gun": the weapon alone; "distance": the other hand too). Returns the deepest.
func _assert_passes(
	tag: String, parts: Dictionary, field: String, only: Array[String] = [], limit := PASSING_DEPTH
) -> float:
	var deepest := 0.0
	for part: String in parts:
		if not only.is_empty() and not only.has(part):
			continue
		var depth: float = -parts[part][field]
		deepest = maxf(deepest, depth)
		(
			assert_float(depth)
			. override_failure_message("%s: the %s is %.1f mm in" % [tag, part, depth * 1e3])
			. is_less_equal(limit)
		)
	return deepest
