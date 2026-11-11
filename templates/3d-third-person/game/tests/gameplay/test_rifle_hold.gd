# Both hands hold the rifle (kit #889): in every state the rifle has, on both mannequins, each
# hand's bone is on its place on the rifle, the grip hand's palm is on the `Grip` socket and the
# support hand's under the `Support` socket, no skin is more than 2 mm inside the rifle and no
# holding part more than 5 mm off it; the index finger is on the trigger only while the rifle is
# up. Only a reload takes the left hand away: to the magazine, down with it and back. And a
# switch is one sequence: no update shows the rifle and the pistol together, none shows neither,
# and none shows the rifle without both hands on it. Measured on the skinned mesh after the hold's
# modifiers ran (`RifleStage`, `HandContact`), and on the live player with simulated input.
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
const RIFLE := "res://gameplay/weapon/rifle.tres"
## The locomotion clips the rifle is carried in, with the times sampled.
const CARRIED: Dictionary[StringName, Array] = {
	CharacterClips.IDLE: [0.0, 1.0],
	CharacterClips.WALK: [0.0, 0.3, 0.6],
	CharacterClips.RUN: [0.0, 0.3],
	CharacterClips.SPRINT: [0.0, 0.2],
	CharacterClips.CROUCH_IDLE: [0.0],
	CharacterClips.CROUCH_WALK: [0.0, 0.4],
}
## The clips the view's pitch is tried in, and the pitches, in degrees.
const PITCHED: Array[StringName] = [CharacterClips.IDLE, CharacterClips.CROUCH_IDLE]
const PITCHES: Array[float] = [-30.0, 30.0]
## How far a hand's bone may be from its place on the rifle, in metres (a clamped arm stops short).
const REACH := 0.005
## How far the palm's skin may be from the socket it holds, in metres: `Grip` is in the middle of
## the grip (its half thickness away from the palm), `Support` inside the hand guard, above the
## palm that is under it.
const PALM_TO_GRIP := 0.035
const PALM_TO_SUPPORT := 0.04
## How near the trigger the index finger's tip is while the rifle is up, and how far off it
## otherwise.
const ON_TRIGGER := 0.012
const OFF_TRIGGER := 0.02
## The shares of the reload that are measured.
const RELOAD_STEP := 0.02
## How deep the left hand may pass through the rifle while it moves between its places, in
## metres: where it holds (the hand guard, the magazine) `HandContact`'s 2 mm stand.
const PASSING_DEPTH := 0.006

var _holder: Node3D
var _arena: PlayArena
var _player: Player
var _hold: TwoHandHold
var _skeleton: Skeleton3D
# One entry an update of the live player: which weapon is shown, how far each hand's bone is from
# its place on the rifle, how far the arms are on the rifle and how far each arm fell short.
var _live: Array[Dictionary] = []


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_both_hands_hold_the_rifle_in_every_locomotion_clip() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		for clip_name: StringName in CARRIED:
			for time: float in CARRIED[clip_name]:
				for aim: float in [0.0, 1.0]:
					stage.pose_rifle(clip_name, time, aim)
					await stage.settle()
					_assert_holds(stage, "%s %s at %.2f aim %.0f" % [model, clip_name, time, aim])
		stage.free()


func test_both_hands_hold_the_rifle_while_it_follows_the_view_up_and_down() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		for clip_name in PITCHED:
			for pitch in PITCHES:
				stage.pose_rifle(clip_name, 0.0, 1.0, pitch)
				await stage.settle()
				_assert_holds(stage, "%s %s pitch %.0f" % [model, clip_name, pitch])
		stage.free()


func test_the_index_finger_is_on_the_trigger_only_while_the_rifle_is_up() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		stage.pose_rifle(CharacterClips.IDLE, 0.0, 0.0)
		await stage.settle()
		var low := _tip_to_trigger(stage)
		stage.pose_rifle(CharacterClips.IDLE, 0.0, 1.0)
		await stage.settle()
		var up := _tip_to_trigger(stage)
		(
			assert_float(low)
			. override_failure_message(
				"%s: at the low ready the finger is %.1f mm from the trigger" % [model, low * 1e3]
			)
			. is_greater(OFF_TRIGGER)
		)
		(
			assert_float(up)
			. override_failure_message(
				"%s: aiming, the finger is %.1f mm from the trigger" % [model, up * 1e3]
			)
			. is_less(ON_TRIGGER)
		)
		stage.free()


