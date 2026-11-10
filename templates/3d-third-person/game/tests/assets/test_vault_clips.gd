# The vault clips (`assets/animation/vault/vault.glb`, built by `build_vault.py`) carry what the
# vault code reads from them: three clips of the lengths `vault_clips.json` gives, every track on
# a bone of both mannequins, only the pelvis moved, the planted hand still on the reference box
# while the body is moved at the clip's speed, the feet over the floor, and first and last poses
# that join the sprint and each other.
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
