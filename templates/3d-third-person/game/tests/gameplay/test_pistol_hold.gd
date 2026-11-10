# The hands hold the pistol (kit #1001): in every pistol clip and in the locomotion clips with the
# pistol out, on both mannequins, no skin of the right hand is more than 2 mm inside the gun and
# no holding part more than 5 mm off it; while aiming and shooting the left hand lies on the gun
# and over the right hand within the same limits, its arm reaching the support marker. Measured
# on the skinned mesh after the hold's modifiers ran (`HoldStage`, `HandContact`).
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
## The clips that hold the pistol in one hand, with the times sampled.
const ONE_HANDED: Dictionary[StringName, Array] = {
	CharacterClips.PISTOL_IDLE: [0.0, 0.5, 1.0],
	CharacterClips.PISTOL_RELOAD: [0.0, 0.4, 0.8, 1.2],
}
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
## How far the left hand's bone may stop from its marker, in metres (a clamped arm stops short).
const REACH := 0.005
## How near the trigger the index finger's tip is while aiming, and how far off it otherwise.
const ON_TRIGGER := 0.012
const OFF_TRIGGER := 0.02

var _holder: Node3D
var _live_skeleton: Skeleton3D
var _live_marker: Node3D
var _live_gaps: Array[float] = []


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
				_assert_holds(stage, "r", tag)
				_assert_holds(stage, "l", tag)
				(
					assert_float(_reach(stage))
					. override_failure_message(
						"%s: the left hand is %.1f mm from its marker" % [tag, _reach(stage) * 1e3]
					)
					. is_less(REACH)
				)
		stage.free()


func test_the_right_hand_holds_the_pistol_in_the_locomotion_clips() -> void:
	var grip := CharacterAnimation.new()
	var bones := grip.grip_bones
	var grip_clip := grip.grip_clip
	grip.free()
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
	var hold := player.get_node("WeaponHold") as WeaponHold
	assert_int(hold.modifiers().size()).is_equal(3)
	assert_float(hold.held_weight).is_equal(1.0)
	assert_float(hold.aim_weight).is_equal(0.0)
	assert_bool(hold.modifiers()[0].active).is_true()
	assert_bool(hold.modifiers()[1].active).is_false()
	_live_skeleton = (player.get_node("Model") as CharacterModel).skeleton()
	_live_marker = player.get_node("Model/PistolHeld/Pistol/SupportHand") as Node3D
	_live_gaps.clear()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(hold.aim_weight).is_equal(1.0)
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
	assert_float(hold.support_shortfall()).is_equal_approx(0.0, 0.0005)
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 40)
	assert_float(hold.aim_weight).is_equal(0.0)
	AudioDrain.stop_all(arena)


# The measure itself works: with the hold left out the clips' own fist is found deep in the grip.
func test_the_clips_own_fist_fails_the_measure() -> void:
	var stage := HoldStage.make(_holder, "female", false)
	stage.pose(CharacterClips.PISTOL_AIM, 0.16, 1.0)
	await stage.settle()
	var right := stage.contact.measure("r")
	assert_array(HandContact.failures("r", right, HoldStage.RIGHT_CONTACTS)).is_not_empty()
	stage.free()


# The hand's bone is read in the skeleton's update; the marker rides the attachment, which moves
# in the same signal, so the two are compared once every listener ran.
func _read_left_hand() -> void:
	var bone := _live_skeleton.get_bone_global_pose(_live_skeleton.find_bone(&"hand_l"))
	_compare_with_marker.call_deferred(_live_skeleton.global_transform * bone.origin)


func _compare_with_marker(hand: Vector3) -> void:
	if is_instance_valid(_live_marker):
		_live_gaps.append(hand.distance_to(_live_marker.global_position))


func _assert_holds(stage: HoldStage, side: String, tag: String) -> void:
	var parts := stage.contact.measure(side, side == "l")
	var contacts := HoldStage.RIGHT_CONTACTS if side == "r" else HoldStage.LEFT_CONTACTS
	var fails := HandContact.failures("%s %s:" % [tag, side], parts, contacts)
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()


# How far the left hand's bone is from the support marker, in metres.
func _reach(stage: HoldStage) -> float:
	var marker := stage.pistol.get_node(^"SupportHand") as Node3D
	return stage.bone_origin(&"hand_l").distance_to(marker.global_position)


# How far the skin of the index finger's last bone is from the trigger's front face, in metres.
func _tip_to_trigger(stage: HoldStage) -> float:
	var trigger := stage.pistol.find_child("Trigger", true, false) as Node3D
	return stage.contact.part_distance_to("r", "index_tip", trigger.global_position)
