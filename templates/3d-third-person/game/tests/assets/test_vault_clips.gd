# The vault clips (`assets/animation/vault/`, built by `build_vault.py`, one file for each of the
# template's bodies: `vault.glb` solved on `CharacterBodies.FEMALE`, `vault_male.glb` on `MALE`,
# kit #1294) carry what the vault code reads from them: three clips of the lengths
# `vault_clips.json` gives, the same in both files, every track on a bone of every body, only the
# pelvis moved, the planted hand still on the reference box
# while the body is moved at the clip's speed, the feet over the floor, and first and last poses
# that join the sprint and each other. And what a body can do: the planted arm gives under the
# weight and pushes off straight, the body falls on the arc of a free fall while nothing touches
# it, the landing leg reaches for the ground and gives under the landing, and an arm that has
# let go follows the body instead of being flung over the head.
extends GdUnitTestSuite

const VAULT := "res://assets/animation/vault/vault.glb"
const UAL1 := "res://assets/animation/universal/ual1.glb"
const CLIPS := "res://assets/animation/vault/vault_clips.json"
const FEMALE := CharacterBodies.FEMALE
const MALE := CharacterBodies.MALE
## The clip file each body plays (`CharacterAnimation.vault_libraries` in the character's scene)
## and the numbers the build wrote beside it.
const FILES: Dictionary[String, String] = {
	FEMALE: VAULT,
	MALE: "res://assets/animation/vault/vault_male.glb",
}
const SIDECARS: Dictionary[String, String] = {
	FEMALE: CLIPS,
	MALE: "res://assets/animation/vault/vault_male_clips.json",
}
## What the vault code reads of a clip, which every file holds the same (`SAME` in the build).
const SAME: Array[String] = [
	"length", "frames", "speed", "travel", "events", "root_start", "root_at", "obstacle"
]
const NAMES: Array[String] = ["Vault_High", "Vault_Land", "Vault_Low"]
## The bones a join is measured on: the ends of the limbs, the hips and the head.
const ENDS: Array[String] = ["pelvis", "Head", "hand_l", "hand_r", "foot_l", "foot_r"]
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

## An arm nothing holds (`FREE_*` in the build, a little wider for the male's longer arms): its
## wrist stays under this height over its own shoulder (m), moves no faster than this in the
## world and against its shoulder (m/s), and its speed changes by no more than this from one
## frame to the next (m/s).
const FREE_OVER_SHOULDER := 0.08
const FREE_SPEED := 7.5
const FREE_SPEED_AGAINST_SHOULDER := 5.0
const FREE_SPEED_CHANGE := 4.5
## The arm that is free in each vault and the event it is free from, to the landing: the right
## hand of `Vault_High` from when it lets go, the right arm of `Vault_Low` from the takeoff.
const FREE_ARMS := {"Vault_High": "right_hand_release", "Vault_Low": "takeoff"}

## The legs over the top in `Vault_High`, a little over the build's limits (`LEGS_*` in
## `build_vault.py`; both mannequins have the same legs): the knees and the ankles in
## widths of the hip joints while the hips are over the box, the tightest knee there, how far a
## leg bone may be under the top, the most an ankle's speed against the hips changes in one
## frame, and the speed under which a leg counts as held still.
const LEGS_KNEE_SPREAD := 2.2
const LEGS_ANKLE_SPREAD := 2.8
const LEGS_FOLD := 35.0
const LEGS_UNDER_TOP := 0.02
const LEGS_SPEED_CHANGE := 6.5
const LEGS_HELD := 1.0
## Between the keys: how often a second the legs are read against the box, and how far a leg
## joint's middle may be inside it (the build's `BETWEEN` and `JOINT_LIMIT`).
const BETWEEN_KEYS := 240.0
const JOINT_IN_BOX := 0.005
const LEG_BONES: Array[String] = [
	"pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"
]

var _file := {}
# The numbers of each body, by its model's path (`_file` is the default body's).
var _files := {}


func before() -> void:
	for model: String in SIDECARS:
		_files[model] = JSON.parse_string(FileAccess.get_file_as_string(SIDECARS[model]))
	_file = _files[FEMALE]


