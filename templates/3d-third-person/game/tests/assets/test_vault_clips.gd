# The vault clips (`assets/animation/vault/vault.glb`, built by `build_vault.py`) carry what the
# vault code reads from them: three clips of the lengths `vault_clips.json` gives, every track on
# a bone of both mannequins, only the pelvis moved, the planted hand still on the reference box
# while the body is moved at the clip's speed, the feet over the floor, and first and last poses
# that join the sprint and each other. And what a body can do: the planted arm gives under the
# weight and pushes off straight, the body falls on the arc of a free fall while nothing touches
# it, the landing leg reaches for the ground and gives under the landing.
extends GdUnitTestSuite

const VAULT := "res://assets/animation/vault/vault.glb"
const UAL1 := "res://assets/animation/universal/ual1.glb"
const CLIPS := "res://assets/animation/vault/vault_clips.json"
const FEMALE := "res://assets/characters/mannequin/mannequin_female.glb"
const MALE := "res://assets/characters/mannequin/mannequin_male.glb"
const NAMES: Array[String] = ["Vault_High", "Vault_Land", "Vault_Low"]
## The bones a join is measured on: the ends of the limbs, the hips and the head.
const ENDS: Array[String] = ["pelvis", "Head", "hand_l", "hand_r", "foot_l", "foot_r"]
## The wrist bone rides this far over a surface the palm lies on (`PALM` in the build).
const WRIST_OVER_TOP := 0.036
const GRAVITY := 9.81
## How far the centre of mass may be off a free fall's arc in the air (`ARC_LIMIT` in the build
## is 0.015; the male's proportions add a little).
const ARC_LIMIT := 0.02
## The body's mass by part (`MASS` in the build): the two bones it lies between, the share of
## the way from the first to the second, and its share of the whole.
const MASS: Array[Array] = [
	["Head", "Head", 0.0, 0.08],
	["pelvis", "neck_01", 0.5, 0.50],
	["upperarm_l", "lowerarm_l", 0.44, 0.028],
	["upperarm_r", "lowerarm_r", 0.44, 0.028],
	["lowerarm_l", "hand_l", 0.43, 0.016],
	["lowerarm_r", "hand_r", 0.43, 0.016],
	["hand_l", "hand_l", 0.0, 0.006],
	["hand_r", "hand_r", 0.0, 0.006],
	["thigh_l", "calf_l", 0.43, 0.10],
	["thigh_r", "calf_r", 0.43, 0.10],
	["calf_l", "foot_l", 0.43, 0.0465],
	["calf_r", "foot_r", 0.43, 0.0465],
	["foot_l", "ball_l", 0.5, 0.0145],
	["foot_r", "ball_r", 0.5, 0.0145],
]

var _file := {}


func before() -> void:
	_file = JSON.parse_string(FileAccess.get_file_as_string(CLIPS))


func _rig(path: String) -> Dictionary:
	var model: Node3D = auto_free((load(path) as PackedScene).instantiate())
	add_child(model)
	var player: AnimationPlayer = auto_free(AnimationPlayer.new())
	add_child(player)
	player.root_node = player.get_path_to(model)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.add_animation_library(&"ual1", load(UAL1))
	player.add_animation_library(&"vault", load(VAULT))
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	return {"model": model, "player": player, "skeleton": skeleton}


# The place of each of `bones` in the model's space, in a clip's pose at a time.
func _pose(rig: Dictionary, clip: StringName, time: float, bones: Array[String]) -> Dictionary:
	var player: AnimationPlayer = rig.player
	var skeleton: Skeleton3D = rig.skeleton
	player.play(clip)
	player.seek(time, true)
	player.advance(0.0)
	var out := {}
	for bone in bones:
		out[bone] = (
			(skeleton.transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))).origin
		)
	return out


# The angle at the middle one of three bones in a clip's pose, in degrees (180 is straight).
func _joint(rig: Dictionary, clip: String, frame: int, bones: Array[String]) -> float:
	var pose := _pose(rig, StringName("vault/" + clip), _time(clip, frame), bones)
	var a: Vector3 = pose[bones[0]] - pose[bones[1]]
	var b: Vector3 = pose[bones[2]] - pose[bones[1]]
	return rad_to_deg(a.angle_to(b))


func _time(clip: String, frame: int) -> float:
	return minf(frame / float(_file.fps), _file.clips[clip].length)


