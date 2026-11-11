# The hands hold the pistol (kit #1001): in every pistol clip and in the locomotion clips with the
# pistol out, on both mannequins, no skin of the right hand is more than 2 mm inside the gun and
# no holding part more than 5 mm off it; while aiming and shooting the left hand lies on the gun
# and over the right hand within the same limits, its arm reaching the support marker. Through
# the reload (kit #1031) the right hand holds as ever and the left hand is on the gun, away with
# the clip's arm for the new magazine, under the magazine while it goes in and on the gun again,
# never more than 2 mm inside the gun or the other hand on the way, at every hundredth of the clip
# while it moves (kit #1051). Measured on the skinned mesh after the hold's modifiers ran
# (`HoldStage`, `HandContact`).
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
## The clips that hold the pistol in one hand, with the times sampled.
const ONE_HANDED: Dictionary[StringName, Array] = {
	CharacterClips.PISTOL_IDLE: [0.0, 0.5, 1.0],
}
## The shares of the reload clip that are measured: every 2 hundredths and its end for the right
## hand, which holds throughout; for the left hand every hundredth of the spans in which the hold
## moves it near the gun (letting go, coming under the magazine and pushing it in, going back),
## since a fingertip that passes through the other hand does it for a hundredth of the clip (kit
## #1031 measured every 4 hundredths and missed three such moments of 4 to 5 mm).
const RELOAD_STEP := 0.02
const RELOAD_MOVING_STEP := 0.01
const RELOAD_MOVING: Array[Vector2] = [Vector2(0.0, 0.12), Vector2(0.3, 0.56), Vector2(0.69, 0.92)]
## The shares of the reload in which the left hand is on the gun (to the first, from the second)
## and under the magazine (between the third and the fourth), as `Pistol_Reload` has them.
const RELOAD_ON_GUN_UNTIL := 0.02
const RELOAD_ON_GUN_FROM := 0.9
const RELOAD_MAGAZINE_FROM := 0.54
const RELOAD_MAGAZINE_UNTIL := 0.71
## The clips that hold it in both hands.
const TWO_HANDED: Dictionary[StringName, Array] = {
	CharacterClips.PISTOL_AIM: [0.0, 0.16],
	CharacterClips.PISTOL_AIM_UP: [0.0, 0.16],
	CharacterClips.PISTOL_AIM_DOWN: [0.0, 0.16],
	CharacterClips.PISTOL_SHOOT: [0.0, 0.05, 0.1, 0.2],
}
## The locomotion clips, the grip clip over the gripping hand (the hand-only carry).
const CARRIED: Dictionary[StringName, Array] = {
	CharacterClips.IDLE: [0.0, 1.0],
	CharacterClips.WALK: [0.0, 0.3, 0.6],
	CharacterClips.RUN: [0.0, 0.25, 0.5],
	CharacterClips.SPRINT: [0.0, 0.2, 0.4],
	CharacterClips.CROUCH_WALK: [0.0, 0.7],
	CharacterClips.AIR: [0.0, 0.3],
}
## The live left hand is measured while its bone is this near one of its two markers, in metres:
## farther off, no finger reaches the gun.
const LIVE_NEAR := 0.2
## The equal parts of the trigger finger's way between the frame and the trigger that are
## measured (kit #1079).
const TRIGGER_WAY_STEPS := 20
## How deep the trigger finger may graze the trigger guard between its two places, in metres: the
## mannequin's finger is as thick as the guard's opening is long (20 mm in 21), and the best way
## in the solver found passes 3.7 mm through the guard's front strut (kit #1079; the guard's
## opening is kit #GUARD_ISSUE). At its two places and against the left hand the limit is the
## usual one.
const TRIGGER_GUARD_GRAZE := 0.004
## How far the left hand's bone may stop from its marker, in metres (a clamped arm stops short).
const REACH := 0.005
## The parts of the left hand's fingers that lie on the right hand's in a two-handed grip (kit
## #1084): each is within `HandContact.MAX_FLOAT` of the right hand's own skin, whatever else it
## touches. The index finger is the one under the trigger guard, on the gun.
const OVER_RIGHT_HAND: Array[String] = [
	"middle_mid", "middle_tip", "ring_mid", "ring_tip", "pinky_mid", "pinky_tip"
]
## How far the left hand is canted, in degrees: its knuckle line (index to little finger) from
## the gun's own down toward its back. A hand held like the right one mirrored is at 0 to 16; a
## support hand is taught at about 45, the wrist bent forward so that the thumb points ahead.
const CANT := Vector2(25.0, 50.0)
## How far ahead of the right thumb's last bone the left one's is, along the barrel, at least.
const THUMB_AHEAD := 0.03
## How near the trigger the index finger's tip is while aiming, and how far off it otherwise.
const ON_TRIGGER := 0.012
const OFF_TRIGGER := 0.02