func _rig(path: String) -> Dictionary:
	var model: Node3D = auto_free((load(path) as PackedScene).instantiate())
	add_child(model)
	var player: AnimationPlayer = auto_free(AnimationPlayer.new())
	add_child(player)
	player.root_node = player.get_path_to(model)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.add_animation_library(&"ual1", load(UAL1))
	player.add_animation_library(&"vault", load(FILES[path]))
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
	for model: String in FILES:
		var library: AnimationLibrary = load(FILES[model])
		var names: Array[String] = []
		for clip in library.get_animation_list():
			names.append(String(clip))
		names.sort()
		assert_array(names).is_equal(NAMES)
		for clip in NAMES:
			var animation := library.get_animation(clip)
			var spec: Dictionary = _files[model].clips[clip]
			assert_float(animation.length).is_equal_approx(spec.length, 0.001)
			assert_float(spec.frames / float(_file.fps)).is_equal_approx(spec.length, 0.001)
			assert_int(animation.loop_mode).is_equal(Animation.LOOP_NONE)


# The vault code has one set of numbers (`VaultClip`): every file has the clips at the same
# lengths, speeds, contact times and root places, and the hands land at the same place.
func test_every_file_gives_the_vault_code_the_same_numbers() -> void:
	for model: String in SIDECARS:
		var theirs: Dictionary = _files[model]
		assert_str(theirs.model).is_equal(model.get_file())
		for clip in NAMES:
			for key in SAME:
				(
					assert_str(JSON.stringify(theirs.clips[clip].get(key)))
					. override_failure_message(
						"%s: %s differs in %s" % [clip, model.get_file(), key]
					)
					. is_equal(JSON.stringify(_file.clips[clip].get(key)))
				)
			if not _file.clips[clip].has("hand_place"):
				continue
			for key: String in ["left", "forward"]:
				assert_float(theirs.clips[clip].hand_place[key]).is_equal(
					_file.clips[clip].hand_place[key]
				)


func test_every_track_finds_a_bone_on_both_mannequins() -> void:
	for path: String in [FEMALE, MALE]:
		var library: AnimationLibrary = load(FILES[path])
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
	for model: String in FILES:
		var library: AnimationLibrary = load(FILES[model])
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
# sidecar says the root starts, the planted wrist stays at one place over the reference box, on
# each of the template's bodies in its own file (kit #1294: in one file keyed on the Quaternius
# female the wrists slid 18 to 82 mm on the top and rode 29 to 67 mm off their height).
func test_the_planted_hand_stays_on_the_box() -> void:
	for model: String in [FEMALE, MALE]:
		_planted_hand_stays_on_the_box(model)


func _planted_hand_stays_on_the_box(model: String) -> void:
	var rig := _rig(model)
	for clip: String in ["Vault_Low", "Vault_High"]:
		var spec: Dictionary = _files[model].clips[clip]
		var top: float = spec.obstacle.height
		var first := int(round(spec.events.hand_plant * _file.fps))
		var last := int(round(spec.events.hand_release * _file.fps))
		var places: Array[Vector3] = []
		for frame in range(first, last + 1):
			var time: float = frame / float(_file.fps)
			var hand: Vector3 = _pose(rig, StringName("vault/" + clip), time, ["hand_l"]).hand_l
			places.append(hand + Vector3(0, 0, spec.root_start + spec.speed * time))
		assert_int(places.size()).is_greater_equal(3)
		var moves := 0.0
		var height := 0.0
		for place in places:
			moves = maxf(moves, place.distance_to(places[0]))
			height = maxf(height, absf(place.y - top - spec.hand_place.wrist_above_top))
		var said := (
			"%s on %s: the planted wrist moves %.4f m, %.4f m off its height over the top"
			% [clip, model.get_file(), moves, height]
		)
		print("VAULT " + said)
		assert_float(moves).override_failure_message(said).is_less(0.005)
		assert_float(height).override_failure_message(said).is_less(0.005)
		assert_float(places[0].x).is_equal_approx(spec.hand_place.left, 0.005)
		assert_float(places[0].z).is_equal_approx(spec.hand_place.forward, 0.005)


