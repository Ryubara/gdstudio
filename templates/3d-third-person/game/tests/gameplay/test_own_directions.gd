# GDStudio's own strafes, backpedals and lean poses (`assets/animation/own/`, kit #1159), as the
# game imports them: each gait that does not go the way the body faces travels the way its
# record says at the speed it says, in step with the forward gait it names; a strafe turns its
# hips, knees and toes toward its step and passes its feet in two lanes without a leg going
# through the other; a left strafe is not a right strafe flipped; and a lean pose is its
# reference plus a difference that moves only the trunk, the legs and the upper arms, leans the
# way its record says from the ankles up, and leaves both soles on the floor when the tree adds
# it at full weight. The tracks, the seams, the planted feet, the skin on the floor and the
# budget of these clips are held by `test_own_clips.gd`, which reads every clip of the file.
extends GdUnitTestSuite

const OWN := "res://assets/animation/own/locomotion.glb"
const RECORDS := "res://assets/animation/own/locomotion.json"
const OVERLAP := "res://assets/animation/own/bodies_overlap.json"
const MODELS: Array[String] = [
	CharacterBodies.FEMALE,
	CharacterBodies.MALE,
	CharacterBodies.QUATERNIUS_FEMALE,
	CharacterBodies.QUATERNIUS_MALE,
]
## The gaits, the way each travels (degrees to the left of the way the body faces) and the
## forward gait it is in step with.
const DIRECTED := {
	"Walk_Back": [180.0, "Walk"],
	"Walk_Left": [90.0, "Walk"],
	"Walk_Right": [-90.0, "Walk"],
	"Jog_Back": [180.0, "Jog"],
	"Jog_Left": [90.0, "Jog"],
	"Jog_Right": [-90.0, "Jog"],
}
const STRAFES: Array[String] = ["Walk_Left", "Walk_Right", "Jog_Left", "Jog_Right"]
## The lean poses and the way each leans (degrees to the left of ahead).
const LEANS := {"Lean_Left": 90.0, "Lean_Right": -90.0, "Lean_Fwd": 0.0, "Lean_Back": 180.0}
const REFERENCE := "Lean_Ref"
## The bones a lean's difference from its reference may move (`clips/lean.py`, `MOVED`).
const MOVED: Array[String] = [
	"pelvis", "spine_", "neck_", "Head", "thigh_", "calf_", "foot_", "ball_", "upperarm_"
]
## A strafe's hips, knees and toes are turned a third toward its step: between these, degrees.
const TOWARD := [15.0, 50.0]
## How far a leg may be inside the other on any frame of a strafe, in metres: the build's limit
## for any limb is 5 mm, and the prototype male's thighs meet by 2 mm in his rest pose.
const LEGS := 0.0035
## How far the pose the tree makes from the reference and a lean's difference may be from the
## lean pose itself, per bone, in metres and degrees; and a sole from the floor, in metres.
const ADDED_PLACE := 0.002
const ADDED_TURN := 0.5
const SOLE := 0.002

var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer


func _records() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(RECORDS))


func _stage(model_path: String) -> void:
	_model = auto_free((load(model_path) as PackedScene).instantiate())
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = auto_free(AnimationPlayer.new())
	add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.add_animation_library(&"gds", load(OWN))


# Every bone's place and turn in the model's space with a clip held at a frame.
func _pose(clip: String, frame: float) -> Dictionary:
	_player.play(StringName("gds/" + clip))
	_player.seek(frame / 30.0, true)
	_player.pause()
	return _read()


func _read() -> Dictionary:
	var out := {}
	for bone in _skeleton.get_bone_count():
		out[_skeleton.get_bone_name(bone)] = _skeleton.get_bone_global_pose(bone)
	return out


# The way a record says the body leans or travels, in the model's space (+Z ahead, +X its left).
func _way(degrees: float) -> Vector3:
	return Vector3(sin(deg_to_rad(degrees)), 0.0, cos(deg_to_rad(degrees)))


# Degrees a bone is turned to the left about the vertical from where it is in another pose.
func _yaw_from(pose: Dictionary, other: Dictionary, bone: String) -> float:
	var turn: Basis = (
		(pose[bone] as Transform3D).basis * (other[bone] as Transform3D).basis.inverse()
	)
	var ahead := turn * Vector3.BACK
	return rad_to_deg(atan2(ahead.x, ahead.z))