var _holder: Node3D
var _live_skeleton: Skeleton3D
var _live_marker: Node3D
var _live_gaps: Array[float] = []
var _live_hold: Node
var _live_magazine: Node3D
# One entry an update of a live reload: the reload's share, the hold's two weights, and how far
# the left hand is from the support marker and from the magazine marker.
var _live_reload: Array[Dictionary] = []
var _live_contact: HandContact
# The deepest the live left hand was in the gun or the right hand, in metres, what was playing
# then, and how many updates were measured.
var _live_deepest := 0.0
var _live_deepest_at := ""
var _live_measured := 0


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func after_test() -> void:
	InputSim.release_all()


func test_the_right_hand_holds_the_pistol_in_the_one_handed_clips() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip_name: StringName in ONE_HANDED:
			for time: float in ONE_HANDED[clip_name]:
				stage.pose(clip_name, time)
				await stage.settle()
				_assert_holds(stage, "r", "%s %s at %.2f" % [model, clip_name, time])
		stage.free()


func test_both_hands_hold_the_pistol_in_the_aim_and_shoot_clips() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip_name: StringName in TWO_HANDED:
			for time: float in TWO_HANDED[clip_name]:
				stage.pose(clip_name, time, 1.0)
				await stage.settle()
				var tag := "%s %s at %.2f" % [model, clip_name, time]
				_assert_holds(stage, "r", tag, true)
				_assert_holds(stage, "l", tag)
				(
					assert_float(_reach(stage))
					. override_failure_message(
						"%s: the left hand is %.1f mm from its marker" % [tag, _reach(stage) * 1e3]
					)
					. is_less(REACH)
				)
		stage.free()


func test_the_right_hand_holds_the_pistol_through_the_reload() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for share in _reload_shares():
			_pose_reload(stage, share, 1.0)
			await stage.settle()
			_assert_holds(stage, "r", "%s reload at %.2f" % [model, share], true)
			var off := _tip_to_trigger(stage)
			(
				assert_float(off)
				. override_failure_message(
					(
						"%s reload at %.2f: the finger is %.1f mm from the trigger"
						% [model, share, off * 1e3]
					)
				)
				. is_greater(OFF_TRIGGER)
			)
		stage.free()


