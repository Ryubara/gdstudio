# The prone and crawl clips (kit #1009) import as a library beside the Universal Animation
# Library, one file a body (kit #1090, #1293): each of the template's bodies (the prototype `form`
# pair, `CharacterBodies`) and each Quaternius mannequin has the four clips solved on its own
# skeleton and skin, with the same clip names, lengths and crawl speed, and plays its own file as
# the library `prone`: the loops close, the two transitions start and end on the poses they join,
# the crawl's elbows and feet stay on their place on the floor at the speed the clip was made
# for, the body stays low, the skin of the forearms, knees and feet rests on the floor and no
# hand, forearm, thigh, shin or foot sinks into it.
extends GdUnitTestSuite

const UAL1 := "res://assets/animation/universal/ual1.glb"
## The bodies the clips are checked on, by the name the limits below use: the template's two
## first, then the Quaternius pair.
const MODELS: Dictionary[String, String] = {
	"form_female": CharacterBodies.FEMALE,
	"form_male": CharacterBodies.MALE,
	"female": CharacterBodies.QUATERNIUS_FEMALE,
	"male": CharacterBodies.QUATERNIUS_MALE,
}
## The file each of `MODELS` plays as the library `prone`.
const PRONE: Dictionary[String, String] = {
	"form_female": "res://assets/animation/prone/prone_form_female.glb",
	"form_male": "res://assets/animation/prone/prone_form_male.glb",
	"female": "res://assets/animation/prone/prone.glb",
	"male": "res://assets/animation/prone/prone_male.glb",
}
## The parts of the body the floor is measured against on every frame of every clip, on the
## skinned mesh. The feet are parts of their own, so a shin is not counted with its foot and toes.
const FLOOR_PARTS: Array[StringName] = [
	&"hand_l",
	&"hand_r",
	&"lowerarm_l",
	&"lowerarm_r",
	&"thigh_l",
	&"thigh_r",
	&"calf_l",
	&"calf_r",
]
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
## Metres a part's skin may be under the floor (skin pressed on it) on any frame of any clip, by
## body: the bar of kit #1293 for the `form` bodies (their feet too) and of kit #1090 for the
## Quaternius male; the Quaternius female's back shin presses 5.0 mm into the floor on one frame
## of going down, as her file was made (kit #1020), and the Quaternius feet are not held (their
## toes dip in the transitions).
const FLOOR_LIMITS := {"form_female": 0.006, "form_male": 0.006, "female": 0.006, "male": 0.005}
const FEET_HELD: Array[String] = ["form_female", "form_male"]
## The numbers of the clips' README, which the code that crawls reads.
const CRAWL_SPEED := 0.618
const CRAWL_SECONDS := 28.0 / 30.0
const ELBOW_PLANTED := 0.52
const FOOT_PLANTED := 0.30
const LENGTHS := {
	&"Prone_Idle": 3.0,
	&"Crawl_Fwd": CRAWL_SECONDS,
	&"Crouch_To_Prone": 0.9,
	&"Prone_To_Crouch": 1.0,
}
## How far a planted joint may stray (m), how low a bone may go (m, under the floor is negative)
## and how far a just planted wrist may lie from the centre line (m), by body, each in its own
## file (kit #1293 for the `form` bodies; in the Quaternius female's file their elbows rolled 19
## and 32 mm and their fingertips were 30 and 42 mm under the floor).
const LIMITS_STRAY := {"form_female": 0.004, "form_male": 0.004, "female": 0.004, "male": 0.004}
const LIMITS_BONE_FLOOR := {
	"form_female": -0.01, "form_male": -0.01, "female": -0.01, "male": -0.01
}
const LIMITS_WRIST := {"form_female": 0.11, "form_male": 0.11, "female": 0.10, "male": 0.10}
## The skin against the floor while lying and crawling (kit #1286, measured on each body's own
## skinned mesh by `BodyMeasure`): the deepest any part may go under it (m; the belly presses a
## few millimetres into it, the Quaternius female's shoulder 1.4 cm in the crawl), and the parts
## that carry the body, which come down to within `SKIN_ON` of it: the forearms, the knees (the
## calves' skin) and the feet lying still, the forearms and the feet crawling (the crawl pushes
## on the foot, never the knee).
const SKIN_UNDER := {"form_female": 0.006, "form_male": 0.006, "female": 0.015, "male": 0.006}
const SKIN_ON := 0.01
const CARRIERS := {
	&"prone/Prone_Idle": ["lowerarm_l", "lowerarm_r", "calf_l", "calf_r", "foot_l", "foot_r"],
	&"prone/Crawl_Fwd": ["lowerarm_l", "lowerarm_r", "foot_l", "foot_r"],
}
var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _twist: MannequinTwist


