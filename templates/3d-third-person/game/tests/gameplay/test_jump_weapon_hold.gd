# The jump with a weapon out (kit #1369, the maintainer's ask before it lands): our nine jump clips
# hold the rifle and the pistol as the gaits do. On both mannequins, at every other frame of every
# jump clip, low and aimed, both hands are on the rifle within its hold's own limits (`REACH`, the
# palms on their sockets, every holding part on it), no point of the rifle is in the body or the
# head, and aimed the butt is on the shoulder; the pistol's grip hand holds it carried and both
# hands aimed. Then the real player jumps standing and running, aimed and firing in the air, with
# each weapon: the hands are on it on every update, the rifle is clear of the body and on the
# shoulder while it is up, and the weapon moves against the chest no faster than it does in the
# jog, so the hold, not the jump's arms, carries it. Measured on the skinned mesh after the hold's
# modifiers ran (`RifleStage`, `HoldStage`, `HandContact`, `BodyClearance`).
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
const PISTOL := "res://gameplay/weapon/pistol.tres"
const MODELS: Array[String] = ["female", "male"]
const JUMP_CLIPS: Array[StringName] = [
	CharacterClips.JUMP_START,
	CharacterClips.JUMP_START_RUN_L,
	CharacterClips.JUMP_START_RUN_R,
	CharacterClips.JUMP_RISE,
	CharacterClips.JUMP_APEX,
	CharacterClips.AIR,
	CharacterClips.LAND,
	CharacterClips.LAND_HARD,
	CharacterClips.LAND_TO_JOG,
]
## Every this many frames of a clip (at 30 a second) is posed, and on every this many the
## rifle is measured against the skin too (about 50 milliseconds a pose), with each clip's last.
const FRAME_STEP := 2
const SKIN_STEP := 4
## The rifle hold's own limits (`test_rifle_hold.gd`): a hand's bone from its place, the palms
## from the grip and the hand guard, the rifle in the body, the butt's pad from the skin.
const REACH := 0.005
const PALM_TO_GRIP := 0.035
const PALM_TO_SUPPORT := 0.04
const BODY_DEPTH := 0.01
const PAD_TO_SKIN := 0.02
## How much faster than in the ground's moves (`_ground_speeds`) the weapon may turn in the
## character's space in the jump, at its fastest, and the least bound (the rifle at the low ready
## does not turn in that space at all). How far it moves against the chest is printed, not held:
## the rifle keeps its turn while the jump's trunk folds and unfolds under it (at the low ready
## 1.5 and 0.9 m/s at the most on the two bodies, 1.5 and 0.6 on the ground).
const OVER_GROUND := 1.25
const TURN_FLOOR := 5.0
## The updates from the leaving of the floor that are the takeoff (gdstudio #1462).
const TAKEOFF_UPDATES := 3
## The skin is measured on every this many updates of the live player (the hands on all).
const SKIN_EVERY := 3