# The two hands hold the pistol together as a two-handed grip is taught (kit #1084; the research
# is the kit's docs, tools/blender/weapon-hands/two-handed-pistol-grip.md), in every aim and shoot
# clip on both mannequins: the left hand canted, its fingers over the right hand's fingers and
# round the front of the grip, its index finger on the gun under the trigger guard, its palm on
# the right hand's fingertips, its thumb forward along the frame ahead of the right one, and the
# right thumb resting on the left hand. Each contact is within the limit the gun's are.
func test_the_two_hands_hold_the_pistol_together() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip_name: StringName in TWO_HANDED:
			stage.pose(clip_name, TWO_HANDED[clip_name][0], 1.0)
			await stage.settle()
			var tag := "%s %s" % [model, clip_name]
			var left := stage.contact.measure("l", true)
			var right := stage.contact.measure("r", true)
			var fails: Array[String] = []
			for part in OVER_RIGHT_HAND:
				if left[part].hand > HandContact.MAX_FLOAT:
					fails.append(
						"the left %s is %.1f mm off the right hand" % [part, left[part].hand * 1e3]
					)
			var under_guard := minf(left.index_base.gun, left.index_mid.gun)
			if under_guard > HandContact.MAX_FLOAT:
				fails.append("the left index finger is %.1f mm off the gun" % (under_guard * 1e3))
			if left.index_tip.hand > HandContact.MAX_FLOAT:
				fails.append(
					"the left index_tip is %.1f mm off the right hand" % (left.index_tip.hand * 1e3)
				)
			# The palm lies on the right hand's fingertips, which cover the grip's panel there.
			if left.palm.hand > HandContact.MAX_FLOAT:
				fails.append("the left palm is %.1f mm off the right hand" % (left.palm.hand * 1e3))
			if left.thumb_tip.gun > HandContact.MAX_FLOAT:
				fails.append("the left thumb is %.1f mm off the gun" % (left.thumb_tip.gun * 1e3))
			if right.thumb_tip.hand > HandContact.MAX_FLOAT:
				fails.append(
					"the right thumb is %.1f mm off the left hand" % (right.thumb_tip.hand * 1e3)
				)
			var ahead := _in_gun(stage, &"thumb_03_r").x - _in_gun(stage, &"thumb_03_l").x
			if ahead < THUMB_AHEAD:
				fails.append("the left thumb is %.0f mm ahead of the right one" % (ahead * 1e3))
			var knuckles := _in_gun(stage, &"pinky_01_l") - _in_gun(stage, &"index_01_l")
			var cant := rad_to_deg(atan2(knuckles.x, -knuckles.y))
			if cant < CANT.x or cant > CANT.y:
				fails.append("the left hand is canted %.0f degrees" % cant)
			(
				assert_array(fails)
				. override_failure_message("%s: %s" % [tag, "; ".join(fails)])
				. is_empty()
			)
		stage.free()


# The left hand through the reload, whether the character aims or carries the pistol: on the gun
# at its ends, under the magazine while it goes in, and no deeper in the gun or the other hand on
# the way than where it holds (`HandContact.MAX_DEPTH`).
func test_the_left_hand_follows_the_reload() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for share in _left_reload_shares():
			_pose_reload(stage, share, 0.0)
			await stage.settle()
			var tag := "%s reload at %.2f" % [model, share]
			var contacts: Array[String] = []
			var marker := ^""
			if share <= RELOAD_ON_GUN_UNTIL or share >= RELOAD_ON_GUN_FROM:
				contacts = HoldStage.LEFT_CONTACTS
				marker = ^"SupportHand"
			elif share >= RELOAD_MAGAZINE_FROM and share <= RELOAD_MAGAZINE_UNTIL:
				contacts = HoldStage.MAGAZINE_CONTACTS
				marker = ^"MagazineHand"
			var parts := stage.contact.measure("l", true)
			if marker.is_empty():
				for part: String in parts:
					var depth: float = -parts[part].distance
					(
						assert_float(depth)
						. override_failure_message(
							"%s l: %s %.1f mm inside on the way" % [tag, part, depth * 1e3]
						)
						. is_less_equal(HandContact.MAX_DEPTH)
					)
				continue
			var fails := HandContact.failures(tag + " l:", parts, contacts)
			assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
			var gap := _reach(stage, marker)
			(
				assert_float(gap)
				. override_failure_message(
					"%s: the left hand is %.1f mm from %s" % [tag, gap * 1e3, marker]
				)
				. is_less(REACH)
			)
		stage.free()