func _stage(body: String) -> void:
	_model = auto_free((load(MODELS[body]) as PackedScene).instantiate())
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = auto_free(AnimationPlayer.new())
	add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.add_animation_library(&"ual1", load(UAL1))
	_player.add_animation_library(&"prone", load(PRONE[body]))
	_twist = _skeleton.get_node_or_null("MannequinTwist") as MannequinTwist


# Every bone's place in the model's space with a clip held at a time.
func _pose(clip: StringName, at: float) -> Dictionary:
	_player.play(clip)
	_player.seek(at, true)
	_player.pause()
	# a prototype body's twist bones, as the game turns them near the camera (no clip keys them)
	if _twist != null:
		_twist.apply(_skeleton)
	var out := {}
	for bone in _skeleton.get_bone_count():
		out[_skeleton.get_bone_name(bone)] = _skeleton.get_bone_global_pose(bone)
	return out


# The largest distance between the same bones of two poses, in metres, and the largest turn.
func _gap(a: Dictionary, b: Dictionary) -> Vector2:
	var apart := 0.0
	var turn := 0.0
	for bone: String in a:
		var one: Transform3D = a[bone]
		var other: Transform3D = b[bone]
		apart = maxf(apart, one.origin.distance_to(other.origin))
		var between := one.basis.orthonormalized().inverse() * other.basis.orthonormalized()
		turn = maxf(turn, rad_to_deg(between.get_rotation_quaternion().get_angle()))
	return Vector2(apart, turn)


func test_each_library_holds_the_four_clips_and_the_loops_loop() -> void:
	for body: String in PRONE:
		var file := PRONE[body]
		var library: AnimationLibrary = load(file)
		var names: Array[String] = []
		for clip in library.get_animation_list():
			names.append(String(clip))
		names.sort()
		assert_array(names).override_failure_message("%s holds %s" % [file, names]).is_equal(
			["Crawl_Fwd", "Crouch_To_Prone", "Prone_Idle", "Prone_To_Crouch"]
		)
		for clip: StringName in LENGTHS:
			var animation := library.get_animation(clip)
			var where := "%s in %s" % [clip, file.get_file()]
			assert_float(animation.length).override_failure_message(where).is_equal_approx(
				LENGTHS[clip], 0.002
			)
			var loops := clip in [&"Prone_Idle", &"Crawl_Fwd"]
			assert_int(animation.loop_mode).override_failure_message(where).is_equal(
				Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
			)


func test_every_track_drives_a_bone_of_every_body() -> void:
	for body: String in MODELS:
		_stage(body)
		var library: AnimationLibrary = load(PRONE[body])
		for clip in library.get_animation_list():
			var animation := library.get_animation(clip)
			assert_int(animation.get_track_count()).is_greater(50)
			for track in animation.get_track_count():
				var path := animation.track_get_path(track)
				var node := _model.get_node_or_null(NodePath(path.get_concatenated_names()))
				assert_object(node).override_failure_message("%s: %s" % [clip, path]).is_not_null()
				var bone := String(path.get_concatenated_subnames())
				(
					assert_int((node as Skeleton3D).find_bone(bone))
					. override_failure_message("%s: no bone %s" % [clip, bone])
					. is_greater_equal(0)
				)


