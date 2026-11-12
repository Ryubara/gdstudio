# GDStudio's own clips (`assets/animation/own/`, kit #1154) import as the library `gds` beside the
# Universal Animation Library and play on the bodies the template wears (`CharacterBodies`, the
# prototype `form` pair the clips are solved and checked on): the file holds exactly the clips its
# `clips.json` freezes, every track finds its bone, a clip keys rotations and the pelvis's place
# and nothing else, the loops close bone by bone, a planted foot stays on its place on the floor
# while the model travels along the clip's travel curve, the gaits (kit #1155) hold the floor at
# the game's own speeds and share a phase, the player plays our clip where the library's played,
# the library clip still plays as a stand-in, and the imported library stays inside the budget.
extends GdUnitTestSuite

const OWN := "res://assets/animation/own/locomotion.glb"
const RECORDS := "res://assets/animation/own/locomotion.json"
const MODELS: Array[String] = [CharacterBodies.FEMALE, CharacterBodies.MALE]
## The furthest a planted foot's joints may move over a clip, in metres. The build holds the sole
## to 5 mm and the joints move less (0.2 mm on the female, 0.5 on the male, in the build's own
## measure of the idle); the import's compressed tracks add up to 0.9 mm (1.1 and 1.4 mm here).
const PLANTED := 0.0015
## The same for the toes' joint of a gait's foot, along the floor (m): 0.4 mm at most on both
## bodies, since the build sets the skin of the sole on the floor and moves the joint in height
## only.
const ROLLING := 0.001
## How far that joint may come down or go up while its foot rolls (m). The prototype bodies' sole
## turns up ahead of the ball of the foot (the toes' own skin is 7 mm over the floor), so a foot
## that rolls onto its toes stands on the ring of skin under the joint, which the heel lifts with
## it: the build brings the foot down 5 mm by the frame the toes leave to keep that skin on the
## floor.
const ROLL_DROP := 0.007
## The share of a gait's contact its foot takes to roll down onto the floor.
const ROLL_ON := 0.25
## The gaits, the speed the game moves each at (`CharacterTuning`) and the clip each replaced.
const GAITS := {
	"Walk": [&"walk_speed", &"ual1/Walk"],
	"Jog": [&"run_speed", &"ual1/Jog_Fwd"],
	"Sprint": [&"sprint_speed", &"ual1/Sprint"],
}
## The imported library's bytes for a second of clip (the plan's budget is 6 KB a second).
const BYTES_A_SECOND := 6144.0

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


func _spawn_player() -> Player:
	var player: Player = auto_free(load("res://gameplay/player/player.tscn").instantiate())
	player.start_at_spawn = false
	add_child(player)
	return player


# Every bone's place and turn in the model's space with a clip held at a time.
func _pose(clip: StringName, at: float) -> Dictionary:
	_player.play(clip)
	_player.seek(at, true)
	_player.pause()
	var out := {}
	for bone in _skeleton.get_bone_count():
		out[_skeleton.get_bone_name(bone)] = _skeleton.get_bone_global_pose(bone)
	return out


func test_the_library_holds_exactly_the_frozen_clips() -> void:
	var records := _records()
	var library: AnimationLibrary = load(OWN)
	var names: Array[String] = []
	for clip in library.get_animation_list():
		names.append(String(clip))
	names.sort()
	var frozen: Array[String] = []
	frozen.assign(records.frozen)
	frozen.sort()
	assert_array(names).is_equal(frozen)
	for clip: String in records.clips:
		var record: Dictionary = records.clips[clip]
		var animation := library.get_animation(clip)
		assert_float(animation.length).override_failure_message(clip).is_equal_approx(
			record.seconds, 0.002
		)
		assert_int(animation.loop_mode).override_failure_message(clip).is_equal(
			Animation.LOOP_LINEAR if record.loop else Animation.LOOP_NONE
		)


