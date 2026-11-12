# The jump's clips of GDStudio's own library (`assets/animation/own/`, kit #1161): the take-offs
# from the idle and from the jog's two foot strikes, the three poses of the air and the three
# landings. They are made for the controller's own jump (its numbers are the tuning's defaults),
# the capsule carries the body through the air, a landing is picked by fall speed, has a foot on
# the floor from its first frame and gives control back inside `land_time`, no pose is a mirror
# of itself, and the player plays them where the library's played. Tracks, loops, joins, planted
# feet and limbs are `test_own_clips.gd`'s, which reads every clip of the file.
extends GdUnitTestSuite

const OWN := "res://assets/animation/own/locomotion.glb"
const RECORDS := "res://assets/animation/own/locomotion.json"
const MODELS: Array[String] = [
	CharacterBodies.FEMALE,
	CharacterBodies.MALE,
	CharacterBodies.QUATERNIUS_FEMALE,
	CharacterBodies.QUATERNIUS_MALE,
]
## How far the lowest skin of the fall's first foot may be from the capsule's bottom (m).
const SOLE := 0.002
## How far the compressed import may move a bone's place (m) and turn (degrees) from the file's.
const IMPORT_PLACE := 0.01
const IMPORT_TURN := 2.0

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


# How far the left hand is from where the right hand would be in a mirror pose (m): the right
# hand's place reflected across the body's middle, the model's x = 0.
func _mirror_gap(left: Vector3, right: Vector3) -> float:
	return left.distance_to(Vector3(-right.x, right.y, right.z))


# Every bone's place and turn in the model's space with a clip held at a time.
func _pose(clip: StringName, at: float) -> Dictionary:
	_player.play(clip)
	_player.seek(at, true)
	_player.pause()
	var out := {}
	for bone in _skeleton.get_bone_count():
		out[_skeleton.get_bone_name(bone)] = _skeleton.get_bone_global_pose(bone)
	return out


func test_the_jump_s_clips_are_made_for_the_controller_s_jump() -> void:
	# The take-offs and the air are carried by the capsule on its own arc, and the landings are
	# timed by its landing: the numbers each was built for are the controller's defaults.
	var records := _records()
	var tuning := CharacterTuning.new()
	var checked := 0
	for clip: String in records.clips:
		var made: Dictionary = records.clips[clip].get("made_for", {})
		for key: String in made:
			var where := "%s was made for %s = %s" % [clip, key, made[key]]
			assert_float(tuning.get(key)).override_failure_message(where).is_equal_approx(
				made[key], 0.0001
			)
			checked += 1
	assert_int(checked).is_equal(3 * 3 + 2 * 2)
	# In the air no foot is on the floor, and the clip says the capsule carries it.
	for clip: String in [
		"Jump_Start", "Jump_Start_Run_L", "Jump_Start_Run_R", "Jump_Rise", "Jump_Apex", "Jump_Fall"
	]:
		var record: Dictionary = records.clips[clip]
		assert_bool(record.carried).override_failure_message(clip).is_true()
		assert_array(record.contacts.l).override_failure_message(clip).is_empty()
		assert_array(record.contacts.r).override_failure_message(clip).is_empty()
	# A take-off is over before the rise is, and the air's three poses loop.
	assert_float(records.clips["Jump_Start"].seconds).is_less(tuning.jump_rise_time)
	for clip: String in ["Jump_Rise", "Jump_Apex", "Jump_Fall"]:
		assert_bool(records.clips[clip].loop).override_failure_message(clip).is_true()
	# The running take-offs leave at the jog's speed, and the landing into the jog arrives at it.
	var jog: float = records.clips["Jog"].speed
	for clip: String in ["Jump_Start_Run_L", "Jump_Start_Run_R", "Land_To_Jog"]:
		assert_float(records.clips[clip].speed).override_failure_message(clip).is_equal_approx(
			jog, 0.02 * jog
		)
	assert_int(int(records.clips["Jump_Start_Run_L"].join_frames.first)).is_equal(0)
	assert_int(int(records.clips["Jump_Start_Run_R"].join_frames.first)).is_equal(
		int(records.clips["Jog"].frames / 2.0)
	)


