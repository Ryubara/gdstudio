# The pistol held in one hand (kit #1085): off by default; on, the right hand holds the pistol to
# the same limits as ever across the aim's look range and the shot on both mannequins, the chest
# is turned side-on, the right arm reaches out nearly straight along the barrel's line, which
# keeps the aim clip's direction, and the left hand stays off the gun until a reload brings it
# to the magazine. A shot kicks the muzzle up at the wrist and bends the elbow. Switched in the
# running game it takes effect at once. Measured on the skinned mesh after the hold's modifiers
# ran (`HoldStage`, `HandContact`); the tree leaves the free arm on the locomotion while it aims,
# which the stage stands in for with the idle clip on the left arm.
extends GdUnitTestSuite

const Match := preload("res://tools/hold/one_hand_match.gd")
const MODELS: Array[String] = ["female", "male"]
## The aim's look range and the shot, with the times sampled.
const AIMED: Dictionary[StringName, Array] = {
	CharacterClips.PISTOL_AIM: [0.0, 0.16],
	CharacterClips.PISTOL_AIM_UP: [0.0],
	CharacterClips.PISTOL_AIM_DOWN: [0.0],
	CharacterClips.PISTOL_SHOOT: [0.0, 0.1, 0.2],
}
## The bone whose chain keeps the locomotion while one-handed.
const FREE_ARM := WeaponDef.FREE_ARM_BONE
## The left hand's bone is at least this far from the support marker while it is free, in metres.
const FREE := 0.15
## The right elbow is at least this straight, in degrees (180 locked; the default reach, 0.96 of
## the arm, is 147).
const STRAIGHT := 140.0
## How near the barrel stays to the aim clip's direction, in degrees.
const SAME_LINE := 1.0
## How far the chest turns from the two-handed hold, in degrees, at the default `side_on`.
const SIDE_ON := Vector2(28.0, 42.0)
## The right thumb's last bone points within this of the barrel while aiming one-handed, in
## degrees, and its way there is measured at this many steps of the aim.
const THUMB_ALONG := 35.0
const THUMB_STEPS := 20
## How far the muzzle may point off the aim's point on the live player, in degrees.
const AIM_MISS := 3.0
## How far the left hand's bone may stop from its marker, in metres.
const REACH := 0.005
## Both bodies hold the pistol with one finger placement, the female body's (kit #1274): each of
## these points (the last joint and the tip of every finger, the thumb's middle joint too) is
## within `PLACEMENT` of the same point of the other body, in the gun's space. That is the float a
## holding part is allowed (`HandContact.MAX_FLOAT`). The knuckles and the fingers' middle joints
## are left out: they are where the hand's size puts them (the male palm sits 8 mm farther out on
## the grip and its first finger bones are longer, 8 to 10 mm apart at the middle joints).
const PLACEMENT := 0.005
const PLACED: Array[String] = [
	"index_3",
	"index_tip",
	"middle_3",
	"middle_tip",
	"ring_3",
	"ring_tip",
	"pinky_3",
	"pinky_tip",
	"thumb_2",
	"thumb_3",
	"thumb_tip",
]

var _holder: Node3D
# The live left hand's distance from the support marker, read where the modifiers' pose is.
var _gap := 0.0


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func after_test() -> void:
	InputSim.release_all()


func test_one_handed_is_off_by_default() -> void:
	var pistol := load("res://gameplay/weapon/pistol.tres") as WeaponDef
	assert_bool(pistol.one_handed).is_false()
	var stage := HoldStage.make(_holder, "female")
	await stage.settle()
	assert_bool(stage.hold.get(&"one_handed")).is_false()
	assert_int((stage.hold.call(&"modifiers") as Array).size()).is_equal(3)
	stage.free()


func test_the_right_hand_holds_the_pistol_in_one_hand_across_the_look_range() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip_name: StringName in AIMED:
			for time: float in AIMED[clip_name]:
				var tag := "%s %s at %.2f" % [model, clip_name, time]
				stage.hold.set(&"one_handed", false)
				stage.pose(clip_name, time, 1.0, &"ual1/Idle", [FREE_ARM])
				await stage.settle()
				var two_barrel := _barrel(stage)
				var two_shoulders := _shoulders(stage)
				stage.hold.set(&"one_handed", true)
				stage.pose(clip_name, time, 1.0, &"ual1/Idle", [FREE_ARM])
				await stage.settle()
				var parts := stage.contact.measure("r", false)
				var fails := HandContact.failures(tag + " r:", parts, HoldStage.RIGHT_CONTACTS)
				var free := stage.bone_origin(&"hand_l").distance_to(_marker(stage))
				if free < FREE:
					fails.append("%s: the left hand is %.0f mm from the gun" % [tag, free * 1e3])
				var elbow := _elbow(stage)
				if elbow < STRAIGHT:
					fails.append("%s: the right elbow is at %.0f degrees" % [tag, elbow])
				var off_line := rad_to_deg(_barrel(stage).angle_to(two_barrel))
				if off_line > SAME_LINE:
					fails.append("%s: the barrel is %.1f degrees off the clip's" % [tag, off_line])
				var turn := rad_to_deg(two_shoulders.signed_angle_to(_shoulders(stage), Vector3.UP))
				if turn < SIDE_ON.x or turn > SIDE_ON.y:
					fails.append("%s: the chest is turned %.0f degrees" % [tag, turn])
				assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
		stage.free()