func test_the_right_hand_holds_the_pistol_in_the_locomotion_clips() -> void:
	var pistol := load("res://gameplay/weapon/pistol.tres") as WeaponDef
	var bones := pistol.grip_bones
	var grip_clip := pistol.grip_clip
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip_name: StringName in CARRIED:
			for time: float in CARRIED[clip_name]:
				stage.pose(clip_name, time, 0.0, grip_clip, bones)
				await stage.settle()
				_assert_holds(stage, "r", "%s %s at %.2f" % [model, clip_name, time])
		stage.free()


func test_the_index_finger_is_on_the_trigger_only_while_aiming() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		stage.pose(CharacterClips.PISTOL_IDLE, 0.5, 0.0)
		await stage.settle()
		var carried := _tip_to_trigger(stage)
		stage.pose(CharacterClips.PISTOL_AIM, 0.16, 1.0)
		await stage.settle()
		var aiming := _tip_to_trigger(stage)
		(
			assert_float(carried)
			. override_failure_message(
				"%s: carried, the finger is %.1f mm from the trigger" % [model, carried * 1e3]
			)
			. is_greater(OFF_TRIGGER)
		)
		(
			assert_float(aiming)
			. override_failure_message(
				"%s: aiming, the finger is %.1f mm from the trigger" % [model, aiming * 1e3]
			)
			. is_less(ON_TRIGGER)
		)
		stage.free()


# The player's own scene wires the hold: carried, only the grip acts; with the aim button held the
# left hand comes to the gun and stays on it while the character walks and fires, read from the
# live skeleton on every update (a hand that trailed the gun by a frame would show here).
func test_the_player_holds_the_pistol_in_both_hands_while_it_aims_walks_and_fires() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 20)
	# Read by name and by property, so the suite also loads in a project that has no hold yet.
	var hold := player.get_node_or_null("WeaponHold")
	assert_object(hold).override_failure_message("the player has no WeaponHold").is_not_null()
	if hold == null:
		AudioDrain.stop_all(arena)
		return
	var modifiers: Array = hold.call(&"modifiers")
	assert_int(modifiers.size()).is_equal(3)
	assert_float(hold.get(&"held_weight")).is_equal(1.0)
	assert_float(hold.get(&"aim_weight")).is_equal(0.0)
	assert_bool((modifiers[0] as SkeletonModifier3D).active).is_true()
	assert_bool((modifiers[1] as SkeletonModifier3D).active).is_false()
	_live_skeleton = (player.get_node("Model") as CharacterModel).skeleton()
	_live_marker = player.get_node("Model/PistolHeld/Pistol/SupportHand") as Node3D
	_live_gaps.clear()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(hold.get(&"aim_weight")).is_equal(1.0)
	_live_skeleton.skeleton_updated.connect(_read_left_hand)
	InputSim.key(KEY_W, true)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 60)
	_live_skeleton.skeleton_updated.disconnect(_read_left_hand)
	assert_int(_live_gaps.size()).is_greater(20)
	var worst := 0.0
	for gap in _live_gaps:
		worst = maxf(worst, gap)
	(
		assert_float(worst)
		. override_failure_message("the left hand was %.1f mm from the gun" % (worst * 1e3))
		. is_less(REACH)
	)
	assert_float(hold.call(&"support_shortfall")).is_equal_approx(0.0, 0.0005)
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 40)
	assert_float(hold.get(&"aim_weight")).is_equal(0.0)
	AudioDrain.stop_all(arena)