func test_the_loops_end_on_their_first_pose() -> void:
	for body: String in MODELS:
		_stage(body)
		for clip: StringName in [&"prone/Prone_Idle", &"prone/Crawl_Fwd"]:
			var length := _player.get_animation(clip).length
			var gap := _gap(_pose(clip, 0.0), _pose(clip, length))
			var said := "%s seam on %s: %s" % [clip, body, gap]
			assert_float(gap.x).override_failure_message(said).is_less(0.001)
			assert_float(gap.y).override_failure_message(said).is_less(0.1)


func test_the_transitions_join_the_crouch_and_the_prone_idle() -> void:
	for body: String in MODELS:
		_stage(body)
		var crouch := _pose(&"ual1/Crouch_Idle", 0.0)
		var prone := _pose(&"prone/Prone_Idle", 0.0)
		var joins := [
			[_pose(&"prone/Crouch_To_Prone", 0.0), crouch, "down starts on the crouch"],
			[_pose(&"prone/Crouch_To_Prone", 0.9), prone, "down ends on the prone idle"],
			[_pose(&"prone/Prone_To_Crouch", 0.0), prone, "up starts on the prone idle"],
			[_pose(&"prone/Prone_To_Crouch", 1.0), crouch, "up ends on the crouch"],
		]
		for join: Array in joins:
			var gap := _gap(join[0], join[1])
			var message := "%s on %s: %s" % [join[2], body, gap]
			assert_float(gap.x).override_failure_message(message).is_less(0.002)
			assert_float(gap.y).override_failure_message(message).is_less(0.2)


# A planted joint stays on its place on the floor while the body moves at the crawl's speed.
# The clip was solved on the female mannequin, where it holds to a millimetre; the Quaternius
# male's upper arms are 5 cm longer, so his elbows roll a little. The prototype bodies (kit
# #1286): LIMITS_STRAY.
func test_planted_elbows_and_feet_do_not_slide_at_the_crawl_speed() -> void:
	for body: String in MODELS:
		_stage(body)
		for joint: Array in [
			["lowerarm_r", 0.0, ELBOW_PLANTED],
			["lowerarm_l", 0.5, ELBOW_PLANTED],
			["hand_r", 0.0, ELBOW_PLANTED],
			["foot_l", 0.0, FOOT_PLANTED],
			["foot_r", 0.5, FOOT_PLANTED],
		]:
			var places: Array[Vector3] = []
			var steps := 12
			for step in steps:
				var phase: float = joint[2] * step / steps
				var at := fposmod(phase + joint[1], 1.0) * CRAWL_SECONDS
				var pose := _pose(&"prone/Crawl_Fwd", at)
				var place: Vector3 = (pose[joint[0]] as Transform3D).origin
				# the model faces +Z and has moved this far since the joint planted
				places.append(place + Vector3(0, 0, CRAWL_SPEED * phase * CRAWL_SECONDS))
			var middle := Vector3.ZERO
			for place in places:
				middle += place / places.size()
			var stray := 0.0
			for place in places:
				stray = maxf(stray, place.distance_to(middle))
			print("PRONE stray %s %s %.4f" % [body, joint[0], stray])
			(
				assert_float(stray)
				. override_failure_message("%s strays %.4f m on %s" % [joint[0], stray, body])
				. is_less(LIMITS_STRAY[body])
			)