func test_a_one_handed_shot_kicks_the_muzzle_up_at_the_wrist_and_bends_the_elbow() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		stage.hold.set(&"one_handed", true)
		stage.pose(CharacterClips.PISTOL_AIM, 0.0, 1.0, &"ual1/Idle", [FREE_ARM])
		await stage.settle()
		var still := _barrel(stage)
		var still_elbow := _elbow(stage)
		stage.hold.set(&"shot_kick", 1.0)
		stage.pose(CharacterClips.PISTOL_AIM, 0.0, 1.0, &"ual1/Idle", [FREE_ARM])
		await stage.settle()
		var climb := rad_to_deg(asin(_barrel(stage).y) - asin(still.y))
		var climb_wanted: float = stage.hold.get(&"kick_climb")
		(
			assert_float(climb)
			. override_failure_message("%s: the muzzle climbed %.1f degrees" % [model, climb])
			. is_between(climb_wanted * 0.7, climb_wanted * 1.3)
		)
		(
			assert_float(still_elbow - _elbow(stage))
			. override_failure_message("%s: the kick did not bend the elbow" % model)
			. is_greater(3.0)
		)
		(
			assert_array(
				HandContact.failures(
					model + " kicked r:",
					stage.contact.measure("r", false),
					HoldStage.RIGHT_CONTACTS
				)
			)
			. is_empty()
		)
		stage.free()


func test_the_kick_rises_at_the_shot_and_settles_by_the_clips_end() -> void:
	assert_float(WeaponHold.kick_at(0.0)).is_equal(0.0)
	assert_float(WeaponHold.kick_at(WeaponHold.KICK_RISE)).is_greater(0.8)
	assert_float(WeaponHold.kick_at(0.5)).is_less(0.3)
	assert_float(WeaponHold.kick_at(1.0)).is_equal(0.0)


# One-handed, the left hand comes in only for a reload: free while aiming, at the magazine while
# it goes in, as the two-handed reload from the carry has it.
func test_the_left_hand_comes_in_only_for_the_reload() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		stage.hold.set(&"one_handed", true)
		var plan: SupportHandPlan = stage.hold.call(&"left_hand")
		stage.pose(CharacterClips.PISTOL_AIM, 0.0, 1.0, &"ual1/Idle", [FREE_ARM])
		await stage.settle()
		assert_float(plan.arm).override_failure_message("aiming, the hold has the hand").is_zero()
		var length := stage.clip(CharacterClips.PISTOL_RELOAD).length
		stage.pose(CharacterClips.PISTOL_RELOAD, 0.62 * length, 1.0, &"", [], 0.62)
		await stage.settle()
		var marker := stage.pistol.get_node(^"MagazineHand") as Node3D
		var gap := stage.bone_origin(&"hand_l").distance_to(marker.global_position)
		(
			assert_float(gap)
			. override_failure_message("%s: %.1f mm from the magazine" % [model, gap * 1e3])
			. is_less(REACH)
		)
		var fails := HandContact.failures(
			model + " magazine l:", stage.contact.measure("l", true), HoldStage.MAGAZINE_CONTACTS
		)
		assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
		stage.free()


# In two hands the left thumb's root has the frame under the slide; in one the right thumb lies
# there, forward along the barrel (the female body's solved grip folds it down the grip panel),
# and it goes there through nothing as the aim comes up, nor does the trigger finger on its way
# to the trigger (kit #1274: the male finger's own way rubbed the guard 2.1 mm deep).
func test_the_right_thumb_lies_forward_along_the_frame_in_one_hand() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		stage.hold.set(&"one_handed", true)
		for step in THUMB_STEPS + 1:
			var aim := float(step) / THUMB_STEPS
			stage.pose(CharacterClips.PISTOL_AIM, 0.0, aim, &"ual1/Idle", [FREE_ARM])
			await stage.settle()
			var parts := stage.contact.measure("r", false)
			for part: String in parts.keys():
				if not part.begins_with("thumb") and not part.begins_with("index"):
					parts.erase(part)
			var fails := HandContact.failures("%s aim %.2f r:" % [model, aim], parts, [])
			assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
		var tip := stage.skeleton.global_basis * stage.contact.bone_pose(&"thumb_03_r").basis
		var along := stage.skeleton.get_bone_pose_position(stage.skeleton.find_bone(&"thumb_03_r"))
		var off := rad_to_deg((tip * along).normalized().angle_to(_barrel(stage)))
		(
			assert_float(off)
			. override_failure_message(
				"%s: the thumb's tip points %.0f degrees off the barrel" % [model, off]
			)
			. is_less(THUMB_ALONG)
		)
		stage.free()