func test_a_directed_gait_travels_its_own_way_in_step_with_the_forward_gait() -> void:
	var records := _records()
	for clip: String in DIRECTED:
		var record: Dictionary = records.clips[clip]
		var with: Dictionary = records.clips[DIRECTED[clip][1]]
		assert_str(record.kind).is_equal("gait")
		assert_float(record.heading).override_failure_message(clip).is_equal(DIRECTED[clip][0])
		assert_str(record.in_step_with).is_equal(DIRECTED[clip][1])
		# The same cycle and the same phase: the left foot lands at 0, the right half a cycle on.
		assert_float(record.frames).override_failure_message(clip).is_equal(with.frames)
		assert_float(record.contacts.l[0][0]).override_failure_message(clip).is_equal(0.0)
		var right_lands := INF
		for contact: Array in record.contacts.r:
			if contact[0] > 0.0:
				right_lands = minf(right_lands, contact[0])
		assert_float(right_lands).override_failure_message(clip).is_equal(record.frames / 2.0)
		# The travel curve goes the way the record says, a cycle's ground at the clip's speed.
		var travel: Array = record.travel
		var gone := Vector3(travel[-1][2] - travel[0][2], 0.0, travel[-1][1] - travel[0][1])
		var want: Vector3 = _way(record.heading) * record.speed * record.seconds
		(
			assert_float(gone.distance_to(want))
			. override_failure_message("%s travels %s, its record says %s" % [clip, gone, want])
			. is_less(0.02 * want.length())
		)
		# Shorter steps than the forward gait's, as a person's are backward and sideways.
		assert_float(record.speed).override_failure_message(clip).is_less(with.speed)
		assert_float(record.speed).override_failure_message(clip).is_greater(0.6 * with.speed)


func test_a_directed_gait_s_planted_sole_holds_the_floor_along_its_travel() -> void:
	# The ball of a planted foot stays on its place on the floor the body travels over, sideways
	# and backward as forward: while the sole is at rest (`flat` of the record) it moves under
	# 2 mm, so the speed in the record is the speed the feet hold the floor at.
	var records := _records()
	for model_path in MODELS.slice(0, 2):
		_stage(model_path)
		for clip: String in DIRECTED:
			var record: Dictionary = records.clips[clip]
			var way := _way(record.heading)
			for side: String in record.flat:
				for window: Array in record.flat[side]:
					var start := Vector3.INF
					var worst := 0.0
					for frame in range(ceili(window[0]), floori(window[1]) + 1):
						var pose := _pose(clip, frame)
						var place: Vector3 = (pose["ball_" + side] as Transform3D).origin
						place += way * record.speed * frame / 30.0
						if start == Vector3.INF:
							start = place
						worst = maxf(worst, Vector2(place.x - start.x, place.z - start.z).length())
					var where := (
						"%s, the %s foot on %s: %.2f mm"
						% [clip, side, model_path.get_file(), worst * 1000]
					)
					print(where)
					assert_float(worst).override_failure_message(where).is_less(0.002)


