# The jump with a weapon out, clip by clip (kit #1369; split from `test_jump_weapon_hold.gd`, which
# drives the live player, so the CI planner can deal the two apart: gdstudio #1558). Our nine jump
# clips hold the rifle and the pistol as the gaits do: on both mannequins, at every other frame of
# every jump clip, low and aimed, both hands are on the rifle within its hold's own limits
# (`REACH`, the palms on their sockets, every holding part on it), no point of the rifle is in the
# body or the head, and aimed the butt is on the shoulder; the pistol's grip hand holds it.
# Measured on the skinned mesh after the hold's modifiers ran (`RifleStage`, `HoldStage`,
# `HandContact`, `BodyClearance`).
extends GdUnitTestSuite

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

var _holder: Node3D


func before_test() -> void:
	_holder = auto_free(Node3D.new())
	add_child(_holder)


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