# The player's own reload while it aims: R starts it, the left hand lets go of the gun for the
# clip's reach to the belt, is at the pistol's magazine marker on every update while the clip
# pushes the magazine in, and is on the support marker again for the clip's end.
func test_the_players_left_hand_goes_to_the_magazine_and_back_when_it_reloads() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 20)
	_live_hold = player.get_node_or_null("WeaponHold")
	assert_object(_live_hold).is_not_null()
	_live_magazine = player.get_node_or_null("Model/PistolHeld/Pistol/MagazineHand") as Node3D
	assert_object(_live_magazine).override_failure_message("no MagazineHand marker").is_not_null()
	if _live_hold == null or _live_magazine == null or not &"reload_share" in _live_hold:
		assert_bool(false).override_failure_message("the hold knows no reload").is_true()
		AudioDrain.stop_all(arena)
		return
	_live_skeleton = (player.get_node("Model") as CharacterModel).skeleton()
	_live_marker = player.get_node("Model/PistolHeld/Pistol/SupportHand") as Node3D
	_live_reload.clear()
	player.weapon.set_ammo(3, 24)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	_live_skeleton.skeleton_updated.connect(_read_reload)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	await InputSim.ticks(get_tree(), roundi(player.weapon.definition.reload_time * 60.0) + 40)
	_live_skeleton.skeleton_updated.disconnect(_read_reload)
	await InputSim.ticks(get_tree(), 2)
	var seated := 0
	var back := 0
	var away := 0
	var worst_seated := 0.0
	var worst_back := 0.0
	for entry in _live_reload:
		var weights: Vector2 = entry.weights
		var share: float = entry.share
		if share > RELOAD_MAGAZINE_FROM + 0.01 and share < RELOAD_MAGAZINE_UNTIL - 0.01:
			seated += 1
			worst_seated = maxf(worst_seated, entry.magazine)
		elif share > RELOAD_ON_GUN_FROM:
			back += 1
			worst_back = maxf(worst_back, entry.support)
		elif weights.x + weights.y < 0.001 and share > 0.1 and share < 0.3:
			away += 1
	assert_int(seated).override_failure_message("never under the magazine").is_greater(5)
	assert_int(back).override_failure_message("never back on the gun").is_greater(2)
	assert_int(away).override_failure_message("never away for the magazine").is_greater(5)
	(
		assert_float(worst_seated)
		. override_failure_message("%.1f mm from the magazine marker" % (worst_seated * 1e3))
		. is_less(REACH)
	)
	(
		assert_float(worst_back)
		. override_failure_message("%.1f mm from the support marker" % (worst_back * 1e3))
		. is_less(REACH)
	)
	assert_int(player.weapon.ammo).is_equal(12)
	assert_float(_live_hold.get(&"reload_weight")).is_equal(0.0)
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 40)
	assert_bool((_live_hold.call(&"modifiers")[1] as SkeletonModifier3D).active).is_false()
	AudioDrain.stop_all(arena)


# The reload in the player's own scene while it aims, measured on every update the left hand is
# near the gun: it lets go while the clip still fades in over the aim pose, comes back from the
# magazine, and never passes deeper through the gun or the right hand than where it holds (kit
# #1051: the posed stage knows no fade), its thumb's tip included while the reload fades and the
# right trigger finger leaves the trigger beside it (kit #1079).
func test_the_players_left_hand_passes_through_nothing_as_it_reloads_while_aiming() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 20)
	_live_hold = player.get_node_or_null("WeaponHold")
	assert_object(_live_hold).is_not_null()
	if _live_hold == null:
		AudioDrain.stop_all(arena)
		return
	_live_skeleton = (player.get_node("Model") as CharacterModel).skeleton()
	_live_marker = player.get_node("Model/PistolHeld/Pistol/SupportHand") as Node3D
	_live_magazine = player.get_node("Model/PistolHeld/Pistol/MagazineHand") as Node3D
	_live_contact = HandContact.new(_live_skeleton)
	_live_contact.set_weapon(player.get_node("Model/PistolHeld/Pistol") as Node3D)
	_live_deepest = 0.0
	_live_deepest_at = ""
	_live_measured = 0
	player.weapon.set_ammo(3, 24)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_live_hold.get(&"aim_weight")).is_equal(1.0)
	_live_skeleton.skeleton_updated.connect(_read_depth)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	await InputSim.ticks(get_tree(), roundi(player.weapon.definition.reload_time * 60.0) + 30)
	_live_skeleton.skeleton_updated.disconnect(_read_depth)
	await InputSim.ticks(get_tree(), 2)
	InputSim.release_all()
	assert_int(player.weapon.ammo).is_equal(12)
	assert_int(_live_measured).override_failure_message("the hand was never measured").is_greater(
		60
	)
	(
		assert_float(_live_deepest)
		. override_failure_message(
			"the left hand passed %.1f mm deep (%s)" % [_live_deepest * 1e3, _live_deepest_at]
		)
		. is_less_equal(HandContact.MAX_DEPTH)
	)
	AudioDrain.stop_all(arena)