func test_every_track_finds_its_bone_and_keys_only_what_a_clip_may() -> void:
	var library: AnimationLibrary = load(OWN)
	for model_path in MODELS:
		_stage(model_path)
		for clip in library.get_animation_list():
			var animation := library.get_animation(clip)
			for track in animation.get_track_count():
				var path := animation.track_get_path(track)
				var bone := String(path.get_concatenated_subnames())
				var where := "%s: %s on %s" % [clip, path, model_path.get_file()]
				(
					assert_object(_model.get_node_or_null(NodePath(path.get_concatenated_names())))
					. override_failure_message(where)
					. is_not_null()
				)
				(
					assert_int(_skeleton.find_bone(bone))
					. override_failure_message(where)
					. is_greater_equal(0)
				)
				var type := animation.track_get_type(track)
				(
					assert_bool(type != Animation.TYPE_SCALE_3D)
					. override_failure_message(where)
					. is_true()
				)
				if type == Animation.TYPE_POSITION_3D:
					(
						assert_bool(bone == "pelvis" or bone.begins_with("ik_"))
						. override_failure_message(where)
						. is_true()
					)
				(
					assert_bool(bone != "root" and not bone.contains("_leaf"))
					. override_failure_message(where)
					. is_true()
				)


func test_a_loop_s_last_pose_is_its_first_bone_by_bone() -> void:
	var records := _records()
	for model_path in MODELS:
		_stage(model_path)
		for clip: String in records.clips:
			if not records.clips[clip].loop:
				continue
			var clip_name := StringName("gds/" + clip)
			var first := _pose(clip_name, 0.0)
			var last := _pose(clip_name, _player.get_animation(clip_name).length)
			for bone: String in first:
				var one: Transform3D = first[bone]
				var other: Transform3D = last[bone]
				(
					assert_float(one.origin.distance_to(other.origin))
					. override_failure_message("%s %s" % [clip, bone])
					. is_less(0.00002)
				)
				(
					assert_bool(one.basis.is_equal_approx(other.basis))
					. override_failure_message("%s %s" % [clip, bone])
					. is_true()
				)


func test_a_planted_foot_stays_on_its_place_on_the_floor() -> void:
	var records := _records()
	for model_path in MODELS:
		_stage(model_path)
		for clip: String in records.clips:
			var record: Dictionary = records.clips[clip]
			for side: String in record.contacts:
				for contact: Array in record.contacts[side]:
					var worst := _wander(clip, record, side, contact)
					var where := (
						"%s, the %s foot on %s: %.2f mm along the floor, %.2f mm up or down"
						% [clip, side, model_path.get_file(), worst.x * 1000.0, worst.y * 1000.0]
					)
					print(where)
					if record.kind == "gait":
						assert_float(worst.x).override_failure_message(where).is_less(ROLLING)
						assert_float(worst.y).override_failure_message(where).is_less(ROLL_DROP)
					else:
						assert_float(worst.length()).override_failure_message(where).is_less(
							PLANTED
						)


# The furthest a foot's joints get from where they were when the contact began, along the floor
# (x) and in height (y), on the floor the body travels over (the clip is in place: the travel
# curve of `clips.json` puts it back). A
# standing foot is held at the ankle and the toes. A gait's foot rolls: it lands on its heel
# and leaves over its toes, so the ankle travels and what stays put is the toes' joint, from
# the frame the foot is down (the first quarter of the contact is the roll onto it).
func _wander(clip: String, record: Dictionary, side: String, contact: Array) -> Vector2:
	var start := {}
	var worst := Vector2.ZERO
	var first := ceili(contact[0])
	var last := mini(floori(contact[1]), int(record.frames))
	var bones: Array[String] = ["foot_" + side, "ball_" + side]
	if record.kind == "gait":
		first += ceili(ROLL_ON * (contact[1] - contact[0]))
		bones = ["ball_" + side]
	for frame in range(first, last + 1):
		var pose := _pose(StringName("gds/" + clip), frame / 30.0)
		var travel := _travel_at(record, frame)
		for bone: String in bones:
			var place: Vector3 = (pose[bone] as Transform3D).origin + travel
			if not start.has(bone):
				start[bone] = place
			var moved: Vector3 = place - start[bone]
			worst = worst.max(Vector2(Vector2(moved.x, moved.z).length(), absf(moved.y)))
	return worst