func test_the_feet_stay_over_the_floor() -> void:
	var feet: Array[String] = ["foot_l", "foot_r", "ball_l", "ball_r"]
	for model: String in [FEMALE, MALE]:
		var rig := _rig(model)
		for clip in NAMES:
			var spec: Dictionary = _file.clips[clip]
			var lowest := 9.0
			for frame in int(spec.frames) + 1:
				var time: float = minf(frame / float(_file.fps), spec.length)
				var pose := _pose(rig, StringName("vault/" + clip), time, feet)
				for bone in feet:
					lowest = minf(lowest, (pose[bone] as Vector3).y)
			var said := "%s on %s: lowest foot bone %.3f m" % [clip, model.get_file(), lowest]
			assert_float(lowest).override_failure_message(said).is_between(0.005, 0.05)


# Each vault starts on the sprint's left foot strike (0 s) and ends on its right one (half a
# cycle), where `Vault_Land` starts; `Vault_Land` ends on the left foot strike again.
func test_the_clips_join_the_sprint_and_each_other() -> void:
	for model: String in [FEMALE, MALE]:
		_clips_join_the_sprint_and_each_other(model)


func _clips_join_the_sprint_and_each_other(model: String) -> void:
	var rig := _rig(model)
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


# A game draws the clip between its 24 keys a second, where two keys that are both clear of the
# box say nothing (gdstudio #1221: `Vault_Low`'s left knee went through the front edge between
# two keys). 240 times a second, with the body moved at the clip's speed, no leg joint of either
# mannequin is inside the reference box.
func test_no_leg_joint_cuts_the_box_between_the_keys() -> void:
	var joints: Array[String] = LEG_BONES.slice(1)
	for model: String in [FEMALE, MALE]:
		var rig := _rig(model)
		for clip: String in ["Vault_Low", "Vault_High"]:
			var spec: Dictionary = _file.clips[clip]
			var top: float = spec.obstacle.height
			var depth: float = spec.obstacle.depth
			var deepest := 0.0
			var where := ""
			var steps := int(round(spec.length * BETWEEN_KEYS))
			for step in steps + 1:
				var time := minf(step / BETWEEN_KEYS, spec.length)
				var pose := _pose(rig, StringName("vault/" + clip), time, joints)
				for bone in joints:
					var at: Vector3 = pose[bone]
					var forward: float = at.z + spec.root_start + spec.speed * time
					var inside := minf(top - at.y, minf(forward, depth - forward))
					if inside > deepest:
						deepest = inside
						where = "%s at %.4f s" % [bone, time]
			(
				assert_float(deepest)
				. override_failure_message(
					(
						"%s on %s: %s is %.3f m inside the box"
						% [clip, model.get_file(), where, deepest]
					)
				)
				. is_less(JOINT_IN_BOX)
			)
		var between: Dictionary = _files[model].clips.Vault_Low.contacts.between_keys
		assert_float(between.samples_a_second).is_greater_equal(60.0)


# No limb passes through another: `build_vault.py` measures, on every frame of every clip and on
# the skinned mesh of the body the file is for, how deep any body part is inside one no joint
# joins it to (`assets/animation/limb_overlap.py`), and writes the deepest into the sidecar with
# the hash of the file it measured. A clip file that is not that file any more has not been
# measured. (Kit #1294: in one file for every body the prototype bodies' thighs went 34.0 and
# 23.6 mm into each other in `Vault_High`.)
func test_no_limb_passes_through_another() -> void:
	for model: String in FILES:
		_no_limb_passes_through_another(model)


