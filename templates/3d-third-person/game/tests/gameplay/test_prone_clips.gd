# The prone and crawl clips (`assets/animation/prone/prone.glb`, kit #1009) import as a library
# beside the Universal Animation Library and play on both mannequins: the loops close, the two
# transitions start and end on the poses they join, the crawl's elbows and feet stay on their
# place on the floor at the speed the clip was made for, and the body stays low.
extends GdUnitTestSuite

const PRONE := "res://assets/animation/prone/prone.glb"
const UAL1 := "res://assets/animation/universal/ual1.glb"
const MODELS: Array[String] = [
	"res://assets/characters/mannequin/mannequin_female.glb",
	"res://assets/characters/mannequin/mannequin_male.glb",
]
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

var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer


func _stage(model_path: String) -> void:
	_model = auto_free((load(model_path) as PackedScene).instantiate())
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = auto_free(AnimationPlayer.new())
	add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.add_animation_library(&"ual1", load(UAL1))
	_player.add_animation_library(&"prone", load(PRONE))


# Every bone's place in the model's space with a clip held at a time.
func _pose(clip: StringName, at: float) -> Dictionary:
	_player.play(clip)
	_player.seek(at, true)
	_player.pause()
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


func test_the_library_holds_the_four_clips_and_the_loops_loop() -> void:
	var library: AnimationLibrary = load(PRONE)
	var names: Array[String] = []
	for clip in library.get_animation_list():
		names.append(String(clip))
	names.sort()
	assert_array(names).is_equal(["Crawl_Fwd", "Crouch_To_Prone", "Prone_Idle", "Prone_To_Crouch"])
	for clip: StringName in LENGTHS:
		var animation := library.get_animation(clip)
		assert_float(animation.length).override_failure_message(clip).is_equal_approx(
			LENGTHS[clip], 0.002
		)
		var loops := clip in [&"Prone_Idle", &"Crawl_Fwd"]
		assert_int(animation.loop_mode).override_failure_message(clip).is_equal(
			Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		)


func test_every_track_drives_a_bone_of_both_mannequins() -> void:
	for model_path in MODELS:
		_stage(model_path)
		var library: AnimationLibrary = load(PRONE)
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
	for model_path in MODELS:
		_stage(model_path)
		for clip: StringName in [&"prone/Prone_Idle", &"prone/Crawl_Fwd"]:
			var length := _player.get_animation(clip).length
			var gap := _gap(_pose(clip, 0.0), _pose(clip, length))
			assert_float(gap.x).override_failure_message("%s seam %s" % [clip, gap]).is_less(0.001)
			assert_float(gap.y).override_failure_message("%s seam %s" % [clip, gap]).is_less(0.1)


func test_the_transitions_join_the_crouch_and_the_prone_idle() -> void:
	for model_path in MODELS:
		_stage(model_path)
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
			var message := "%s on %s: %s" % [join[2], model_path.get_file(), gap]
			assert_float(gap.x).override_failure_message(message).is_less(0.002)
			assert_float(gap.y).override_failure_message(message).is_less(0.2)


# A planted joint stays on its place on the floor while the body moves at the crawl's speed.
# The clip was solved on the female mannequin, where it holds to a millimetre; the male's upper
# arms are 5 cm longer, so his elbows roll a little.
func test_planted_elbows_and_feet_do_not_slide_at_the_crawl_speed() -> void:
	var limits := [0.004, 0.035]
	for index in MODELS.size():
		_stage(MODELS[index])
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
			(
				assert_float(stray)
				. override_failure_message(
					"%s strays %.4f m on %s" % [joint[0], stray, MODELS[index].get_file()]
				)
				. is_less(limits[index])
			)


# No bone goes under the floor on the female mannequin, which the clips were solved on; the
# male's longer arms put his thumb tips 2 cm lower.
func test_the_body_stays_low_while_prone() -> void:
	var floors := [-0.01, -0.03]
	for index in MODELS.size():
		var model_path := MODELS[index]
		_stage(model_path)
		for clip: StringName in [&"prone/Prone_Idle", &"prone/Crawl_Fwd"]:
			var length := _player.get_animation(clip).length
			var highest := 0.0
			var lowest := 1.0
			var lowest_bone := ""
			for step in 16:
				var pose := _pose(clip, length * step / 16.0)
				for bone: String in pose:
					if bone == "root":
						continue
					var height := (pose[bone] as Transform3D).origin.y
					highest = maxf(highest, height)
					if height < lowest:
						lowest = height
						lowest_bone = bone
			var where := "%s on %s" % [clip, model_path.get_file()]
			(
				assert_float(highest)
				. override_failure_message("%s: highest bone %.3f" % [where, highest])
				. is_less(0.45)
			)
			(
				assert_float(lowest)
				. override_failure_message("%s: %s at %.3f" % [where, lowest_bone, lowest])
				. is_greater(floors[index])
			)