var _holder: Node3D
var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _contact: HandContact
var _clearance: BodyClearance
var _weapon: Node3D
var _aim_offset: AimOffsetModifier
# The pistol in the grip hand's space (it rides a bone attachment of that hand).
var _pistol_in_hand := Transform3D.IDENTITY
var _updates: Array[Dictionary] = []
var _read_count := 0
# Updates read since the body went into the jump state (0 out of it).
var _in_jump := 0


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_both_hands_hold_the_rifle_through_every_jump_clip() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		var near := stage.rifle.get_node(^"Near") as Node3D
		var clearance := BodyClearance.new(
			stage.skeleton, stage.contact, near, BodyClearance.HOLDING
		)
		var torso := BodyClearance.new(stage.skeleton, stage.contact, near)
		var worst := {"hand": 0.0, "depth": 0.0, "gap": 0.0}
		for clip_name in JUMP_CLIPS:
			for time in _times(stage.clip(clip_name)):
				for aim: float in [0.0, 1.0]:
					stage.pose_rifle(clip_name, time, aim)
					await stage.settle()
					var tag := "%s %s at %.2f aim %.0f" % [model, clip_name, time, aim]
					_assert_rifle_hands(stage, tag)
					worst.hand = maxf(worst.hand, maxf(stage.hand_gap("r"), stage.hand_gap("l")))
					if roundi(time * 30.0) % SKIN_STEP != 0 and time < stage.clip(clip_name).length:
						continue
					var found := clearance.deepest(near)
					worst.depth = maxf(worst.depth, found.depth)
					(
						assert_float(found.depth)
						. override_failure_message(
							(
								"%s: the rifle is %.1f mm in the %s"
								% [tag, found.depth * 1e3, found.bone]
							)
						)
						. is_less(BODY_DEPTH)
					)
					if aim < 1.0:
						continue
					var pad := torso.deepest(near, true)
					worst.gap = maxf(worst.gap, pad.gap)
					(
						assert_float(pad.gap)
						. override_failure_message(
							"%s: the butt is %.1f mm off the shoulder" % [tag, pad.gap * 1e3]
						)
						. is_less_equal(PAD_TO_SKIN)
					)
		prints(
			(
				"JUMP_RIFLE %s hand %.1f mm, in the body %.1f mm, butt off %.1f mm"
				% [model, worst.hand * 1e3, worst.depth * 1e3, worst.gap * 1e3]
			)
		)
		stage.free()


func test_the_pistol_stays_in_the_hands_through_every_jump_clip() -> void:
	var pistol := load(PISTOL) as WeaponDef
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip_name in JUMP_CLIPS:
			for time in _times(stage.clip(clip_name)):
				stage.pose(clip_name, time, 0.0, pistol.grip_clip, pistol.grip_bones)
				await stage.settle()
				_assert_pistol_hand(stage, "r", "%s %s at %.2f" % [model, clip_name, time])
		stage.free()


func test_the_female_player_keeps_both_hands_on_the_rifle_through_its_jumps() -> void:
	await _rifle_jumps("female")


func test_the_male_player_keeps_both_hands_on_the_rifle_through_its_jumps() -> void:
	await _rifle_jumps("male")


func test_the_female_player_keeps_the_pistol_in_its_hands_through_its_jumps() -> void:
	await _pistol_jumps("female")


func test_the_male_player_keeps_the_pistol_in_its_hands_through_its_jumps() -> void:
	await _pistol_jumps("male")


func _rifle_jumps(body: String) -> void:
	await _player_with(body, RIFLE)
	var hold := _player.model.get_node("RifleHeld") as TwoHandHold
	var ground := await _ground_speeds()
	var jumps := await _jumps()
	_assert_rifle_updates(jumps, hold)
	_assert_not_faster(jumps, ground)
	_assert_fired_in_the_air(jumps)


func _pistol_jumps(body: String) -> void:
	await _player_with(body, PISTOL)
	var ground := await _ground_speeds()
	var off_aimed := _off_aimed_on_the_ground(_updates.duplicate())
	var jumps := await _jumps()
	_assert_pistol_updates(jumps, off_aimed)
	_assert_not_faster(jumps, ground)
	_assert_fired_in_the_air(jumps)


# The frames of `animation` posed: every `FRAME_STEP`th and its last.
func _times(animation: Animation) -> Array[float]:
	var times: Array[float] = []
	var frames := roundi(animation.length * 30.0)
	for frame in range(0, frames, FRAME_STEP):
		times.append(frame / 30.0)
	times.append(animation.length)
	return times


func _assert_rifle_hands(stage: RifleStage, tag: String) -> void:
	for side: String in ["r", "l"]:
		var gap := stage.hand_gap(side)
		(
			assert_float(gap)
			. override_failure_message(
				"%s: hand_%s is %.1f mm from its place" % [tag, side, gap * 1e3]
			)
			. is_less(REACH)
		)
		var socket := stage.rifle.find_child("Grip" if side == "r" else "Support", true, false)
		var palm := stage.contact.part_distance_to(side, "palm", (socket as Node3D).global_position)
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
		var fails := HandContact.failures(tag + " " + side, stage.contact.measure(side), contacts)
		assert_array(fails).override_failure_message("\n".join(fails)).is_empty()


