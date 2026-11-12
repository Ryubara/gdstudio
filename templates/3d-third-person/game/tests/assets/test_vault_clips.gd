# The vault clips (`assets/animation/vault/vault.glb`, built by `build_vault.py`) carry what the
# vault code reads from them: three clips of the lengths `vault_clips.json` gives, every track on
# a bone of every body, only the pelvis moved, the planted hand still on the reference box
# while the body is moved at the clip's speed, the feet over the floor, and first and last poses
# that join the sprint and each other. And what a body can do: the planted arm gives under the
# weight and pushes off straight, the body falls on the arc of a free fall while nothing touches
# it, the landing leg reaches for the ground and gives under the landing, and an arm that has
# let go follows the body instead of being flung over the head. Posed on the template's bodies (the
# prototype `form` pair, `CharacterBodies`, kit #1286) and on the Quaternius pair the clips were
# keyed on (the female); `PER_BODY` holds where a body is allowed more.
extends GdUnitTestSuite

const VAULT := "res://assets/animation/vault/vault.glb"
const UAL1 := "res://assets/animation/universal/ual1.glb"
const CLIPS := "res://assets/animation/vault/vault_clips.json"
## The bodies, by the name the limits use: the template's two, then the Quaternius pair.
const MODELS: Dictionary[String, String] = {
	"form_female": CharacterBodies.FEMALE,
	"form_male": CharacterBodies.MALE,
	"female": CharacterBodies.QUATERNIUS_FEMALE,
	"male": CharacterBodies.QUATERNIUS_MALE,
}
## Limits a body is held to in place of the shared ones (kit #1286, measured): the clips were
## keyed on the Quaternius female, and on a body with other arms the planted wrist slides over the
## top and rides off its height (7.2 to 8.2 cm and 4.1 to 6.7 cm in `Vault_High`): kit #1294.
const PER_BODY := {
	"form_female": {"hand_moves": 0.08, "hand_height": 0.05},
	"form_male": {"hand_moves": 0.09, "hand_height": 0.075},
	"male": {"hand_moves": 0.085, "hand_height": 0.055},
}
## The crossings `bodies_overlap.json` reads on a body over `limb_overlap.py`'s limit (mm): the
## legs come over the top together on the Quaternius female's thighs, and the prototype bodies'
## thicker thighs go into each other there (kit #1294).
const KNOWN_OVERLAP_MM := {"Vault_High": {"form_female": 34.0, "form_male": 23.6}}
## The shared limits: how far the planted wrist moves (m) and how far its height over the top
## is off `WRIST_OVER_TOP` (m), the lowest foot bone's height (m), and how far a join is (m).
const SHARED := {"hand_moves": 0.005, "hand_height": 0.005, "feet": [0.005, 0.05], "join": 0.02}
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
const LEG_BONES: Array[String] = [
	"pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"
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


func _limit(body: String, key: String) -> Variant:
	return PER_BODY.get(body, {}).get(key, SHARED[key])


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


func test_every_track_finds_a_bone_on_every_body() -> void:
	var library: AnimationLibrary = load(VAULT)
	for body: String in MODELS:
		var path := MODELS[body]
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
					. override_failure_message("%s: %s has no bone %s" % [clip, body, bone])
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
	for body: String in MODELS:
		_planted_hand_stays_on_the_box(body)


func _planted_hand_stays_on_the_box(body: String) -> void:
	var rig := _rig(MODELS[body])
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
		var moves := 0.0
		var height := 0.0
		for place in places:
			moves = maxf(moves, place.distance_to(places[0]))
			height = maxf(height, absf(place.y - top - WRIST_OVER_TOP))
		var said := (
			"%s on %s: the planted wrist moves %.3f m, %.3f m off its height over the top"
			% [clip, body, moves, height]
		)
		print("VAULT " + said)
		assert_float(moves).override_failure_message(said).is_less(_limit(body, "hand_moves"))
		assert_float(height).override_failure_message(said).is_less(_limit(body, "hand_height"))
		if body == "female":
			assert_float(places[0].x).is_equal_approx(spec.hand_place.left, 0.005)
			assert_float(places[0].z).is_equal_approx(spec.hand_place.forward, 0.005)


func test_the_feet_stay_over_the_floor() -> void:
	var feet: Array[String] = ["foot_l", "foot_r", "ball_l", "ball_r"]
	for body: String in MODELS:
		var rig := _rig(MODELS[body])
		var limits: Array = _limit(body, "feet")
		for clip in NAMES:
			var spec: Dictionary = _file.clips[clip]
			var lowest := 9.0
			for frame in int(spec.frames) + 1:
				var time: float = minf(frame / float(_file.fps), spec.length)
				var pose := _pose(rig, StringName("vault/" + clip), time, feet)
				for bone in feet:
					lowest = minf(lowest, (pose[bone] as Vector3).y)
			var said := "%s on %s: the lowest foot bone at %.3f m" % [clip, body, lowest]
			print("VAULT " + said)
			assert_float(lowest).override_failure_message(said).is_between(limits[0], limits[1])


# Each vault starts on the sprint's left foot strike (0 s) and ends on its right one (half a
# cycle), where `Vault_Land` starts; `Vault_Land` ends on the left foot strike again.
func test_the_clips_join_the_sprint_and_each_other() -> void:
	for body: String in MODELS:
		_clips_join_the_sprint_and_each_other(body)


func _clips_join_the_sprint_and_each_other(body: String) -> void:
	var rig := _rig(MODELS[body])
	var limit: float = _limit(body, "join")
	var half: float = (rig.player as AnimationPlayer).get_animation(&"ual1/Sprint").length * 0.5
	var left_strike := _pose(rig, &"ual1/Sprint", 0.0, ENDS)
	var right_strike := _pose(rig, &"ual1/Sprint", half, ENDS)
	var land: Dictionary = _file.clips.Vault_Land
	for clip: String in ["Vault_Low", "Vault_High"]:
		var spec: Dictionary = _file.clips[clip]
		var start := _pose(rig, StringName("vault/" + clip), 0.0, ENDS)
		var end := _pose(rig, StringName("vault/" + clip), spec.length, ENDS)
		var gaps := [
			_farthest(start, left_strike),
			_farthest(end, right_strike),
			_farthest(end, _pose(rig, &"vault/Vault_Land", 0.0, ENDS)),
		]
		print("VAULT %s on %s: joins %s" % [clip, body, str(gaps)])
		for gap: float in gaps:
			assert_float(gap).override_failure_message("%s on %s" % [clip, body]).is_less(limit)
	var landed := _pose(rig, &"vault/Vault_Land", land.length, ENDS)
	print("VAULT Vault_Land on %s: join %.4f" % [body, _farthest(landed, left_strike)])
	assert_float(_farthest(landed, left_strike)).is_less(limit)


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


# The same measure on every body (`vault/bodies_overlap.json`, `limb_overlap.py --brief` on the
# template's bodies and the Quaternius pair): nothing deeper than the limit but the crossings
# KNOWN_OVERLAP_MM holds, and those no deeper.
func test_no_limb_passes_through_another_on_every_body() -> void:
	var bodies: Array[String] = []
	for body: String in MODELS:
		bodies.append(MODELS[body].get_file().get_basename())
	var found := BodiesOverlap.problems(VAULT, bodies, KNOWN_OVERLAP_MM)
	assert_array(found).override_failure_message("; ".join(found)).is_empty()


# A vault is carried by the planted arm (the maintainer's review of 2026-11-11): the elbow gives
# as the body comes over the hand (or the hand lands with the arm folded under the body, on the
# high obstacle), and the arm is straight when the hand leaves.
func test_the_planted_arm_gives_and_pushes_off_straight() -> void:
	var arm: Array[String] = ["upperarm_l", "lowerarm_l", "hand_l"]
	for body: String in MODELS:
		var path := MODELS[body]
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
			var said := "%s on %s: elbow %s" % [clip, body, elbows]
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
	for body: String in MODELS:
		var path := MODELS[body]
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
			var said := "%s on %s: %.0f mm off the arc" % [clip, body, off * 1e3]
			assert_float(off).override_failure_message(said).is_less(ARC_LIMIT)
			# The push sends the body up: the top of the arc comes after the hand has left.
			assert_float(speed).is_greater(0.5)
			assert_float(times[-1]).is_greater_equal(0.37)


# The landing leg reaches down a little more each frame and is nearly straight a frame before
# the foot lands; in `Vault_Land` the knee gives and the hips drop under the landing.
func test_the_landing_leg_reaches_and_gives() -> void:
	for body: String in MODELS:
		_landing_leg_reaches_and_gives(body)


func _landing_leg_reaches_and_gives(body: String) -> void:
	var leg: Array[String] = ["thigh_r", "calf_r", "foot_r"]
	var rig := _rig(MODELS[body])
	for clip: String in ["Vault_Low", "Vault_High"]:
		var last := int(_file.clips[clip].frames)
		var knees: Array[float] = []
		for frame in range(last - 6, last + 1):
			knees.append(_joint(rig, clip, frame, leg))
		for index in range(1, knees.size()):
			var step := knees[index] - knees[index - 1]
			var said := "%s on %s: knee %s" % [clip, body, knees]
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
	for body: String in MODELS:
		var path := MODELS[body]
		var rig := _rig(path)
		for clip: String in FREE_ARMS:
			assert_bool(_file.clips[clip].events.has(FREE_ARMS[clip])).is_true()
			var arm := _free_arm(rig, clip)
			var said := (
				"%s on %s, the right arm from frame %d: %.3f m over the shoulder, %.2f m/s, "
				% [clip, body, arm.first, arm.over, arm.speed]
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
	for body: String in MODELS:
		var path := MODELS[body]
		var legs := _legs(_rig(path), "Vault_High")
		var said := (
			"Vault_High on %s, hips over the box on frames %s (%.3f m over the top at the edge): "
			% [body, str(legs.over), legs.hips]
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
