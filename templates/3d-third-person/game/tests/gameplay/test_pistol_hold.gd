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


func before_test() -> void:
	_holder = auto_free(Node3D.new())
	add_child(_holder)


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
	var grip := PlayerAnimation.new()
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


# The measure itself works: with the hold left out the clips' own fist is found deep in the grip.
func test_the_clips_own_fist_fails_the_measure() -> void:
	var stage := HoldStage.make(_holder, "female", false)
	stage.pose(CharacterClips.PISTOL_AIM, 0.16, 1.0)
	await stage.settle()
	var right := stage.contact.measure("r")
	assert_array(HandContact.failures("r", right, HoldStage.RIGHT_CONTACTS)).is_not_empty()
	stage.free()


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