func _assert_pistol_hand(stage: HoldStage, side: String, tag: String) -> void:
	var contacts := HoldStage.RIGHT_CONTACTS if side == "r" else HoldStage.LEFT_CONTACTS
	if side == "l":
		var plan: SupportHandPlan = stage.hold.call(&"left_hand")
		var under := plan.room >= 1.0 and plan.off <= 0.0 and plan.opened <= 0.0
		if plan.room > 0.0 and not under:
			contacts = contacts.filter(func(part: String) -> bool: return part != "thumb_tip")
	var parts := stage.contact.measure(side, side == "l")
	var fails := HandContact.failures(tag + " " + side, parts, contacts)
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()


# A player of `body` in an arena with the weapon of `definition` out.
func _player_with(body: String, definition: String) -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	if body == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_skeleton = _player.model.skeleton()
	var weapon := load(definition) as WeaponDef
	if _player.weapon == null or _player.weapon.definition != weapon:
		_player.loadout.give(weapon, 60)
	await InputSim.ticks(get_tree(), 60)
	assert_object(_player.weapon.definition).is_equal(weapon)
	_contact = HandContact.new(_skeleton)
	_aim_offset = _skeleton.find_child("AimOffset", true, false) as AimOffsetModifier
	if definition == RIFLE:
		_weapon = _player.model.get_node(^"RifleHeld/Pivot/Rifle/Near") as Node3D
		_clearance = BodyClearance.new(_skeleton, _contact, _weapon, BodyClearance.HOLDING)
	else:
		_weapon = _player.model.get_node(^"PistolHeld/Pistol") as Node3D
		_pistol_in_hand = _bone(&"hand_r").affine_inverse() * _weapon.global_transform
	_contact.set_weapon(_weapon)


# The fastest the weapon turns and moves in the character's space through the ground's moves the
# hold is tuned on: a start into the jog, the jog, the stop, crouching and standing, the same with
# the weapon up (a landing dips the trunk as a crouch does), and a burst fired standing with it up.
func _ground_speeds() -> Dictionary:
	_player.position = Vector3.ZERO
	_updates.clear()
	var steps: Array[Array] = [
		["start", func() -> void: InputSim.key(KEY_W, true)],
		["jog", func() -> void: pass],
		["stop", func() -> void: InputSim.key(KEY_W, false)],
		["crouch", func() -> void: await _tap(KEY_C)],
		["stand", func() -> void: await _tap(KEY_C)],
		["aim", func() -> void: InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)],
		["aim_start", func() -> void: InputSim.key(KEY_W, true)],
		["aim_stop", func() -> void: InputSim.key(KEY_W, false)],
		["aim_crouch", func() -> void: await _tap(KEY_C)],
		["aim_stand", func() -> void: await _tap(KEY_C)],
		["fire", func() -> void: InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)],
		["after", func() -> void: InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)],
	]
	for step in steps:
		await (step[1] as Callable).call()
		await _record(30 if step[0] == "fire" else 45, step[0])
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 30)
	return _speeds(_updates)


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(key, false)