# Through the reload the right hand holds as ever with its finger off the trigger, and the left
# hand is under the hand guard at the ends, round the magazine while it is in the rifle, with
# the magazine while it is out, and never deeper than `PASSING_DEPTH` in the rifle on the way.
func test_the_left_hand_takes_the_magazine_out_and_in_through_the_reload() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		var hold := stage.hold as TwoHandHold
		var magazine := hold.get_node(hold.magazine) as Node3D
		var marker := stage.rifle.get_node(^"MagazineHand") as Node3D
		var seated := 0
		# How far the hand's bone is from the magazine's origin while it holds it.
		var in_hand := marker.position.distance_to(
			stage.rifle.global_transform.affine_inverse() * magazine.global_position
		)
		var share := 0.0
		while share <= 1.0001:
			stage.pose_rifle(CharacterClips.IDLE, 0.0, 1.0, 0.0, share)
			await stage.settle()
			var tag := "%s reload at %.2f" % [model, share]
			_assert_hand(stage, "r", tag)
			var off := _tip_to_trigger(stage)
			(
				assert_float(off)
				. override_failure_message(
					"%s: the finger is %.1f mm from the trigger" % [tag, off * 1e3]
				)
				. is_greater(OFF_TRIGGER)
			)
			var gap := stage.hand_gap("l")
			(
				assert_float(gap)
				. override_failure_message("%s: the left hand is %.1f mm off" % [tag, gap * 1e3])
				. is_less(REACH)
			)
			var out := share > hold.reload_out.x + 0.001 and share < hold.reload_in.y - 0.001
			var on_magazine := (
				share > hold.reload_leave.y - 0.001 and share < hold.reload_return.x + 0.001
			)
			if share <= hold.reload_leave.x or share >= hold.reload_return.y:
				_assert_hand(stage, "l", tag)
			elif out:
				# The magazine is in the hand, away from the rifle: it goes with the hand.
				var carried := stage.bone_origin(&"hand_l").distance_to(magazine.global_position)
				(
					assert_float(carried)
					. override_failure_message(
						(
							"%s: the magazine is %.1f mm from where the hand holds it"
							% [tag, absf(carried - in_hand) * 1e3]
						)
					)
					. is_equal_approx(in_hand, 0.002)
				)
			elif on_magazine:
				seated += 1
				var at := stage.bone_origin(&"hand_l").distance_to(marker.global_position)
				(
					assert_float(at)
					. override_failure_message(
						"%s: the left hand is %.1f mm from the magazine" % [tag, at * 1e3]
					)
					. is_less(REACH)
				)
				var fails := HandContact.failures(
					tag + " l:", stage.contact.measure("l"), RifleStage.RIFLE_MAGAZINE_CONTACTS
				)
				assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
			else:
				var parts := stage.contact.measure("l")
				for part: String in parts:
					var depth: float = -parts[part].distance
					(
						assert_float(depth)
						. override_failure_message(
							"%s l: %s %.1f mm inside on the way" % [tag, part, depth * 1e3]
						)
						. is_less(PASSING_DEPTH)
					)
			share += RELOAD_STEP
		assert_int(seated).override_failure_message("never on the magazine").is_greater(1)
		stage.free()