# The aim coming up and going down in the player's own scene (kit #1078), measured on every
# update the left hand is near the gun, on both mannequins: the body is between the carry pose
# and the aim pose then and the gun still out to the side, so the left arm is too short for the
# hand's place; it backs the hand off along its way, opened, and the hand passes no deeper
# through the gun or the right hand than where it holds.
func test_the_left_hand_passes_through_nothing_as_the_female_players_aim_comes_up() -> void:
	await _aim_up_and_down("female")


func test_the_left_hand_passes_through_nothing_as_the_male_players_aim_comes_up() -> void:
	await _aim_up_and_down("male")


# The trigger finger between the frame and the trigger (kit #1079), at every twentieth of its
# way while both hands hold the aimed pistol: neither hand is more than `HandContact.MAX_DEPTH`
# inside the other (the left thumb lies along the frame on the guard's other side, where the
# straight blend took the finger through it) or inside the gun, but for the finger's own graze of
# the trigger guard on the way (`TRIGGER_GUARD_GRAZE`). The reload's weight takes the finger off
# the trigger, as in the game.
func test_the_trigger_finger_passes_through_nothing_on_its_way_to_the_trigger() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for step in TRIGGER_WAY_STEPS + 1:
			var on_trigger := float(step) / TRIGGER_WAY_STEPS
			stage.pose(CharacterClips.PISTOL_AIM, 0.16, 1.0)
			stage.hold.set(&"reload_weight", 1.0 - on_trigger)
			stage.hold.call(&"refresh")
			await stage.settle()
			var tag := "%s, the finger %.2f on the trigger" % [model, on_trigger]
			var on_the_way := step > 0 and step < TRIGGER_WAY_STEPS
			var fails: Array[String] = []
			for side: String in ["r", "l"]:
				var parts := stage.contact.measure(side, true)
				for part: String in parts:
					var in_gun: float = -parts[part].gun
					var in_hand: float = -parts[part].hand
					var grazes := side == "r" and part.begins_with("index") and on_the_way
					if in_gun > (TRIGGER_GUARD_GRAZE if grazes else HandContact.MAX_DEPTH):
						fails.append("%s %s %.1f mm inside the gun" % [side, part, in_gun * 1e3])
					if in_hand > HandContact.MAX_DEPTH:
						fails.append(
							"%s %s %.1f mm in the other hand" % [side, part, in_hand * 1e3]
						)
			(
				assert_array(fails)
				. override_failure_message("%s: %s" % [tag, "; ".join(fails)])
				. is_empty()
			)
		stage.free()


# The measure itself works: with the hold left out the clips' own fist is found deep in the grip.
func test_the_clips_own_fist_fails_the_measure() -> void:
	var stage := HoldStage.make(_holder, "female", false)
	stage.pose(CharacterClips.PISTOL_AIM, 0.16, 1.0)
	await stage.settle()
	var right := stage.contact.measure("r")
	assert_array(HandContact.failures("r", right, HoldStage.RIGHT_CONTACTS)).is_not_empty()
	stage.free()