# No bone goes under the floor on the female mannequin, which the clips were solved on; the
# male's longer arms put his thumb tips 2 cm lower. The prototype bodies: LIMITS_BONE_FLOOR.
func test_the_body_stays_low_while_prone() -> void:
	for body: String in MODELS:
		_stage(body)
		for clip: StringName in [&"prone/Prone_Idle", &"prone/Crawl_Fwd"]:
			var animation := _player.get_animation(clip)
			var length := animation.length
			# The bones the clip turns: a prototype body has more (its sockets and IK targets,
			# which no clip of this file moves, stand where the rest pose has them).
			var keyed := {}
			for track in animation.get_track_count():
				keyed[String(animation.track_get_path(track).get_concatenated_subnames())] = true
			var highest := 0.0
			var lowest := 1.0
			var lowest_bone := ""
			for step in 16:
				var pose := _pose(clip, length * step / 16.0)
				for bone: String in pose:
					if bone == "root" or not keyed.has(bone):
						continue
					var height := (pose[bone] as Transform3D).origin.y
					highest = maxf(highest, height)
					if height < lowest:
						lowest = height
						lowest_bone = bone
			var where := "%s on %s" % [clip, body]
			print(
				"PRONE bones %s: highest %.3f, %s at %.3f" % [where, highest, lowest_bone, lowest]
			)
			(
				assert_float(highest)
				. override_failure_message("%s: highest bone %.3f" % [where, highest])
				. is_less(0.45)
			)
			(
				assert_float(lowest)
				. override_failure_message("%s: %s at %.3f" % [where, lowest_bone, lowest])
				. is_greater(LIMITS_BONE_FLOOR[body])
			)


# The skin of each body, not its bones: lying still and crawling, no part goes deeper under the
# floor than SKIN_UNDER, and the forearms, the knees (the calves' skin) and the feet come down to
# the floor. The clips were solved on the Quaternius female's skin; the other bodies are thicker
# or longer in places, which only their own mesh shows.
func test_the_skin_rests_on_the_floor() -> void:
	for body: String in MODELS:
		var measure := BodyMeasure.stage(self, MODELS[body], {&"ual1": UAL1, &"prone": PRONE[body]})
		var twist := measure.skeleton.get_node_or_null("MannequinTwist") as MannequinTwist
		for clip: StringName in [&"prone/Prone_Idle", &"prone/Crawl_Fwd"]:
			var length := measure.player.get_animation(clip).length
			var lowest := {}
			for step in 16:
				measure.pose(clip, length * step / 16.0)
				if twist != null:
					twist.apply(measure.skeleton)
				var parts := measure.lowest_by_part()
				for part: String in parts:
					lowest[part] = minf(lowest.get(part, INF), parts[part])
			var deepest := INF
			var deepest_part := ""
			var row := PackedStringArray()
			for part: String in lowest:
				row.append("%s %.1f" % [part, lowest[part] * 1000.0])
				if lowest[part] < deepest:
					deepest = lowest[part]
					deepest_part = part
			var where := "%s on %s" % [clip, body]
			print("PRONE skin %s (mm): %s" % [where, ", ".join(row)])
			(
				assert_float(deepest)
				. override_failure_message(
					"%s: %s %.1f mm under the floor" % [where, deepest_part, -deepest * 1000.0]
				)
				. is_greater(-SKIN_UNDER[body])
			)
			for part: String in CARRIERS[clip]:
				(
					assert_float(lowest[part])
					. override_failure_message(
						"%s: %s %.1f mm over the floor" % [where, part, lowest[part] * 1000.0]
					)
					. is_less(SKIN_ON)
				)
		measure.free_nodes()


# No limb passes through another on any frame of the four clips, on the body that plays each
# file (the report beside each file, `limb_overlap.py --brief` in Blender on the skinned mesh).
func test_no_limb_passes_through_another() -> void:
	for body: String in MODELS:
		var bodies: Array[String] = [MODELS[body].get_file().get_basename()]
		var found := BodiesOverlap.problems(PRONE[body], bodies, {})
		assert_array(found).override_failure_message("; ".join(found)).is_empty()