# The root's place at a frame, from the travel curve of `clips.json` (forward is +Z, left +X).
func _travel_at(record: Dictionary, frame: int) -> Vector3:
	var curve: Array = record.travel
	for i in range(curve.size() - 1):
		var a: Array = curve[i]
		var b: Array = curve[i + 1]
		if frame >= a[0] and frame <= b[0]:
			var share: float = (frame - a[0]) / maxf(b[0] - a[0], 1.0)
			return Vector3(lerpf(a[2], b[2], share), 0.0, lerpf(a[1], b[1], share))
	return Vector3.ZERO


func test_the_gaits_hold_the_floor_at_the_game_s_speeds_and_share_a_phase() -> void:
	# The library's walk covered 56 % of the ground the game moved it over and its jog swept
	# 48 % faster than it (the audit, kit #1150). Ours carry the game's speeds, within 2 %, and
	# the left foot lands at 0 and the right at half the cycle in all three, so a blend between
	# them stays in step.
	var records := _records()
	var tuning := CharacterTuning.new()
	for clip: String in GAITS:
		var record: Dictionary = records.clips[clip]
		var speed: float = tuning.get(GAITS[clip][0])
		(
			assert_float(record.speed)
			. override_failure_message("%s: %.3f m/s for %.2f" % [clip, record.speed, speed])
			. is_equal_approx(speed, 0.02 * speed)
		)
		assert_str(record.kind).is_equal("gait")
		assert_str(record.replaces).is_equal(String(GAITS[clip][1]))
		assert_float(record.contacts.l[0][0]).override_failure_message(clip).is_equal(0.0)
		var right_lands := INF
		for contact: Array in record.contacts.r:
			if contact[0] > 0.0:
				right_lands = minf(right_lands, contact[0])
		assert_float(right_lands).override_failure_message(clip).is_equal(record.frames / 2.0)
		var steps: Array = record.events.filter(
			func(event: Dictionary) -> bool: return event.name == "footstep"
		)
		assert_int(steps.size()).override_failure_message(clip).is_equal(2)
		assert_str(steps[0].foot).is_equal("l")
		assert_str(steps[1].foot).is_equal("r")
		# The travel curve is the speed: the root is one cycle's ground further at the end.
		var travel: Array = record.travel
		assert_float(travel[-1][1] - travel[0][1]).override_failure_message(clip).is_equal_approx(
			speed * record.seconds, 0.02 * speed * record.seconds
		)


func test_a_gait_swings_each_arm_with_the_other_side_s_leg() -> void:
	# As a foot leaves the floor the other leg's knee is ahead of its own, and so is the hand
	# of its own side: each arm swings with the other side's leg, in the walk and in the runs
	# (whose arms are widest apart as the foot leaves, not as it lands).
	var records := _records()
	for model_path in MODELS:
		_stage(model_path)
		for clip: String in GAITS:
			var record: Dictionary = records.clips[clip]
			for side: String in ["l", "r"]:
				var other := "r" if side == "l" else "l"
				var lift: float = record.contacts[side][-1][1]
				var pose := _pose(StringName("gds/" + clip), fmod(lift, record.frames) / 30.0)
				var knee: Transform3D = pose["calf_" + other]
				var own_knee: Transform3D = pose["calf_" + side]
				var hand: Transform3D = pose["hand_" + side]
				var other_hand: Transform3D = pose["hand_" + other]
				var where := "%s as the %s foot leaves, on %s" % [clip, side, model_path.get_file()]
				(
					assert_float(knee.origin.z - own_knee.origin.z)
					. override_failure_message(where)
					. is_greater(0.1)
				)
				(
					assert_float(hand.origin.z - other_hand.origin.z)
					. override_failure_message(where)
					. is_greater(0.1)
				)