func test_a_strafe_turns_hips_knees_and_toes_toward_its_step() -> void:
	var records := _records()
	for model_path in MODELS.slice(0, 2):
		_stage(model_path)
		var standing := _pose("Idle", 0.0)
		for clip: String in STRAFES:
			var record: Dictionary = records.clips[clip]
			var toward := signf(record.heading)
			# Over the cycle, the pelvis's turn toward the step; each foot's while it is planted.
			var hips := 0.0
			for frame in int(record.frames):
				hips += toward * _yaw_from(_pose(clip, frame), standing, "pelvis") / record.frames
			var where := (
				"%s on %s: the hips are turned %.1f degrees" % [clip, model_path.get_file(), hips]
			)
			print(where)
			assert_float(hips).override_failure_message(where).is_between(TOWARD[0], TOWARD[1])
			for side: String in ["l", "r"]:
				var window: Array = record.flat[side][-1]
				var pose := _pose(clip, 0.5 * (window[0] + window[1]))
				var foot: Transform3D = pose["foot_" + side]
				var ball: Transform3D = pose["ball_" + side]
				var knee: Transform3D = pose["calf_" + side]
				var hip: Transform3D = pose["thigh_" + side]
				var toes := ball.origin - foot.origin
				var toe_turn := toward * rad_to_deg(atan2(toes.x, toes.z))
				var thigh := knee.origin - hip.origin
				var knee_turn := toward * rad_to_deg(atan2(thigh.x, thigh.z))
				where = (
					"%s on %s: the %s toes point %.1f degrees toward the step, the knee %.1f"
					% [clip, model_path.get_file(), side, toe_turn, knee_turn]
				)
				print(where)
				assert_float(toe_turn).override_failure_message(where).is_between(
					TOWARD[0], TOWARD[1]
				)
				# The leading leg's knee points on toward the step; the crossing leg's points ahead
				# (it passes in front of the other knee), never away from the step.
				var leading := (side == "l") == (toward > 0.0)
				assert_float(knee_turn).override_failure_message(where).is_greater(
					TOWARD[0] if leading else -5.0
				)


func test_a_strafe_s_feet_pass_in_two_lanes_and_no_leg_goes_through_the_other() -> void:
	# The crossing foot lands past the planted one, toward the step, and ahead of it (the leading
	# foot's lane is behind the root's path, the crossing foot's ahead of it).
	var records := _records()
	_stage(MODELS[0])
	for clip: String in STRAFES:
		var record: Dictionary = records.clips[clip]
		var toward := signf(record.heading)
		var crossing := "r" if toward > 0.0 else "l"
		var leading := "l" if toward > 0.0 else "r"
		var lands := 0.0
		for contact: Array in record.contacts[crossing]:
			lands = maxf(lands, contact[0])
		var pose := _pose(clip, fmod(lands, record.frames))
		var a: Vector3 = (pose["ball_" + crossing] as Transform3D).origin
		var b: Vector3 = (pose["ball_" + leading] as Transform3D).origin
		var where := (
			"%s: the crossing foot lands %.0f mm past the other and %.0f mm ahead of it"
			% [clip, toward * (a.x - b.x) * 1000, (a.z - b.z) * 1000]
		)
		print(where)
		assert_float(toward * (a.x - b.x)).override_failure_message(where).is_greater(0.05)
		assert_float(a.z - b.z).override_failure_message(where).is_greater(0.15)
	# The build measured every frame of every clip on every body's skin (`limb_overlap.py`).
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OVERLAP))
	for clip: String in DIRECTED:
		var by_body: Dictionary = report.clips[clip + "_Loop"]
		for body: String in by_body:
			var entry: Dictionary = by_body[body]
			var where := "%s on %s: %.1f mm (%s)" % [clip, body, entry.deepest_mm, entry.pair]
			print(where)
			assert_float(entry.deepest_mm / 1000.0).override_failure_message(where).is_less(LEGS)


func test_a_left_strafe_is_not_a_right_strafe_flipped() -> void:
	# Flip the right strafe left for right and lay it on the left one: the hips' turn, the
	# feet's lanes and the hands' heights are each side's own.
	var records := _records()
	_stage(MODELS[0])
	var standing := _pose("Idle", 0.0)
	for pair: Array in [["Walk_Left", "Walk_Right"], ["Jog_Left", "Jog_Right"]]:
		var frames := int(records.clips[pair[0]].frames)
		var hips := 0.0
		var feet := 0.0
		var hands := 0.0
		for frame in frames:
			var left := _pose(pair[0], frame)
			# The right strafe's left foot lands at 0 too; flipped, that is its right foot, so
			# the flipped clip is half a cycle on.
			var right := _pose(pair[1], (frame + frames / 2) % frames)
			var turn_l := _yaw_from(left, standing, "pelvis")
			var turn_r := -_yaw_from(right, standing, "pelvis")
			hips = maxf(hips, absf(turn_l - turn_r))
			for side: String in ["l", "r"]:
				var other := "r" if side == "l" else "l"
				var foot: Vector3 = (left["foot_" + side] as Transform3D).origin
				var flipped: Vector3 = (right["foot_" + other] as Transform3D).origin
				flipped.x = -flipped.x
				feet = maxf(feet, foot.distance_to(flipped))
				var hand: Vector3 = (left["hand_" + side] as Transform3D).origin
				var flipped_hand: Vector3 = (right["hand_" + other] as Transform3D).origin
				hands = maxf(hands, absf(hand.y - flipped_hand.y))
		var where := (
			"%s against %s flipped: hips %.1f degrees, a foot %.0f mm, a hand's height %.0f mm"
			% [pair[0], pair[1], hips, feet * 1000, hands * 1000]
		)
		print(where)
		assert_float(hips).override_failure_message(where).is_greater(2.0)
		assert_float(feet).override_failure_message(where).is_greater(0.02)
		assert_float(hands).override_failure_message(where).is_greater(0.005)