# One finger placement for both bodies (kit #1274): the trigger finger, the thumb and the grip
# fingers of the male hand land where the female hand's do on the gun (`fit_one_hand.gd` fitted
# them), not where a separate male pose put them (the thumb 23 mm and the little finger 16 mm
# apart before).
func test_both_bodies_hold_the_pistol_with_one_finger_placement() -> void:
	var places := {}
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		stage.hold.set(&"one_handed", true)
		stage.pose(CharacterClips.PISTOL_AIM, 0.0, 1.0, &"ual1/Idle", [FREE_ARM])
		await stage.settle()
		places[model] = Match.places(stage)
		stage.free()
	var fails: Array[String] = []
	for point in PLACED:
		var apart: float = (places.female[point] as Vector3).distance_to(places.male[point])
		if apart > PLACEMENT:
			fails.append("%s %.1f mm apart" % [point, apart * 1e3])
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()


# The player's own scene: the definition's `one_handed` switched while it aims puts the stance on
# and takes the left hand off the gun, a shot kicks, and switched back the left hand is on again.
func test_one_handed_switches_live_on_the_player() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(view)
	view.make_current()
	var pistol := player.weapon.definition.duplicate() as WeaponDef
	player.loadout.slots[0] = pistol
	player.weapon.definition = pistol
	await InputSim.ticks(get_tree(), 20)
	var hold := player.get_node("WeaponHold") as WeaponHold
	var skeleton := player.model.skeleton()
	var marker := player.get_node("Model/PistolHeld/Pistol/SupportHand") as Node3D
	# The modifiers' pose is the skeleton's only inside `skeleton_updated`.
	skeleton.skeleton_updated.connect(
		func() -> void: _measure_gap.call_deferred(_live_hand(skeleton), marker)
	)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_gap).is_less(REACH)
	pistol.one_handed = true
	await InputSim.ticks(get_tree(), 10)
	assert_int(hold.modifiers().size()).is_equal(4)
	assert_bool(hold.modifiers()[0] is OneHandStance).is_true()
	assert_float(_gap).is_greater(FREE)
	# The aim layer reads the muzzle after the stance and the grip's wrist turn (it ran between
	# them and left the barrel 24 degrees under the aim).
	var muzzle := player.weapon.muzzle
	var toward := (player.get_node("AimLayer") as AimLayer).aim_point(1.0) - muzzle.global_position
	var miss := rad_to_deg((-muzzle.global_basis.z).angle_to(toward))
	(
		assert_float(miss)
		. override_failure_message("one-handed, the muzzle is %.1f degrees off the aim" % miss)
		. is_less(AIM_MISS)
	)
	var kicks := 0
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	for _tick in 20:
		await InputSim.ticks(get_tree(), 1)
		if hold.shot_kick > 0.0:
			kicks += 1
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	assert_int(kicks).override_failure_message("no kick after the shot").is_greater(3)
	pistol.one_handed = false
	await InputSim.ticks(get_tree(), 30)
	assert_int(hold.modifiers().size()).is_equal(3)
	assert_float(_gap).is_less(REACH)
	InputSim.release_all()
	AudioDrain.stop_all(arena)


# The barrel's direction in the world (the pistol's muzzle is along its own -X).
func _barrel(stage: HoldStage) -> Vector3:
	return (stage.pistol.global_basis * Vector3.LEFT).normalized()


# From the left shoulder to the right one, level.
func _shoulders(stage: HoldStage) -> Vector3:
	var across := stage.bone_origin(&"upperarm_r") - stage.bone_origin(&"upperarm_l")
	return Vector3(across.x, 0.0, across.z).normalized()


# The right elbow's angle, in degrees (180 straight).
func _elbow(stage: HoldStage) -> float:
	var elbow := stage.bone_origin(&"lowerarm_r")
	var upper := stage.bone_origin(&"upperarm_r") - elbow
	var fore := stage.bone_origin(&"hand_r") - elbow
	return rad_to_deg(upper.angle_to(fore))


func _marker(stage: HoldStage) -> Vector3:
	return (stage.pistol.get_node(^"SupportHand") as Node3D).global_position


# The live left hand's bone in the world, read in `skeleton_updated`; the marker rides a
# `BoneAttachment3D` that may move after this listener, so it is read later (`_measure_gap`).
func _live_hand(skeleton: Skeleton3D) -> Vector3:
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(skeleton.find_bone(&"hand_l")).origin
	)


func _measure_gap(hand: Vector3, marker: Node3D) -> void:
	if is_instance_valid(marker):
		_gap = hand.distance_to(marker.global_position)