# The floor under the skin, on every frame of the four clips: no hand (with its fingers), forearm,
# thigh or shin of a body's own mesh, and no foot of a `form` body, is more than `FLOOR_LIMITS`
# under the floor in the body's own file.
func test_no_hand_forearm_thigh_shin_or_foot_sinks_into_the_floor() -> void:
	for body: String in MODELS:
		_stage(body)
		var held: Array[StringName] = FLOOR_PARTS.duplicate()
		if body in FEET_HELD:
			held.append_array(FEET)
		var parts := SkinnedParts.new(_skeleton, FLOOR_PARTS + FEET)
		for part in FLOOR_PARTS:
			assert_int(parts.size(part)).override_failure_message(part).is_greater(20)
		for clip: StringName in LENGTHS:
			var frames := roundi(LENGTHS[clip] * 30.0)
			var lowest: Dictionary[StringName, float] = {}
			var lowest_frame: Dictionary[StringName, int] = {}
			for frame in frames + 1:
				_pose(StringName("prone/" + clip), minf(frame / 30.0, LENGTHS[clip]))
				var now := parts.lowest()
				for part in held:
					if now[part] < lowest.get(part, INF):
						lowest[part] = now[part]
						lowest_frame[part] = frame
			for part in held:
				(
					assert_float(lowest[part])
					. override_failure_message(
						(
							"%s on %s: %s is %.1f mm under the floor at frame %d"
							% [clip, body, part, -lowest[part] * 1000.0, lowest_frame[part]]
						)
					)
					. is_greater(-FLOOR_LIMITS[body])
				)
			print("FLOOR %s %s %s" % [body, clip, _millimetres(lowest, lowest_frame)])


# Each part's lowest height in millimetres and its frame, for the log.
func _millimetres(
	heights: Dictionary[StringName, float], frames: Dictionary[StringName, int]
) -> String:
	var out: Array[String] = []
	for part: StringName in heights:
		out.append("%s %.1f (%d)" % [part, heights[part] * 1000.0, frames[part]])
	return ", ".join(out)


# The arms crawl the way people do (the README's research): a planted forearm points inward, its
# wrist near the body's centre line in front of the head, and each hand in turn plants ahead of
# the other. The idle lies the same way. Measured on every body; the Quaternius male's shoulders
# are wider, so his wrists lie a little further out (LIMITS_WRIST).
func test_the_forearms_point_inward_and_the_hands_reach_past_each_other() -> void:
	for model: String in MODELS:
		_stage(model)
		for side: Array in [["r", "l", 0.0, -1.0], ["l", "r", 0.5, 1.0]]:
			var just_planted := _pose(&"prone/Crawl_Fwd", side[2] * CRAWL_SECONDS)
			var elbow: Vector3 = (just_planted["lowerarm_" + side[0]] as Transform3D).origin
			var wrist: Vector3 = (just_planted["hand_" + side[0]] as Transform3D).origin
			var other: Vector3 = (just_planted["hand_" + side[1]] as Transform3D).origin
			var inward := _inward(elbow, wrist, side[3])
			var where := "%s arm on %s" % [side[0], model]
			print(
				(
					"PRONE arm %s: %.1f degrees inward, wrist %.3f, %.3f ahead"
					% [where, inward, wrist.x, wrist.z - other.z]
				)
			)
			(
				assert_float(inward)
				. override_failure_message("%s: forearm %.1f degrees inward" % [where, inward])
				. is_between(34.0, 50.0)
			)
			(
				assert_float(absf(wrist.x))
				. override_failure_message("%s: wrist %.3f m from the centre" % [where, wrist.x])
				. is_less(LIMITS_WRIST[model])
			)
			# the model faces +Z: the hand that has just planted lies ahead of the other
			(
				assert_float(wrist.z - other.z)
				. override_failure_message("%s: %.3f m ahead" % [where, wrist.z - other.z])
				. is_greater(0.2)
			)
		var idle := _pose(&"prone/Prone_Idle", 0.0)
		for side: Array in [["r", -1.0], ["l", 1.0]]:
			var inward := _inward(
				(idle["lowerarm_" + side[0]] as Transform3D).origin,
				(idle["hand_" + side[0]] as Transform3D).origin,
				side[1]
			)
			(
				assert_float(inward)
				. override_failure_message(
					"idle %s arm on %s: %.1f degrees inward" % [side[0], model, inward]
				)
				. is_between(25.0, 45.0)
			)