func test_a_landing_is_picked_by_fall_speed_and_gives_control_back_in_time() -> void:
	var records := _records()
	var tuning := CharacterTuning.new()
	var soft: Dictionary = records.clips["Land_Soft"]
	var hard: Dictionary = records.clips["Land_Hard"]
	var to_jog: Dictionary = records.clips["Land_To_Jog"]
	# The soft landing begins where the game begins to play a landing, the hard one where the
	# soft one ends, and the controller's own jump lands softly.
	assert_float(soft.fall_speed.from).is_equal_approx(tuning.land_clip_speed, 0.0001)
	assert_float(hard.fall_speed.from).is_equal_approx(soft.fall_speed.to, 0.0001)
	assert_bool(hard.fall_speed.to == null).is_true()
	var lands_at := sqrt(2.0 * tuning.jump_height * tuning.gravity() * tuning.fall_gravity_scale)
	assert_float(lands_at).is_between(soft.fall_speed.from, soft.fall_speed.to)
	# Control is back inside `land_time`; what follows that frame is the settle.
	assert_float(soft.control / 30.0).is_less_equal(tuning.land_time + 0.0001)
	assert_float(soft.seconds).is_greater(soft.control / 30.0)
	assert_float(to_jog.seconds).is_less_equal(tuning.land_time + 0.0001)
	# A foot is on the floor from the first frame of every landing: the fall's pose stands on it.
	for record: Dictionary in [soft, hard, to_jog]:
		assert_float(record.contacts.l[0][0]).is_equal(0.0)
	for model_path: String in [CharacterBodies.FEMALE, CharacterBodies.MALE]:
		var measure := BodyMeasure.stage(self, model_path, {&"gds": OWN})
		measure.pose(&"gds/Idle", 0.0)
		var standing := measure.feet_lowest()
		var floor_height := minf(standing["l"], standing["r"])
		measure.pose(&"gds/Jump_Fall", 0.0)
		var feet := measure.feet_lowest()
		var where := (
			"%s: the fall's feet are %.1f and %.1f mm over the capsule's bottom"
			% [
				model_path.get_file(),
				(feet["l"] - floor_height) * 1000.0,
				(feet["r"] - floor_height) * 1000.0,
			]
		)
		print(where)
		assert_float(absf(feet["l"] - floor_height)).override_failure_message(where).is_less(SOLE)
		assert_float(feet["r"] - floor_height).override_failure_message(where).is_greater(0.02)
		measure.free_nodes()


func test_the_jump_is_not_a_mirror_of_itself() -> void:
	# No pose of the jump is the same on both sides (kit docs, own-animation.md#feel): in the air
	# the right knee leads and the feet are apart fore and aft; a landing's right foot stands a step
	# ahead of the left at its lowest; and no hand is where the other's mirror image would be.
	var records := _records()
	for model_path in MODELS:
		_stage(model_path)
		for clip: StringName in [&"gds/Jump_Rise", &"gds/Jump_Apex", &"gds/Jump_Fall"]:
			var pose := _pose(clip, 0.0)
			var where := "%s on %s" % [clip, model_path.get_file()]
			var knee_l: Transform3D = pose["calf_l"]
			var knee_r: Transform3D = pose["calf_r"]
			var foot_l: Transform3D = pose["foot_l"]
			var foot_r: Transform3D = pose["foot_r"]
			var hand_l: Transform3D = pose["hand_l"]
			var hand_r: Transform3D = pose["hand_r"]
			(
				assert_float(knee_r.origin.z - knee_l.origin.z)
				. override_failure_message(where)
				. is_greater(0.05)
			)
			(
				assert_float((foot_r.origin - foot_l.origin).abs()[Vector3.AXIS_Z])
				. override_failure_message(where)
				. is_greater(0.05)
			)
			(
				assert_float(_mirror_gap(hand_l.origin, hand_r.origin))
				. override_failure_message(where)
				. is_greater(0.05)
			)
		for clip: String in ["Land_Soft", "Land_Hard"]:
			var lowest: float = 0.0
			for event: Dictionary in records.clips[clip].events:
				if event.name == "lowest":
					lowest = event.frame / 30.0
			var pose := _pose(StringName("gds/" + clip), lowest)
			var where := "%s on %s" % [clip, model_path.get_file()]
			var ball_l: Transform3D = pose["ball_l"]
			var ball_r: Transform3D = pose["ball_r"]
			var hand_l: Transform3D = pose["hand_l"]
			var hand_r: Transform3D = pose["hand_r"]
			(
				assert_float(ball_r.origin.z - ball_l.origin.z)
				. override_failure_message(where)
				. is_greater(0.1)
			)
			(
				assert_float(_mirror_gap(hand_l.origin, hand_r.origin))
				. override_failure_message(where)
				. is_greater(0.05)
			)