func test_the_player_plays_our_gaits_where_the_library_s_played() -> void:
	var player := _spawn_player()
	var animation: CharacterAnimation = player.get_node("Animation")
	var clips: AnimationPlayer = player.get_node("AnimationPlayer")
	var slots := {&"walk_clip": "gds/Walk", &"run_clip": "gds/Jog", &"sprint_clip": "gds/Sprint"}
	for slot: StringName in slots:
		assert_str(String(animation.get(slot))).is_equal(slots[slot])
		assert_bool(clips.has_animation(animation.get(slot))).is_true()
	assert_str(String(CharacterClips.WALK)).is_equal("gds/Walk")
	assert_str(String(CharacterClips.RUN)).is_equal("gds/Jog")
	assert_str(String(CharacterClips.SPRINT)).is_equal("gds/Sprint")
	# The library's gait goes back in through the inspector's export.
	animation.run_clip = CharacterClips.stand_in(CharacterClips.RUN)
	await await_idle_frame()
	assert_str(String(animation.run_clip)).is_equal("ual1/Jog_Fwd")


func test_the_idle_is_alive() -> void:
	# What the library's idle lacked (17 bones moving, the pelvis 8.5 mm, no weight shift, no
	# fingers): ours moves the pelvis from foot to foot and curls the fingers.
	_stage(MODELS[0])
	var length := _player.get_animation(&"gds/Idle").length
	var low := Vector3.INF
	var high := -Vector3.INF
	var curl_low := INF
	var curl_high := -INF
	for step in 41:
		var pose := _pose(&"gds/Idle", length * step / 40.0)
		var pelvis: Vector3 = (pose["pelvis"] as Transform3D).origin
		low = low.min(pelvis)
		high = high.max(pelvis)
		var bone := _skeleton.find_bone("index_02_l")
		var curl := _skeleton.get_bone_pose_rotation(bone).angle_to(
			_skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		)
		curl_low = minf(curl_low, curl)
		curl_high = maxf(curl_high, curl)
	assert_float(high.x - low.x).is_greater(0.04)
	assert_float(rad_to_deg(curl_high - curl_low)).is_greater(1.0)
	assert_float(rad_to_deg(curl_low)).is_greater(5.0)


func test_the_player_plays_our_idle_where_the_library_s_played() -> void:
	var player := _spawn_player()
	var animation: CharacterAnimation = player.get_node("Animation")
	var clips: AnimationPlayer = player.get_node("AnimationPlayer")
	assert_str(String(CharacterClips.IDLE)).is_equal("gds/Idle")
	assert_str(String(animation.idle_clip)).is_equal("gds/Idle")
	assert_bool(clips.has_animation(CharacterClips.IDLE)).is_true()
	assert_bool(clips.has_animation_library(CharacterClips.LIBRARY_OWN)).is_true()


func test_every_stand_in_is_a_library_clip_that_still_plays() -> void:
	var player := _spawn_player()
	var animation: CharacterAnimation = player.get_node("Animation")
	var clips: AnimationPlayer = player.get_node("AnimationPlayer")
	for own: StringName in CharacterClips.STAND_INS:
		var library: StringName = CharacterClips.STAND_INS[own]
		assert_bool(CharacterClips.ALL.has(own)).override_failure_message(own).is_true()
		assert_bool(clips.has_animation(library)).override_failure_message(library).is_true()
		assert_str(String(CharacterClips.stand_in(own))).is_equal(String(library))
	# The idle's stand-in goes back in through the inspector's export and the tree takes it.
	animation.idle_clip = CharacterClips.stand_in(CharacterClips.IDLE)
	await await_idle_frame()
	assert_str(String(animation.idle_clip)).is_equal("ual1/Idle")
	assert_str(String(CharacterClips.stand_in(CharacterClips.CROUCH_WALK))).is_equal(
		String(CharacterClips.CROUCH_WALK)
	)


func test_the_imported_library_is_inside_the_budget() -> void:
	var records := _records()
	var seconds := 0.0
	for clip: String in records.clips:
		seconds += records.clips[clip].seconds
	var config := ConfigFile.new()
	assert_int(config.load(OWN + ".import")).is_equal(OK)
	var imported: String = config.get_value("remap", "path")
	var size := FileAccess.get_file_as_bytes(imported).size()
	assert_int(size).is_greater(0)
	(
		assert_float(size / seconds)
		. override_failure_message("%d bytes for %.1f s of clips" % [size, seconds])
		. is_less(BYTES_A_SECOND)
	)