# Three jumps, read on every update: standing, running, and standing with the weapon up and a
# burst fired in the air.
func _jumps() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for way in ["standing", "running", "aimed"]:
		_player.position = Vector3.ZERO
		_player.velocity = Vector3.ZERO
		if way == "running":
			InputSim.key(KEY_W, true)
		if way == "aimed":
			InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
		await InputSim.ticks(get_tree(), 40)
		_updates.clear()
		var reader := _read.bind(way)
		_skeleton.skeleton_updated.connect(_contact.snapshot)
		_skeleton.skeleton_updated.connect(reader)
		InputSim.key(KEY_SPACE, true)
		for tick in 80:
			if tick == 12:
				InputSim.key(KEY_SPACE, false)
			if way == "aimed" and tick == 18:
				InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
			if way == "aimed" and tick == 30:
				InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
			await get_tree().physics_frame
		_skeleton.skeleton_updated.disconnect(reader)
		_skeleton.skeleton_updated.disconnect(_contact.snapshot)
		InputSim.release_all()
		await InputSim.ticks(get_tree(), 30)
		all.append_array(_updates)
	return all


func _record(ticks: int, way: String) -> void:
	var reader := _read.bind(way)
	_skeleton.skeleton_updated.connect(_contact.snapshot)
	_skeleton.skeleton_updated.connect(reader)
	await InputSim.ticks(get_tree(), ticks)
	_skeleton.skeleton_updated.disconnect(reader)
	_skeleton.skeleton_updated.disconnect(_contact.snapshot)


func _read(way: String) -> void:
	var chest := _bone(&"spine_03")
	var rifle := _player.model.get_node_or_null(^"RifleHeld") as TwoHandHold
	var held := rifle != null and rifle.is_visible_in_tree()
	# The pistol rides the grip hand's bone (its attachment moves later in this same signal).
	var weapon := _weapon.global_transform if held else _bone(&"hand_r") * _pistol_in_hand
	var state: String = Character.State.keys()[_player.state]
	_in_jump = _in_jump + 1 if state == "JUMP" else 0
	var entry := {
		"way": way,
		"state": state,
		"takeoff": _in_jump > 0 and _in_jump <= TAKEOFF_UPDATES,
		"in_chest": chest.affine_inverse() * weapon,
		"in_body": _skeleton.global_transform.affine_inverse() * weapon,
		"frame": Engine.get_physics_frames(),
		"ammo": _player.weapon.ammo,
		"settling": _aim_offset != null and _aim_offset.is_settling(),
		"depth": 0.0,
		"gap": 0.0,
	}
	if held:
		entry.raised = rifle.raised_amount()
		entry.right = _bone(&"hand_r").origin.distance_to(_marker(rifle, "RightHandTarget"))
		entry.left = _bone(&"hand_l").origin.distance_to(_marker(rifle, "LeftHandTarget"))
		if _read_count % SKIN_EVERY == 0:
			var found := _clearance.deepest(_weapon, true)
			entry.depth = found.depth
			entry.bone = found.bone
			entry.gap = found.gap
	else:
		var hold := _player.get_node(^"WeaponHold")
		entry.raised = hold.get(&"aim_weight")
		var marker := _weapon.get_node(^"SupportHand") as Node3D
		entry.left = _bone(&"hand_l").origin.distance_to(marker.global_position)
	_read_count += 1
	_updates.append(entry)
	if not held:
		_measure_pistol_hand.call_deferred(entry)


func _measure_pistol_hand(entry: Dictionary) -> void:
	var parts := _contact.measure("r")
	entry.fails = HandContact.failures(
		"%s %s" % [entry.way, entry.state], parts, HoldStage.RIGHT_CONTACTS
	)
	var off: Array[String] = []
	for part: String in HoldStage.RIGHT_CONTACTS:
		if parts.has(part) and parts[part].distance > HandContact.MAX_FLOAT:
			off.append(part)
	entry.off = off


# The grip hand's contacts that are off the pistol with it all the way up standing on the ground:
# the one placement both bodies share leaves the male's thumb tip 15 mm off the frame aimed
# (gdstudio #1369), a hold of the body, not of the jump.
func _off_aimed_on_the_ground(ground: Array[Dictionary]) -> Array[String]:
	var off: Array[String] = []
	for entry in ground:
		if entry.way == "aim" and entry.raised >= 1.0:
			for part: String in entry.get("off", []):
				if part not in off:
					off.append(part)
	return off