# Aims and lowers the pistol twice in the player's own scene with the mannequin `model`, the left
# hand's depth read on every update.
func _aim_up_and_down(model: String) -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	if model != "female":
		var old := player.model.rig()
		player.model.remove_child(old)
		old.free()
		player.model.add_child((load(HoldStage.MODELS[model]) as PackedScene).instantiate())
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 20)
	_live_hold = player.get_node_or_null("WeaponHold")
	assert_object(_live_hold).is_not_null()
	if _live_hold == null:
		AudioDrain.stop_all(arena)
		return
	_live_skeleton = (player.get_node("Model") as CharacterModel).skeleton()
	_live_marker = player.get_node("Model/PistolHeld/Pistol/SupportHand") as Node3D
	_live_magazine = player.get_node("Model/PistolHeld/Pistol/MagazineHand") as Node3D
	_live_contact = HandContact.new(_live_skeleton)
	_live_contact.set_weapon(player.get_node("Model/PistolHeld/Pistol") as Node3D)
	_live_deepest = 0.0
	_live_deepest_at = ""
	_live_measured = 0
	_live_skeleton.skeleton_updated.connect(_read_depth)
	for _round in 2:
		InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
		await InputSim.ticks(get_tree(), 30)
		assert_float(_live_hold.get(&"aim_weight")).is_equal(1.0)
		# Once the aim is up the arm reaches (read by name: a hold from before kit #1078 has none).
		if _live_hold.has_method(&"support_backed"):
			assert_float(_live_hold.call(&"support_backed")).is_equal(0.0)
		InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
		await InputSim.ticks(get_tree(), 30)
		assert_float(_live_hold.get(&"aim_weight")).is_equal(0.0)
	_live_skeleton.skeleton_updated.disconnect(_read_depth)
	await InputSim.ticks(get_tree(), 2)
	InputSim.release_all()
	assert_int(_live_measured).override_failure_message("the hand was never measured").is_greater(
		20
	)
	(
		assert_float(_live_deepest)
		. override_failure_message(
			(
				"%s: the left hand passed %.1f mm deep (%s)"
				% [model, _live_deepest * 1e3, _live_deepest_at]
			)
		)
		. is_less_equal(HandContact.MAX_DEPTH)
	)
	AudioDrain.stop_all(arena)


# The hand's bone is read in the skeleton's update; the marker rides the attachment, which moves
# in the same signal, so the two are compared once every listener ran.
func _read_left_hand() -> void:
	var bone := _live_skeleton.get_bone_global_pose(_live_skeleton.find_bone(&"hand_l"))
	_compare_with_marker.call_deferred(_live_skeleton.global_transform * bone.origin)


func _read_reload() -> void:
	var bone := _live_skeleton.get_bone_global_pose(_live_skeleton.find_bone(&"hand_l"))
	var entry := {
		"share": _live_hold.get(&"reload_share"),
		"weights": _live_hold.call(&"support_weights"),
		"hand": _live_skeleton.global_transform * bone.origin,
	}
	_compare_with_markers.call_deferred(entry)


# The live left hand's depth: the pose is copied in the skeleton's update and measured once the
# gun's attachment moved too, and only while the hand is within a hand's length of the gun.
func _read_depth() -> void:
	_live_contact.snapshot()
	var weight: float = _live_hold.get(&"reload_weight")
	var tag := (
		"aim %.2f, reload %.2f at share %.3f"
		% [_live_hold.get(&"aim_weight"), weight, _live_hold.get(&"reload_share")]
	)
	_measure_depth.call_deferred(tag)


func _measure_depth(tag: String) -> void:
	if not is_instance_valid(_live_marker) or not is_instance_valid(_live_magazine):
		return
	var hand := _live_skeleton.global_transform * _live_contact.bone_pose(&"hand_l").origin
	var gap := minf(
		hand.distance_to(_live_marker.global_position),
		hand.distance_to(_live_magazine.global_position)
	)
	if gap > LIVE_NEAR:
		return
	_live_measured += 1
	var parts := _live_contact.measure("l", true)
	for part: String in parts:
		var depth: float = -parts[part].distance
		if depth > _live_deepest:
			_live_deepest = depth
			_live_deepest_at = "%s, %s" % [part, tag]