func _no_limb_passes_through_another(model: String) -> void:
	var file: Dictionary = _files[model]
	assert_bool(file.has("measured")).is_true()
	if not file.has("measured"):
		return
	var measured: Dictionary = file.measured
	(
		assert_str(FileAccess.get_sha256(FILES[model]))
		. override_failure_message(
			(
				"%s is not the file %s was measured on: run build_vault.py"
				% [FILES[model].get_file(), SIDECARS[model].get_file()]
			)
		)
		. is_equal(measured.sha256)
	)
	assert_float(measured.overlap_limit_mm).is_less_equal(5.0)
	for clip in NAMES:
		var overlap: Dictionary = file.clips[clip].contacts.overlap_mm
		assert_array(overlap.keys()).contains_exactly([file.body])
		for body: String in overlap:
			var entry: Dictionary = overlap[body]
			(
				assert_float(entry.deepest)
				. override_failure_message(
					(
						"%s on %s: %s by %.1f mm at frame %s"
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


# What the right arm does from `FREE_ARMS`' event to the landing, on the poses Godot plays, with
# the body moved at the clip's speed: the wrist's highest place over its own shoulder (m), its
# highest speed in the world and against the shoulder (m/s), and the most its speed changes from
# one frame to the next (m/s).
func _free_arm(rig: Dictionary, clip: String) -> Dictionary:
	var spec: Dictionary = _file.clips[clip]
	var first := int(round(spec.events[FREE_ARMS[clip]] * _file.fps))
	var bones: Array[String] = ["upperarm_r", "hand_r"]
	var world: Array[Vector3] = []
	var local: Array[Vector3] = []
	var out := {"over": -9.0, "speed": 0.0, "against": 0.0, "change": 0.0, "first": first}
	for frame in range(first, int(spec.frames) + 1):
		var time := _time(clip, frame)
		var pose := _pose(rig, StringName("vault/" + clip), time, bones)
		var wrist: Vector3 = pose.hand_r
		var shoulder: Vector3 = pose.upperarm_r
		out.over = maxf(out.over, wrist.y - shoulder.y)
		world.append(wrist + Vector3(0, 0, spec.speed * time))
		local.append(wrist - shoulder)
	var last_step := Vector3.ZERO
	for index in range(1, world.size()):
		var step: Vector3 = (world[index] - world[index - 1]) * float(_file.fps)
		out.speed = maxf(out.speed, step.length())
		var against: float = (local[index] - local[index - 1]).length() * float(_file.fps)
		out.against = maxf(out.against, against)
		if index > 1:
			out.change = maxf(out.change, (step - last_step).length())
		last_step = step
	return out


# A hand that lets go is carried on by the body (the maintainer's review of 2026-11-11, the
# third): in `Vault_High` the right arm lifts off ahead of the leg that swings over and rides
# out to the side at shoulder height; in `Vault_Low` the free right arm does the same. Before,
# the wrist went 0.30 m (0.37 m) over the shoulder at 11 m/s within two frames of the release.
func test_a_free_arm_follows_the_body() -> void:
	for path: String in [FEMALE, MALE]:
		var rig := _rig(path)
		for clip: String in FREE_ARMS:
			assert_bool(_file.clips[clip].events.has(FREE_ARMS[clip])).is_true()
			var arm := _free_arm(rig, clip)
			var said := (
				"%s on %s, the right arm from frame %d: %.3f m over the shoulder, %.2f m/s, "
				% [clip, path.get_file(), arm.first, arm.over, arm.speed]
			)
			said += "%.2f m/s against the shoulder, %.2f m/s a frame" % [arm.against, arm.change]
			print(said)
			(
				assert_float(arm.over)
				. override_failure_message("the wrist goes over the shoulder. " + said)
				. is_less_equal(FREE_OVER_SHOULDER)
			)
			(
				assert_float(arm.speed)
				. override_failure_message("the arm is flung. " + said)
				. is_less_equal(FREE_SPEED)
			)
			(
				assert_float(arm.against)
				. override_failure_message("the arm is flung past the shoulder. " + said)
				. is_less_equal(FREE_SPEED_AGAINST_SHOULDER)
			)
			(
				assert_float(arm.change)
				. override_failure_message("the arm snaps. " + said)
				. is_less_equal(FREE_SPEED_CHANGE)
			)
		# The right hand of `Vault_High` lets go while its elbow is still bent: an arm at
		# full stretch is torn off the top by the shoulder.
		var release := int(round(_file.clips.Vault_High.events.right_hand_release * _file.fps))
		var elbow := _joint(rig, "Vault_High", release, ["upperarm_r", "lowerarm_r", "hand_r"])
		(
			assert_float(elbow)
			. override_failure_message(
				"%s: the right elbow is at %.0f degrees when the hand lets go" % [path, elbow]
			)
			. is_less_equal(140.0)
		)


# What the legs do in a vault from the takeoff until they come down (seven frames before the
# landing): over the frames the hips are over the box, the widest the knees and the ankles
# are apart in widths of the hip joints, the tightest knee and the lowest leg bone against
# the top; over all of them, the most an ankle's speed against the hips changes in one frame
# and how often it rests against the hips for two frames running once the hips are over.
func _legs(rig: Dictionary, clip: String) -> Dictionary:
	var spec: Dictionary = _file.clips[clip]
	var fps := float(_file.fps)
	var first := int(round(spec.events.takeoff * fps))
	var final := int(spec.frames) - 7
	var out := {"knees": 0.0, "ankles": 0.0, "fold": 180.0, "low": 9.0, "snap": 0.0, "held": 0}
	out.merge({"over": [], "hips": 0.0})
	var local := {"l": [], "r": []}
	var over_from := -1
	for frame in range(first, final + 1):
		var time := _time(clip, frame)
		var pose := _pose(rig, StringName("vault/" + clip), time, LEG_BONES)
		for side: String in local:
			local[side].append(pose["foot_" + side] - pose.pelvis)
		var forward: float = spec.root_start + spec.speed * time + pose.pelvis.z
		if forward < 0.0 or forward > spec.obstacle.depth:
			continue
		if over_from < 0:
			over_from = frame - first
			out.hips = pose.pelvis.y - spec.obstacle.height
		out.over.append(frame)
		var width: float = (pose.thigh_l - pose.thigh_r).length()
		out.knees = maxf(out.knees, (pose.calf_l - pose.calf_r).length() / width)
		out.ankles = maxf(out.ankles, (pose.foot_l - pose.foot_r).length() / width)
		for side: String in local:
			var hip: Vector3 = pose["thigh_" + side] - pose["calf_" + side]
			var shin: Vector3 = pose["foot_" + side] - pose["calf_" + side]
			out.fold = minf(out.fold, rad_to_deg(hip.angle_to(shin)))
			for part: String in ["calf_", "foot_", "ball_"]:
				out.low = minf(out.low, pose[part + side].y - spec.obstacle.height)
	for side: String in local:
		var speeds: Array[Vector3] = []
		for index in range(1, local[side].size()):
			speeds.append((local[side][index] - local[side][index - 1]) * fps)
		for index in range(1, speeds.size()):
			out.snap = maxf(out.snap, (speeds[index] - speeds[index - 1]).length())
			var slow: bool = speeds[index].length() < LEGS_HELD
			if index > over_from and slow and speeds[index - 1].length() < LEGS_HELD:
				out.held += 1
	return out


# Both legs go over the box together, to one side (the maintainer's review of 2026-11-11, the
# fourth): in `Vault_High` the hips roll onto the left arm and the legs trail beside them, a
# hip width apart, in one move. Before, the right leg went over ahead and the left stayed
# folded behind the hands, astride them: the knees 3.8 hip widths apart with one folded to 14
# degrees, each leg stopping and starting again, then held for five frames in the air.
func test_the_legs_go_over_together() -> void:
	for path: String in [FEMALE, MALE]:
		var legs := _legs(_rig(path), "Vault_High")
		var said := (
			"Vault_High on %s, hips over the box on frames %s (%.3f m over the top at the edge): "
			% [path.get_file(), str(legs.over), legs.hips]
		)
		said += (
			"knees %.2f and ankles %.2f hip widths apart, tightest knee %.0f degrees, "
			% [legs.knees, legs.ankles, legs.fold]
		)
		said += (
			"lowest leg bone %.3f m over the top, %.2f m/s a frame, held %d"
			% [legs.low, legs.snap, legs.held]
		)
		print(said)
		assert_int(legs.over.size()).is_greater(1)
		(
			assert_float(legs.knees)
			. override_failure_message("the knees are astride. " + said)
			. is_less_equal(LEGS_KNEE_SPREAD)
		)
		(
			assert_float(legs.ankles)
			. override_failure_message("the feet are astride. " + said)
			. is_less_equal(LEGS_ANKLE_SPREAD)
		)
		(
			assert_float(legs.fold)
			. override_failure_message("a leg is folded shut over the top. " + said)
			. is_greater_equal(LEGS_FOLD)
		)
		(
			assert_float(legs.low)
			. override_failure_message("a leg hangs under the top. " + said)
			. is_greater_equal(-LEGS_UNDER_TOP)
		)
		assert_float(legs.snap).override_failure_message("a leg snaps. " + said).is_less_equal(
			LEGS_SPEED_CHANGE
		)
		(
			assert_int(legs.held)
			. override_failure_message("a leg is held still in the air. " + said)
			. is_equal(0)
		)