func test_a_lean_moves_only_the_trunk_the_legs_and_the_upper_arms() -> void:
	var records := _records()
	var library: AnimationLibrary = load(OWN)
	var reference := library.get_animation(REFERENCE)
	for clip: String in LEANS:
		var record: Dictionary = records.clips[clip]
		assert_bool(record.pose).is_true()
		assert_str(record.reference).is_equal(REFERENCE)
		assert_float(record.lean.way).is_equal(LEANS[clip])
		assert_float(record.lean.degrees).is_between(5.0, 20.0)
		var lean := library.get_animation(clip)
		assert_int(lean.get_track_count()).is_equal(reference.get_track_count())
		for track in lean.get_track_count():
			var path := lean.track_get_path(track)
			assert_str(String(reference.track_get_path(track))).is_equal(String(path))
			var bone := String(path.get_concatenated_subnames())
			var moved := false
			for stem in MOVED:
				moved = moved or bone.begins_with(stem)
			if moved:
				continue
			var a: Variant = lean.track_get_key_value(track, 0)
			var b: Variant = reference.track_get_key_value(track, 0)
			var apart := 0.0
			if a is Quaternion:
				apart = rad_to_deg((a as Quaternion).angle_to(b))
			else:
				apart = (a as Vector3).distance_to(b)
			(
				assert_float(apart)
				. override_failure_message("%s moves %s by %.3f" % [clip, bone, apart])
				. is_less(0.2)
			)


func test_a_lean_bends_the_body_its_way_from_the_ankles_through_the_spine() -> void:
	for model_path in MODELS.slice(0, 2):
		_stage(model_path)
		var upright := _pose(REFERENCE, 0.0)
		for clip: String in LEANS:
			var pose := _pose(clip, 0.0)
			var way := _way(LEANS[clip])
			var leans := {}
			# Each part's own line against the same line in the reference, toward the way of the lean.
			for part: Array in [
				["shins", "calf_l", "foot_l"],
				["thighs", "thigh_l", "calf_l"],
				["spine", "spine_01", "spine_03"],
				["neck", "spine_03", "Head"]
			]:
				var line: Vector3 = (
					(pose[part[2]] as Transform3D).origin - (pose[part[1]] as Transform3D).origin
				)
				var was: Vector3 = (
					(upright[part[2]] as Transform3D).origin
					- (upright[part[1]] as Transform3D).origin
				)
				# A line that hangs down (a shin) leans the way its top goes.
				var turn := -1.0 if was.y < 0.0 else 1.0
				leans[part[0]] = (
					turn
					* rad_to_deg(
						atan2(line.dot(way), absf(line.y)) - atan2(was.dot(way), absf(was.y))
					)
				)
			var head: Vector3 = (
				(pose["Head"] as Transform3D).origin - (upright["Head"] as Transform3D).origin
			)
			var where := (
				"%s on %s: shins %.1f, thighs %.1f, spine %.1f, neck %.1f degrees; the head goes %.0f mm"
				% [
					clip,
					model_path.get_file(),
					leans.shins,
					leans.thighs,
					leans.spine,
					leans.neck,
					head.dot(way) * 1000
				]
			)
			print(where)
			for part: String in leans:
				assert_float(leans[part]).override_failure_message(where).is_greater(1.0)
			assert_float(head.dot(way)).override_failure_message(where).is_greater(0.15)
			# Both feet stay where the reference has them.
			for side: String in ["l", "r"]:
				var foot: Vector3 = (pose["ball_" + side] as Transform3D).origin
				var was_foot: Vector3 = (upright["ball_" + side] as Transform3D).origin
				assert_float(foot.distance_to(was_foot)).override_failure_message(where).is_less(
					0.002
				)