# The height of the body's centre of mass in a clip's pose (the clips are in place and the game
# moves the body level over the reference obstacle, so this is its height in the world too).
func _centre(rig: Dictionary, clip: String, frame: int) -> float:
	var bones: Array[String] = []
	for part in MASS:
		bones.append(part[0])
		bones.append(part[1])
	var pose := _pose(rig, StringName("vault/" + clip), _time(clip, frame), bones)
	var height := 0.0
	var mass := 0.0
	for part in MASS:
		var from: Vector3 = pose[part[0]]
		var to: Vector3 = pose[part[1]]
		height += lerpf(from.y, to.y, part[2]) * float(part[3])
		mass += float(part[3])
	return height / mass


func _farthest(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for bone: String in a:
		worst = maxf(worst, (a[bone] as Vector3).distance_to(b[bone]))
	return worst


func test_the_library_holds_the_three_clips() -> void:
	var library: AnimationLibrary = load(VAULT)
	var names: Array[String] = []
	for clip in library.get_animation_list():
		names.append(String(clip))
	names.sort()
	assert_array(names).is_equal(NAMES)
	for clip in NAMES:
		var animation := library.get_animation(clip)
		var spec: Dictionary = _file.clips[clip]
		assert_float(animation.length).is_equal_approx(spec.length, 0.001)
		assert_float(spec.frames / float(_file.fps)).is_equal_approx(spec.length, 0.001)
		assert_int(animation.loop_mode).is_equal(Animation.LOOP_NONE)


func test_every_track_finds_a_bone_on_both_mannequins() -> void:
	var library: AnimationLibrary = load(VAULT)
	for path: String in [FEMALE, MALE]:
		var rig := _rig(path)
		var model: Node3D = rig.model
		var skeleton: Skeleton3D = rig.skeleton
		for clip in NAMES:
			var animation := library.get_animation(clip)
			assert_int(animation.get_track_count()).is_greater(40)
			for track in animation.get_track_count():
				var track_path := animation.track_get_path(track)
				var node := model.get_node_or_null(NodePath(track_path.get_concatenated_names()))
				assert_object(node).is_same(skeleton)
				var bone := track_path.get_concatenated_subnames()
				(
					assert_int(skeleton.find_bone(bone))
					. override_failure_message(
						"%s: %s has no bone %s" % [clip, path.get_file(), bone]
					)
					. is_greater_equal(0)
				)


func test_only_the_pelvis_is_moved() -> void:
	var library: AnimationLibrary = load(VAULT)
	for clip in NAMES:
		var animation := library.get_animation(clip)
		var moved: Array[String] = []
		for track in animation.get_track_count():
			var kind := animation.track_get_type(track)
			assert_bool(kind == Animation.TYPE_SCALE_3D).is_false()
			if kind == Animation.TYPE_POSITION_3D:
				moved.append(animation.track_get_path(track).get_concatenated_subnames())
		assert_array(moved).is_equal(["pelvis"])


# The clips are in place: the game moves the body. Moved at the clip's speed from where the
# sidecar says the root starts, the planted wrist stays at one place over the reference box.
func test_the_planted_hand_stays_on_the_box() -> void:
	var rig := _rig(FEMALE)
	for clip: String in ["Vault_Low", "Vault_High"]:
		var spec: Dictionary = _file.clips[clip]
		var top: float = spec.obstacle.height
		var first := int(round(spec.events.hand_plant * _file.fps))
		var last := int(round(spec.events.hand_release * _file.fps))
		var places: Array[Vector3] = []
		for frame in range(first, last + 1):
			var time: float = frame / float(_file.fps)
			var hand: Vector3 = _pose(rig, StringName("vault/" + clip), time, ["hand_l"]).hand_l
			places.append(hand + Vector3(0, 0, spec.root_start + spec.speed * time))
		assert_int(places.size()).is_greater_equal(3)
		for place in places:
			(
				assert_float(place.distance_to(places[0]))
				. override_failure_message(
					"%s: the planted wrist moves %.3f m" % [clip, place.distance_to(places[0])]
				)
				. is_less(0.005)
			)
			assert_float(place.y - top).is_equal_approx(WRIST_OVER_TOP, 0.005)
		assert_float(places[0].x).is_equal_approx(spec.hand_place.left, 0.005)
		assert_float(places[0].z).is_equal_approx(spec.hand_place.forward, 0.005)


func test_the_feet_stay_over_the_floor() -> void:
	var rig := _rig(FEMALE)
	var feet: Array[String] = ["foot_l", "foot_r", "ball_l", "ball_r"]
	for clip in NAMES:
		var spec: Dictionary = _file.clips[clip]
		var lowest := 9.0
		for frame in int(spec.frames) + 1:
			var time: float = minf(frame / float(_file.fps), spec.length)
			var pose := _pose(rig, StringName("vault/" + clip), time, feet)
			for bone in feet:
				lowest = minf(lowest, (pose[bone] as Vector3).y)
		assert_float(lowest).is_between(0.005, 0.05)


# Each vault starts on the sprint's left foot strike (0 s) and ends on its right one (half a
# cycle), where `Vault_Land` starts; `Vault_Land` ends on the left foot strike again.
func test_the_clips_join_the_sprint_and_each_other() -> void:
	var rig := _rig(FEMALE)
	var half: float = (rig.player as AnimationPlayer).get_animation(&"ual1/Sprint").length * 0.5
	var left_strike := _pose(rig, &"ual1/Sprint", 0.0, ENDS)
	var right_strike := _pose(rig, &"ual1/Sprint", half, ENDS)
	var land: Dictionary = _file.clips.Vault_Land
	for clip: String in ["Vault_Low", "Vault_High"]:
		var spec: Dictionary = _file.clips[clip]
		var start := _pose(rig, StringName("vault/" + clip), 0.0, ENDS)
		var end := _pose(rig, StringName("vault/" + clip), spec.length, ENDS)
		assert_float(_farthest(start, left_strike)).is_less(0.02)
		assert_float(_farthest(end, right_strike)).is_less(0.02)
		assert_float(_farthest(end, _pose(rig, &"vault/Vault_Land", 0.0, ENDS))).is_less(0.02)
	var landed := _pose(rig, &"vault/Vault_Land", land.length, ENDS)
	assert_float(_farthest(landed, left_strike)).is_less(0.02)


# No limb passes through another: `build_vault.py` measures, on every frame of every clip and on
# both mannequins' skinned meshes, how deep any body part is inside one no joint joins it to
# (`assets/animation/limb_overlap.py`), and writes the deepest into the sidecar with the hash of
# the file it measured. A vault.glb that is not that file any more has not been measured.
func test_no_limb_passes_through_another() -> void:
	assert_bool(_file.has("measured")).is_true()
	if not _file.has("measured"):
		return
	var measured: Dictionary = _file.measured
	(
		assert_str(FileAccess.get_sha256(VAULT))
		. override_failure_message(
			"vault.glb is not the file vault_clips.json was measured on: run build_vault.py"
		)
		. is_equal(measured.sha256)
	)
	assert_float(measured.overlap_limit_mm).is_less_equal(5.0)
	for clip in NAMES:
		var overlap: Dictionary = _file.clips[clip].contacts.overlap_mm
		assert_array(overlap.keys()).contains_exactly_in_any_order(["female", "male"])
		for body: String in overlap:
			var entry: Dictionary = overlap[body]
			(
				assert_float(entry.deepest)
				. override_failure_message(
					(
						"%s on the %s mannequin: %s by %.1f mm at frame %s"
						% [clip, body, entry.pair, entry.deepest, entry.frame]
					)
				)
				. is_less_equal(measured.overlap_limit_mm)
			)


# A vault is carried by the planted arm (the maintainer's review of 2026-11-11): the elbow gives
# as the body comes over the hand (or the hand lands with the arm folded under the body, on the
# high obstacle), and the arm is straight when the hand leaves.
func test_the_planted_arm_gives_and_pushes_off_straight() -> void:
	var arm: Array[String] = ["upperarm_l", "lowerarm_l", "hand_l"]
	for path: String in [FEMALE, MALE]:
		var rig := _rig(path)
		for clip: String in ["Vault_Low", "Vault_High"]:
			var spec: Dictionary = _file.clips[clip]
			assert_bool(spec.events.has("push_off")).is_true()
			if not spec.events.has("push_off"):
				continue
			var first := int(round(spec.events.hand_plant * _file.fps))
			var last := int(round(spec.events.push_off * _file.fps))
			assert_int(last - first).is_greater_equal(4)
			var elbows: Array[float] = []
			for frame in range(first, last + 1):
				elbows.append(_joint(rig, clip, frame, arm))
			var deepest: float = elbows.min()
			var said := "%s on %s: elbow %s" % [clip, path.get_file(), elbows]
			(
				assert_bool(deepest <= 100.0 or elbows[0] - deepest >= 15.0)
				. override_failure_message("the planted arm never gives. " + said)
				. is_true()
			)
			(
				assert_float(elbows[-1])
				. override_failure_message("the arm does not push off straight. " + said)
				. is_greater_equal(160.0)
			)
			assert_float(elbows[-1] - deepest).is_greater_equal(30.0)
			assert_float(spec.motion.push.weight_carried).is_greater_equal(0.25)


# From the hand's push to the landing nothing touches the body, so its centre of mass is on the
# arc of a free fall: measured here on the poses Godot plays, on both mannequins.
func test_the_body_falls_on_a_free_fall_arc() -> void:
	for path: String in [FEMALE, MALE]:
		var rig := _rig(path)
		for clip: String in ["Vault_Low", "Vault_High"]:
			var spec: Dictionary = _file.clips[clip]
			assert_bool(spec.events.has("push_off")).is_true()
			if not spec.events.has("push_off"):
				continue
			var first := int(round(spec.events.push_off * _file.fps))
			var last := int(spec.frames)
			# The best free fall through the frames: gravity is given, height and speed fitted.
			var times: Array[float] = []
			var lifted: Array[float] = []
			for frame in range(first, last + 1):
				var time := (frame - first) / float(_file.fps)
				times.append(time)
				lifted.append(_centre(rig, clip, frame) + 0.5 * GRAVITY * time * time)
			var mean_time := 0.0
			var mean_height := 0.0
			for index in times.size():
				mean_time += times[index] / times.size()
				mean_height += lifted[index] / times.size()
			var spread := 0.0
			var slope := 0.0
			for index in times.size():
				spread += (times[index] - mean_time) ** 2
				slope += (times[index] - mean_time) * (lifted[index] - mean_height)
			var speed := slope / spread
			var start := mean_height - speed * mean_time
			var off := 0.0
			for index in times.size():
				off = maxf(off, absf(start + speed * times[index] - lifted[index]))
			var said := "%s on %s: %.0f mm off the arc" % [clip, path.get_file(), off * 1e3]
			assert_float(off).override_failure_message(said).is_less(ARC_LIMIT)
			# The push sends the body up: the top of the arc comes after the hand has left.
			assert_float(speed).is_greater(0.5)
			assert_float(times[-1]).is_greater_equal(0.37)


# The landing leg reaches down a little more each frame and is nearly straight a frame before
# the foot lands; in `Vault_Land` the knee gives and the hips drop under the landing.
func test_the_landing_leg_reaches_and_gives() -> void:
	var leg: Array[String] = ["thigh_r", "calf_r", "foot_r"]
	var rig := _rig(FEMALE)
	for clip: String in ["Vault_Low", "Vault_High"]:
		var last := int(_file.clips[clip].frames)
		var knees: Array[float] = []
		for frame in range(last - 6, last + 1):
			knees.append(_joint(rig, clip, frame, leg))
		for index in range(1, knees.size()):
			var step := knees[index] - knees[index - 1]
			var said := "%s: knee %s" % [clip, knees]
			assert_float(step).override_failure_message(said).is_between(0.0, 30.0)
		assert_float(knees[-2]).is_greater_equal(135.0)
	var land: Dictionary = _file.clips.Vault_Land
	assert_bool(land.events.has("lowest")).is_true()
	if not land.events.has("lowest"):
		return
	var lowest := int(round(land.events.lowest * _file.fps))
	var hips: Array[float] = []
	var bent: Array[float] = []
	for frame in lowest + 1:
		var time := _time("Vault_Land", frame)
		hips.append((_pose(rig, &"vault/Vault_Land", time, ["pelvis"]).pelvis as Vector3).y)
		bent.append(_joint(rig, "Vault_Land", frame, leg))
	for index in range(1, hips.size()):
		assert_float(hips[index]).is_less(hips[index - 1])
		assert_float(bent[index]).is_less_equal(bent[index - 1] + 0.5)
	assert_float(hips[0] - hips[-1]).is_greater_equal(0.08)