func test_the_import_keeps_every_clip_s_motion() -> void:
	# Godot's compressed import cuts the library into pages; with 8 KiB pages it dropped the
	# pelvis's place keys on frames 16 to 28 of `Land_Hard` (the feet 173 to 194 mm off the
	# floor), with 32 the track is whole (kit docs, third-person/clips.md#animation-libraries).
	# Every bone's place and turn in the imported clips against the same file read uncompressed.
	var state := GLTFState.new()
	assert_int(GLTFDocument.new().append_from_file(OWN, state)).is_equal(OK)
	var scene: Node = auto_free(GLTFDocument.new().generate_scene(state))
	var raw: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var imported: AnimationLibrary = load(OWN)
	var compared := 0
	for clip: StringName in imported.get_animation_list():
		var packed := imported.get_animation(clip)
		# The file names a loop `<name>_Loop`; the importer takes the suffix off.
		var named := clip if raw.has_animation(clip) else StringName(String(clip) + "_Loop")
		assert_bool(raw.has_animation(named)).override_failure_message(String(clip)).is_true()
		if not raw.has_animation(named):
			continue
		var source := raw.get_animation(named)
		var tracks := {}
		for track in source.get_track_count():
			var bone := source.track_get_path(track).get_concatenated_subnames()
			tracks["%s %d" % [bone, source.track_get_type(track)]] = track
		var worst_place := 0.0
		var worst_turn := 0.0
		var where := ""
		for track in packed.get_track_count():
			var kind := packed.track_get_type(track)
			var key := "%s %d" % [packed.track_get_path(track).get_concatenated_subnames(), kind]
			if not tracks.has(key):
				continue
			var from: int = tracks[key]
			for frame in int(round(packed.length * 30.0)) + 1:
				var at := minf(frame / 30.0, packed.length)
				if kind == Animation.TYPE_POSITION_3D:
					var off := packed.position_track_interpolate(track, at).distance_to(
						source.position_track_interpolate(from, at)
					)
					if off > worst_place:
						worst_place = off
						where = "%s frame %d" % [key, frame]
				elif kind == Animation.TYPE_ROTATION_3D:
					var turn := rad_to_deg(
						packed.rotation_track_interpolate(track, at).angle_to(
							source.rotation_track_interpolate(from, at)
						)
					)
					worst_turn = maxf(worst_turn, turn)
			compared += 1
		var message := (
			"%s: a place %.1f mm off (%s), a turn %.2f degrees off"
			% [clip, worst_place * 1000.0, where, worst_turn]
		)
		print(message)
		assert_float(worst_place).override_failure_message(message).is_less(IMPORT_PLACE)
		assert_float(worst_turn).override_failure_message(message).is_less(IMPORT_TURN)
	assert_int(compared).is_greater(0)


func test_the_player_plays_our_jump_where_the_library_s_played() -> void:
	var player := _spawn_player()
	var animation: CharacterAnimation = player.get_node("Animation")
	var clips: AnimationPlayer = player.get_node("AnimationPlayer")
	assert_str(String(animation.jump_clip)).is_equal("gds/Jump_Start")
	assert_str(String(animation.air_clip)).is_equal("gds/Jump_Fall")
	assert_str(String(animation.land_clip)).is_equal("gds/Land_Soft")
	for clip: StringName in [
		CharacterClips.JUMP_START,
		CharacterClips.JUMP_START_RUN_L,
		CharacterClips.JUMP_START_RUN_R,
		CharacterClips.JUMP_RISE,
		CharacterClips.JUMP_APEX,
		CharacterClips.AIR,
		CharacterClips.LAND,
		CharacterClips.LAND_HARD,
		CharacterClips.LAND_TO_JOG,
	]:
		assert_bool(clips.has_animation(clip)).override_failure_message(clip).is_true()
	# The library's three still play as stand-ins.
	assert_str(String(CharacterClips.stand_in(CharacterClips.JUMP_START))).is_equal(
		"ual1/Jump_Start"
	)
	assert_str(String(CharacterClips.stand_in(CharacterClips.AIR))).is_equal("ual1/Jump")
	assert_str(String(CharacterClips.stand_in(CharacterClips.LAND))).is_equal("fixed/Jump_Land")