# The player's own scene: with the rifle out, both hands are on it on every update while the
# character stands, walks, sprints, aims, fires, crouches and walks crouched, and through the
# changes between them (a hand that trailed the rifle by a frame would show here).
func test_the_player_keeps_both_hands_on_the_rifle_in_every_state() -> void:
	await _player_with_the_rifle()
	assert_int(_hold.modifiers().size()).is_equal(5)
	_skeleton.skeleton_updated.connect(_read_live)
	var steps: Array[Callable] = [
		func() -> void: pass,
		func() -> void: InputSim.key(KEY_W, true),
		func() -> void: InputSim.key(KEY_SHIFT, true),
		func() -> void: InputSim.key(KEY_SHIFT, false),
		func() -> void: InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true),
		func() -> void: InputSim.mouse_button(MOUSE_BUTTON_LEFT, true),
		func() -> void: InputSim.release_all(),
		func() -> void: _tap(KEY_C),
		func() -> void: InputSim.key(KEY_W, true),
		func() -> void: InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true),
		func() -> void: InputSim.release_all(),
		func() -> void: _tap(KEY_C),
	]
	for step in steps:
		step.call()
		await InputSim.ticks(get_tree(), 40)
	_skeleton.skeleton_updated.disconnect(_read_live)
	assert_int(_live.size()).is_greater(200)
	for entry in _live:
		assert_bool(entry.rifle).is_true()
		_assert_entry_holds(entry)
	assert_int(_player.weapon.ammo).is_less(30)


# R starts the rifle's reload: the left hand leaves the hand guard, is on the magazine's marker
# on its way out and in, and is back under the hand guard at the end, with the magazine back in
# the rifle; the right hand never leaves the grip.
func test_the_players_left_hand_leaves_the_rifle_only_for_the_reload() -> void:
	await _player_with_the_rifle()
	_player.weapon.set_ammo(3, 60)
	var left := _hold.find_child("LeftHandTarget", true, false) as Node3D
	var marker := _hold.find_child("MagazineHand", true, false) as Node3D
	var magazine := _hold.get_node(_hold.magazine) as Node3D
	var rest := left.transform
	var magazine_rest := magazine.transform
	_skeleton.skeleton_updated.connect(_read_live)
	_tap(KEY_R)
	var farthest := 0.0
	var nearest_magazine := 1.0
	for _tick in roundi(_player.weapon.definition.reload_time * 60.0) + 30:
		await InputSim.ticks(get_tree(), 1)
		farthest = maxf(farthest, left.transform.origin.distance_to(rest.origin))
		if _player.weapon.is_reloading():
			nearest_magazine = minf(
				nearest_magazine, left.transform.origin.distance_to(marker.transform.origin)
			)
	_skeleton.skeleton_updated.disconnect(_read_live)
	assert_float(farthest).override_failure_message("the hand never left").is_greater(0.2)
	assert_float(nearest_magazine).override_failure_message("never at the magazine").is_less(0.002)
	assert_int(_player.weapon.ammo).is_equal(30)
	assert_bool(left.transform.is_equal_approx(rest)).is_true()
	assert_bool(magazine.transform.is_equal_approx(magazine_rest)).is_true()
	assert_bool(magazine.visible).is_true()
	for entry in _live:
		(
			assert_float(entry.right)
			. override_failure_message("the right hand was %.1f mm off" % (entry.right * 1e3))
			. is_less(REACH)
		)
		assert_float(entry.left).is_less(REACH)


# A switch to the pistol and back, read on every update: one weapon is shown at a time and never
# none, the rifle is never shown without both hands on it, the arms leave its places only after
# it is hidden and are on them before it is shown.
func test_a_switch_never_shows_two_weapons_or_the_rifle_without_the_hands() -> void:
	await _player_with_the_rifle()
	var rifle_slot := _player.loadout.held_slot()
	_skeleton.skeleton_updated.connect(_read_live)
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.select(0)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")
	_player.loadout.select(rifle_slot)
	await InputSim.ticks(get_tree(), 60)
	_skeleton.skeleton_updated.disconnect(_read_live)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	var hidden_at := -1
	var shown_at := -1
	for index in _live.size():
		var entry := _live[index]
		(
			assert_bool(entry.rifle != entry.pistol)
			. override_failure_message(
				"update %d: rifle shown %s, pistol shown %s" % [index, entry.rifle, entry.pistol]
			)
			. is_true()
		)
		if entry.rifle:
			_assert_entry_holds(entry, "update %d" % index)
		if index > 0 and _live[index - 1].rifle and not entry.rifle:
			hidden_at = index
		if index > 0 and not _live[index - 1].rifle and entry.rifle:
			shown_at = index
	assert_int(hidden_at).override_failure_message("the rifle was never hidden").is_greater(0)
	assert_int(shown_at).override_failure_message("the rifle never came back").is_greater(hidden_at)
	# The arms are still on the rifle's places in the update that hides it, and leave after.
	assert_float(_live[hidden_at].reach).is_greater(0.8)
	var least := 1.0
	for index in range(hidden_at, shown_at):
		least = minf(least, _live[index].reach)
	assert_float(least).override_failure_message("the arms never left the rifle").is_equal(0.0)
	# They are back on its places before it is shown.
	assert_float(_live[shown_at - 1].reach).is_greater(0.8)
	assert_float(_live[shown_at - 1].right).is_less(0.03)
	assert_float(_live[shown_at - 1].left).is_less(0.03)
	# With the pistol out and the switch over, the hold lets the arms be.
	for modifier in _hold.modifiers():
		assert_bool(modifier.active).is_true()
	_player.loadout.select(0)
	await InputSim.ticks(get_tree(), 60)
	for modifier in _hold.modifiers():
		assert_bool(modifier.active).is_false()