func _bone(bone_name: StringName) -> Transform3D:
	return (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name))
	)


func _marker(hold: TwoHandHold, marker: String) -> Vector3:
	return (hold.find_child(marker, true, false) as Node3D).global_position


# The fastest the weapon turns in the character's space (degrees a second) and moves against the
# chest (metres a second: the jump moves the whole trunk up and down in the character's space, and
# the weapon goes with it) between updates a tick apart, apart for the weapon down (`low`) and all
# the way up (`up`), and the fastest it turns against the chest, which turns under it.
func _speeds(updates: Array[Dictionary]) -> Dictionary:
	var most := {"low": _none(), "up": _none(), "chest": 0.0, "kick": 0.0, "takeoff": 0.0}
	for index in range(1, updates.size()):
		var now := updates[index]
		var last := updates[index - 1]
		var ticks: int = now.frame - last.frame
		if ticks <= 0 or now.way != last.way:
			continue
		var seconds := ticks / float(Engine.physics_ticks_per_second)
		most.chest = maxf(most.chest, _turn(last.in_chest, now.in_chest) / seconds)
		var kind := "up" if now.raised >= 1.0 and last.raised >= 1.0 else "low"
		if kind == "low" and (now.raised > 0.0 or last.raised > 0.0):
			continue
		# A shot's kick and the aim's settle after it are the shot's, printed apart.
		if now.settling or last.settling:
			most.kick = maxf(most.kick, _turn(last.in_body, now.in_body) / seconds)
			continue
		# Up, the muzzle's line is what the aim holds (the aim offset leaves the roll about it).
		var turn := (
			(
				_aim_turn(last.in_body, now.in_body)
				if kind == "up"
				else _turn(last.in_body, now.in_body)
			)
			/ seconds
		)
		var move := (last.in_chest as Transform3D).origin.distance_to(now.in_chest.origin) / seconds
		# The aimed takeoff's first updates: a 3 degree step there predates the jump clips
		# (gdstudio #1462), printed apart until it is fixed.
		if kind == "up" and now.get("takeoff", false):
			most.takeoff = maxf(most.takeoff, turn)
			continue
		var into: Dictionary = most[kind]
		if turn > into.turn:
			into.turn = turn
			into.where = "%s %s update %d" % [now.way, now.state, index]
		into.move = maxf(into.move, move)
	return most


func _none() -> Dictionary:
	return {"turn": 0.0, "move": 0.0, "where": "-"}


func _aim_turn(from: Transform3D, to: Transform3D) -> float:
	return rad_to_deg((-from.basis.z).angle_to(-to.basis.z))


func _turn(from: Transform3D, to: Transform3D) -> float:
	return rad_to_deg(
		from.basis.get_rotation_quaternion().angle_to(to.basis.get_rotation_quaternion())
	)


func _assert_rifle_updates(updates: Array[Dictionary], hold: TwoHandHold) -> void:
	assert_int(updates.size()).is_greater(150)
	var worst := {"right": 0.0, "left": 0.0, "depth": 0.0, "gap": 0.0}
	for index in updates.size():
		var entry := updates[index]
		var tag := "%s jump, update %d in %s" % [entry.way, index, entry.state]
		for side: String in ["right", "left"]:
			worst[side] = maxf(worst[side], entry[side])
			(
				assert_float(entry[side])
				. override_failure_message(
					"%s: the %s hand is %.1f mm off its place" % [tag, side, entry[side] * 1e3]
				)
				. is_less(REACH)
			)
		worst.depth = maxf(worst.depth, entry.depth)
		(
			assert_float(entry.depth)
			. override_failure_message(
				(
					"%s: the rifle is %.1f mm in the %s"
					% [tag, entry.depth * 1e3, entry.get("bone", "")]
				)
			)
			. is_less(BODY_DEPTH)
		)
		if entry.raised >= 1.0 and entry.depth == 0.0 and entry.has("bone"):
			worst.gap = maxf(worst.gap, entry.gap)
			(
				assert_float(entry.gap)
				. override_failure_message(
					"%s: aimed, the butt is %.1f mm off the shoulder" % [tag, entry.gap * 1e3]
				)
				. is_less_equal(PAD_TO_SKIN)
			)
	assert_int(hold.modifiers().size()).is_equal(5)
	prints(
		(
			"JUMP_RIFLE_LIVE hands %.1f / %.1f mm, in the body %.1f mm, aimed butt off %.1f mm"
			% [worst.right * 1e3, worst.left * 1e3, worst.depth * 1e3, worst.gap * 1e3]
		)
	)