func _compare_with_markers(entry: Dictionary) -> void:
	if is_instance_valid(_live_marker) and is_instance_valid(_live_magazine):
		entry.support = (entry.hand as Vector3).distance_to(_live_marker.global_position)
		entry.magazine = (entry.hand as Vector3).distance_to(_live_magazine.global_position)
		_live_reload.append(entry)


func _compare_with_marker(hand: Vector3) -> void:
	if is_instance_valid(_live_marker):
		_live_gaps.append(hand.distance_to(_live_marker.global_position))


# One hand holds: nothing deeper than the limit in the gun, every holding part on it. The left
# hand is measured against the right one too, and with `both` the right against the left (a
# fingertip that enters a flat face of the other hand shows only from its own side); the right
# thumb then counts as holding only while the left hand is on the gun or away from it, since it
# moves between the frame and the left thumb's root as that hand comes and goes.
func _assert_holds(stage: HoldStage, side: String, tag: String, both := false) -> void:
	var parts := stage.contact.measure(side, side == "l" or both)
	var contacts := HoldStage.RIGHT_CONTACTS if side == "r" else HoldStage.LEFT_CONTACTS
	if both and stage.hold != null:
		var on_gun: float = stage.hold.call(&"support_weights").x
		if on_gun > 0.0 and on_gun < 1.0:
			contacts = contacts.filter(func(part: String) -> bool: return part != "thumb_tip")
	var fails := HandContact.failures("%s %s:" % [tag, side], parts, contacts)
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()


# Where a bone is in the pistol's own space (the muzzle along -X, up +Y, the gun's left +Z).
func _in_gun(stage: HoldStage, bone_name: StringName) -> Vector3:
	return stage.pistol.global_transform.affine_inverse() * stage.bone_origin(bone_name)


# How far the left hand's bone is from a marker of the pistol, in metres (a pistol with no such
# marker reads as a metre off).
func _reach(stage: HoldStage, marker_path := ^"SupportHand") -> float:
	var marker := stage.pistol.get_node_or_null(marker_path) as Node3D
	if marker == null:
		return 1.0
	return stage.bone_origin(&"hand_l").distance_to(marker.global_position)


func _reload_shares() -> Array[float]:
	var shares: Array[float] = []
	for step in ceili(1.0 / RELOAD_STEP):
		shares.append(step * RELOAD_STEP)
	shares.append(1.0)
	return shares


# The shares the left hand is measured at: `_reload_shares()` and every hundredth of the spans in
# which it moves (`RELOAD_MOVING`), in order.
func _left_reload_shares() -> Array[float]:
	var hundredths := {}
	for share in _reload_shares():
		hundredths[roundi(share * 100.0)] = true
	for span in RELOAD_MOVING:
		for step in range(roundi(span.x * 100.0), roundi(span.y * 100.0) + 1):
			hundredths[step] = true
	var steps := hundredths.keys()
	steps.sort()
	var shares: Array[float] = []
	for step: int in steps:
		shares.append(step * RELOAD_MOVING_STEP)
	return shares


# Puts the reload clip at `share` of its length on the stage, the hold told it is that far in.
func _pose_reload(stage: HoldStage, share: float, aim: float) -> void:
	var length := stage.clip(CharacterClips.PISTOL_RELOAD).length
	stage.pose(CharacterClips.PISTOL_RELOAD, share * length, aim, &"", [], share)


# How far the skin of the index finger's last bone is from the trigger's front face, in metres.
func _tip_to_trigger(stage: HoldStage) -> float:
	var trigger := stage.pistol.find_child("Trigger", true, false) as Node3D
	return stage.contact.part_distance_to("r", "index_tip", trigger.global_position)