func test_no_lean_is_another_flipped() -> void:
	_stage(MODELS[0])
	var upright := _pose(REFERENCE, 0.0)
	var left := _pose("Lean_Left", 0.0)
	var right := _pose("Lean_Right", 0.0)
	var worst := 0.0
	for bone: String in ["pelvis", "spine_03", "Head"]:
		var a: Vector3 = (left[bone] as Transform3D).origin - (upright[bone] as Transform3D).origin
		var b: Vector3 = (right[bone] as Transform3D).origin - (upright[bone] as Transform3D).origin
		b.x = -b.x
		worst = maxf(worst, a.distance_to(b))
	print("Lean_Left against Lean_Right flipped: %.0f mm" % (worst * 1000))
	assert_float(worst).is_greater(0.01)


func test_the_tree_adds_a_lean_s_difference_to_its_reference_and_the_soles_stay_down() -> void:
	# What the animation tree does with a lean (kit #1158): a gait, plus the lean pose less its
	# reference. Over the reference itself at full weight that is the lean pose, so both soles
	# are on the floor.
	for model_path in MODELS.slice(0, 2):
		var measure := BodyMeasure.stage(self, model_path, {&"gds": OWN})
		_model = measure.model
		_skeleton = measure.skeleton
		measure.pose(&"gds/Idle", 0.0)
		var standing := measure.feet_lowest()
		var floor_height := minf(standing["l"], standing["r"])
		for clip: String in LEANS:
			measure.pose(StringName("gds/" + clip), 0.0)
			var want := _read()
			var tree := _lean_tree(measure.player, clip)
			tree.advance(0.0)
			var got := _read()
			var apart := 0.0
			var turned := 0.0
			for bone: String in want:
				var a: Transform3D = want[bone]
				var b: Transform3D = got[bone]
				apart = maxf(apart, a.origin.distance_to(b.origin))
				turned = maxf(
					turned,
					rad_to_deg(
						a.basis.get_rotation_quaternion().angle_to(
							b.basis.get_rotation_quaternion()
						)
					)
				)
			var feet := measure.feet_lowest()
			var off := maxf(absf(feet["l"] - floor_height), absf(feet["r"] - floor_height))
			var where := (
				"%s added to its reference on %s: %.2f mm, %.2f degrees off the pose, soles %.2f mm up"
				% [clip, model_path.get_file(), apart * 1000, turned, off * 1000]
			)
			print(where)
			assert_float(apart).override_failure_message(where).is_less(ADDED_PLACE)
			assert_float(turned).override_failure_message(where).is_less(ADDED_TURN)
			assert_float(off).override_failure_message(where).is_less(SOLE)
			tree.active = false
			tree.free()
		measure.free_nodes()


# reference + (lean - reference), as an `AnimationTree` over the staged player.
func _lean_tree(player: AnimationPlayer, clip: String) -> AnimationTree:
	var blend := AnimationNodeBlendTree.new()
	for entry: Array in [["base", REFERENCE], ["lean", clip], ["reference", REFERENCE]]:
		var node := AnimationNodeAnimation.new()
		node.animation = StringName("gds/" + String(entry[1]))
		blend.add_node(StringName(entry[0]), node)
	blend.add_node(&"difference", AnimationNodeSub2.new())
	blend.add_node(&"added", AnimationNodeAdd2.new())
	blend.connect_node(&"difference", 0, &"lean")
	blend.connect_node(&"difference", 1, &"reference")
	blend.connect_node(&"added", 0, &"base")
	blend.connect_node(&"added", 1, &"difference")
	blend.connect_node(&"output", 0, &"added")
	var tree := AnimationTree.new()
	tree.tree_root = blend
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.set(&"parameters/difference/sub_amount", 1.0)
	tree.set(&"parameters/added/add_amount", 1.0)
	tree.active = true
	return tree