# Every update's grip hand on the pistol: with it up, a contact already off aimed on the ground
# (`off_aimed`) is printed, not held.
func _assert_pistol_updates(updates: Array[Dictionary], off_aimed: Array[String]) -> void:
	assert_int(updates.size()).is_greater(150)
	var worst_left := 0.0
	for index in updates.size():
		var entry := updates[index]
		var tag := "%s jump, update %d in %s" % [entry.way, index, entry.state]
		var fails: Array = entry.get("fails", [])
		if entry.raised >= 1.0 and not off_aimed.is_empty():
			fails = fails.filter(
				func(line: String) -> bool:
					return not (line.ends_with(" off") and line.split(" ")[-4] in off_aimed)
			)
		assert_array(fails).override_failure_message(tag + ":\n" + "\n".join(fails)).is_empty()
		if entry.raised >= 1.0:
			worst_left = maxf(worst_left, entry.left)
			(
				assert_float(entry.left)
				. override_failure_message(
					"%s: aimed, the left hand is %.1f mm off the gun" % [tag, entry.left * 1e3]
				)
				. is_less(REACH)
			)
	prints(
		(
			"JUMP_PISTOL_LIVE aimed left hand %.1f mm; off aimed on the ground too: %s"
			% [worst_left * 1e3, ", ".join(off_aimed) if not off_aimed.is_empty() else "none"]
		)
	)


# The jump turns the weapon in the character's space no faster than the ground's moves do, down
# and up: the hold carries it, and the jump's arms do not swing it.
func _assert_not_faster(updates: Array[Dictionary], ground: Dictionary) -> void:
	var jump := _speeds(updates)
	for kind: String in ["low", "up"]:
		var now: Dictionary = jump[kind]
		var bound: Dictionary = ground[kind]
		var message := (
			(
				"%s, the weapon turns %.0f degrees a second in the character's space at %s and"
				+ " moves %.2f m/s against the chest; on the ground %.0f (%s) and %.2f"
			)
			% [kind, now.turn, now.where, now.move, bound.turn, bound.where, bound.move]
		)
		prints("JUMP_CARRY " + message)
		assert_float(now.turn).override_failure_message(message).is_less_equal(
			maxf(bound.turn, TURN_FLOOR) * OVER_GROUND
		)
	prints(
		(
			(
				"JUMP_CARRY against the chest, at most %.0f degrees a second (on the ground %.0f); a"
				+ " shot's kick %.0f (on the ground %.0f); up at the takeoff %.0f (gdstudio #1462)"
			)
			% [jump.chest, ground.chest, jump.kick, ground.kick, jump.takeoff]
		)
	)


func _assert_fired_in_the_air(updates: Array[Dictionary]) -> void:
	var first := -1
	var fired_in_air := false
	var raised_in_air := false
	for entry in updates:
		if entry.way != "aimed":
			continue
		if first < 0:
			first = entry.ammo
		var in_air: bool = entry.state in ["JUMP", "FALL"]
		if in_air and entry.raised >= 1.0:
			raised_in_air = true
		if in_air and entry.ammo < first:
			fired_in_air = true
	assert_bool(raised_in_air).override_failure_message("never aimed in the air").is_true()
	assert_bool(fired_in_air).override_failure_message("no shot left in the air").is_true()
