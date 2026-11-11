# The prone aim clips (kit #1111) hold the pistol the way the game's hold does, on the skinned
# mesh of both mannequins after the hold's modifiers ran (`HoldStage`, `HandContact`): the barrel
# lies along the look each clip is made for, both hands are on the pistol within the hold's limits
# (2 mm in, 5 mm off), the left hand's bone is on its marker with its elbow where the clip put it,
# and neither the hands nor the pistol are under the floor.
extends GdUnitTestSuite

## Each clip and the look it is made for, in degrees (up is positive).
const CLIPS: Dictionary[StringName, float] = {
	CharacterClips.PRONE_AIM_DOWN: -25.0,
	CharacterClips.PRONE_AIM: 0.0,
	CharacterClips.PRONE_AIM_UP: 20.0,
}
## The times of each clip that are measured (the clips breathe; the pistol must not).
const TIMES: Array[float] = [0.0, 0.75, 1.5, 2.25]
## How far the barrel may be off its look, in degrees.
const LINE := 1.0
## How far the pistol may move through a clip's breath, in metres.
const STILL := 0.005
## How far the left hand's bone may be from its marker, in metres.
const REACH := 0.005
const MODELS: Array[String] = ["female", "male"]
## How far the left elbow may move when the hold reaches the arm, in metres: the clip has the hand
## on the marker already, so the reach changes next to nothing on the female mannequin, which the
## clips are solved on; the male's longer arms end 14 to 18 mm off, which the reach takes up.
const ELBOW_KEPT: Dictionary[String, float] = {"female": 0.01, "male": 0.025}
## The lowest a hand or finger bone may be over the floor, in metres (a finger is about 8 mm
## thick about its bone; the male's little finger presses 2 to 3 mm into it), and the lowest the
## pistol's foot and muzzle may be.
const BONE_FLOOR: Dictionary[String, float] = {"female": 0.008, "male": 0.004}
const PISTOL_FLOOR := 0.0

var _holder: Node3D


func before_test() -> void:
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func _pose(stage: HoldStage, clip: StringName, time: float) -> void:
	stage.hold.set(&"support_keep_elbow", 1.0)
	stage.pose(clip, time, 1.0)
	await stage.settle()


func test_the_barrel_lies_along_the_look_of_each_clip() -> void:
	for model: String in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip: StringName in CLIPS:
			var look := deg_to_rad(CLIPS[clip])
			var along := Vector3(0.0, sin(look), cos(look))
			var first := Vector3.ZERO
			for time in TIMES:
				await _pose(stage, clip, time)
				var barrel := -stage.pistol.global_basis.x.normalized()
				var off := rad_to_deg(barrel.angle_to(along))
				(
					assert_float(off)
					. override_failure_message(
						"%s %s at %.2f: the barrel is %.2f deg off" % [model, clip, time, off]
					)
					. is_less(LINE)
				)
				# The breath leaves the pistol where it is (the build holds it to 0.5 mm; the stretched
				# arms turn a hundredth of a degree of the imported keys into millimetres).
				if time == 0.0:
					first = stage.pistol.global_position
				assert_float(stage.pistol.global_position.distance_to(first)).is_less(STILL)
		stage.free()


func test_both_hands_hold_the_pistol_in_the_prone_aim_clips() -> void:
	for model: String in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip: StringName in CLIPS:
			for time: float in [0.0, 1.5]:
				await _pose(stage, clip, time)
				var tag := "%s %s at %.2f" % [model, clip, time]
				for side: String in ["r", "l"]:
					var parts := stage.contact.measure(side, side == "l")
					var contacts := (
						HoldStage.RIGHT_CONTACTS if side == "r" else HoldStage.LEFT_CONTACTS
					)
					var fails := HandContact.failures("%s %s:" % [tag, side], parts, contacts)
					assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
				var marker := stage.pistol.get_node("SupportHand") as Node3D
				var reach := stage.bone_origin(&"hand_l").distance_to(marker.global_position)
				(
					assert_float(reach)
					. override_failure_message(
						"%s: the left hand is %.1f mm off" % [tag, reach * 1e3]
					)
					. is_less(REACH)
				)
		stage.free()


func test_the_left_elbow_stays_where_the_clip_put_it() -> void:
	for model: String in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip: StringName in CLIPS:
			# The clip alone: the hold's arm off.
			stage.pose(clip, 0.0, 0.0)
			await stage.settle()
			var own := stage.bone_origin(&"lowerarm_l")
			await _pose(stage, clip, 0.0)
			var held := stage.bone_origin(&"lowerarm_l")
			(
				assert_float(held.distance_to(own))
				. override_failure_message(
					"%s %s: the elbow moved %.1f mm" % [model, clip, held.distance_to(own) * 1e3]
				)
				. is_less(ELBOW_KEPT[model])
			)
		stage.free()


func test_the_hands_and_the_pistol_stay_over_the_floor() -> void:
	for model: String in MODELS:
		var stage := HoldStage.make(_holder, model)
		for clip: StringName in CLIPS:
			await _pose(stage, clip, 0.0)
			var lowest := 1.0
			var lowest_bone := ""
			for bone in stage.skeleton.get_bone_count():
				var bone_name := stage.skeleton.get_bone_name(bone)
				var cursor := bone
				var in_hand := false
				while cursor >= 0:
					in_hand = in_hand or stage.skeleton.get_bone_name(cursor).begins_with("hand_")
					cursor = stage.skeleton.get_bone_parent(cursor)
				if in_hand and stage.bone_origin(bone_name).y < lowest:
					lowest = stage.bone_origin(bone_name).y
					lowest_bone = bone_name
			(
				assert_float(lowest)
				. override_failure_message(
					"%s %s: %s is %.1f mm up" % [model, clip, lowest_bone, lowest * 1e3]
				)
				. is_greater(BONE_FLOOR[model])
			)
			for part: String in ["Magazine", "Muzzle"]:
				var node := stage.pistol.find_child(part, true, false) as Node3D
				(
					assert_float(node.global_position.y)
					. override_failure_message(
						(
							"%s: the pistol's %s is %.1f mm up"
							% [clip, part, node.global_position.y * 1e3]
						)
					)
					. is_greater(PISTOL_FLOOR)
				)
		stage.free()