# A resting forearm is rolled about 45 degrees onto its outer edge, so the palm faces down and in
# toward the other arm, and the hand is a fist: every finger's last joint is about as near the
# wrist as its knuckle and the thumb lies on the index finger. Lying flat on the palms tires the
# wrists;
# this is how a crawl is kept up (the README). Every body, lying still and in the crawl,
# planted and carried (an open finger's last joint is 1.6 times as far from the wrist as its
# knuckle, a closed one's 0.9, a carried fist's a little more).
func test_the_forearms_rest_on_their_outer_edge_and_the_hands_are_fists() -> void:
	for model: String in MODELS:
		_stage(model)
		var moments := [
			["idle", &"prone/Prone_Idle", 0.0, ["l", "r"]],
			["crawl, right planted", &"prone/Crawl_Fwd", 0.25 * CRAWL_SECONDS, ["r"]],
			["crawl, left planted", &"prone/Crawl_Fwd", 0.75 * CRAWL_SECONDS, ["l"]],
			["crawl, right carried", &"prone/Crawl_Fwd", 0.75 * CRAWL_SECONDS, ["r"]],
		]
		for moment: Array in moments:
			var pose := _pose(moment[1], moment[2])
			for side: String in moment[3]:
				var where := "%s, %s hand on %s" % [moment[0], side, model]
				var hand := _skeleton.find_bone("hand_" + side)
				var turned := (
					(pose["hand_" + side] as Transform3D).basis.orthonormalized()
					* _skeleton.get_bone_global_rest(hand).basis.orthonormalized().inverse()
				)
				# the palm faces down in the rest pose
				var palm := turned * Vector3.DOWN
				var roll := rad_to_deg(palm.angle_to(Vector3.DOWN))
				(
					assert_float(roll)
					. override_failure_message("%s: rolled %.1f degrees" % [where, roll])
					. is_between(35.0, 55.0)
				)
				var inward := -palm.x if side == "l" else palm.x
				(
					assert_float(inward)
					. override_failure_message("%s: the palm faces %.2f inward" % [where, inward])
					. is_greater(0.3)
				)
				var wrist: Vector3 = (pose["hand_" + side] as Transform3D).origin
				for finger: String in ["index", "middle", "ring", "pinky"]:
					var knuckle: Vector3 = (pose["%s_01_%s" % [finger, side]] as Transform3D).origin
					var last: Vector3 = (pose["%s_03_%s" % [finger, side]] as Transform3D).origin
					(
						assert_float(last.distance_to(wrist))
						. override_failure_message("%s: the %s finger is open" % [where, finger])
						. is_less(1.1 * knuckle.distance_to(wrist))
					)
				var thumb: Vector3 = (pose["thumb_03_" + side] as Transform3D).origin
				var index: Vector3 = (pose["index_02_" + side] as Transform3D).origin
				var palm_length := (pose["index_01_" + side] as Transform3D).origin.distance_to(
					wrist
				)
				(
					assert_float(thumb.distance_to(index))
					. override_failure_message("%s: the thumb is off the fingers" % where)
					. is_less(0.5 * palm_length)
				)


# Degrees a forearm points toward the body's centre line, seen from above (the model faces +Z and
# its left is +X; `side` is 1 for the left arm).
func _inward(elbow: Vector3, wrist: Vector3, side: float) -> float:
	var along := wrist - elbow
	return rad_to_deg(atan2(-side * along.x, along.z))