# A player in an arena with the rifle given, drawn and at the low ready.
func _player_with_the_rifle() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	_hold = _player.model.get_node("RifleHeld") as TwoHandHold
	_skeleton = _player.model.skeleton()
	_live.clear()
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	assert_bool(_player.loadout.is_switching()).is_false()


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(key, false)


func _read_live() -> void:
	var entry := {
		"rifle": _hold.is_visible_in_tree(),
		"pistol": (_player.model.get_node("PistolHeld") as Node3D).is_visible_in_tree(),
		"reach": _hold.reach_amount(),
		"short": _hold.shortfall(),
	}
	for side: String in ["r", "l"]:
		var target := (
			_hold.find_child("RightHandTarget" if side == "r" else "LeftHandTarget", true, false)
			as Node3D
		)
		var hand := (
			_skeleton.global_transform
			* _skeleton.get_bone_global_pose(_skeleton.find_bone("hand_" + side))
		)
		entry["right" if side == "r" else "left"] = hand.origin.distance_to(target.global_position)
	_live.append(entry)


func _assert_entry_holds(entry: Dictionary, tag := "") -> void:
	(
		assert_float(entry.right)
		. override_failure_message("%s the right hand was %.1f mm off" % [tag, entry.right * 1e3])
		. is_less(REACH)
	)
	(
		assert_float(entry.left)
		. override_failure_message("%s the left hand was %.1f mm off" % [tag, entry.left * 1e3])
		. is_less(REACH)
	)


# Both hands on the rifle in the pose `settle()` waited for.
func _assert_holds(stage: RifleStage, tag: String) -> void:
	_assert_hand(stage, "r", tag)
	_assert_hand(stage, "l", tag)


# One hand: its bone on its place, its palm on its socket, its skin within the limits.
func _assert_hand(stage: RifleStage, side: String, tag: String) -> void:
	var gap := stage.hand_gap(side)
	(
		assert_float(gap)
		. override_failure_message("%s: hand_%s is %.1f mm from its place" % [tag, side, gap * 1e3])
		. is_less(REACH)
	)
	var socket := (
		stage.rifle.find_child("Grip" if side == "r" else "Support", true, false) as Node3D
	)
	var palm := stage.contact.part_distance_to(side, "palm", socket.global_position)
	(
		assert_float(palm)
		. override_failure_message(
			"%s: the palm of hand_%s is %.1f mm from %s" % [tag, side, palm * 1e3, socket.name]
		)
		. is_less(PALM_TO_GRIP if side == "r" else PALM_TO_SUPPORT)
	)
	var contacts := (
		RifleStage.RIFLE_RIGHT_CONTACTS if side == "r" else RifleStage.RIFLE_LEFT_CONTACTS
	)
	var fails := HandContact.failures("%s %s:" % [tag, side], stage.contact.measure(side), contacts)
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()


func _tip_to_trigger(stage: RifleStage) -> float:
	var trigger := stage.rifle.find_child("Trigger", true, false) as Node3D
	return stage.contact.part_distance_to("r", "index_tip", trigger.global_position)
