# GDStudio's own starts and stops of the walk, the jog and the sprint (`assets/animation/own/`,
# kit #1156): every gait has a start that steps off with the left foot and one with the right,
# and a stop that begins as the left foot strikes and one as the right does; a start begins on
# the idle standing still and ends on its gait's pose as a foot strikes, at the gait's speed, and
# a stop the other way; the body's parts are moving as the gait's are where the two meet, so
# nothing pops; the two clips of a pair are not mirror images of each other; each names the frame
# from which the game may cut to new input. Planted feet, skin on the floor, tracks, limbs and
# the budget are `test_own_clips.gd`'s, which reads every clip of the file. The compressed
# import keeps every bone's motion of these clips as the file has it, and the player plays them.
extends GdUnitTestSuite

const OWN := "res://assets/animation/own/locomotion.glb"
const RECORDS := "res://assets/animation/own/locomotion.json"
const GAITS: Array[String] = ["Walk", "Jog", "Sprint"]
const FEET: Array[String] = ["L", "R"]
## The furthest a bone's step over the frame at a join may be from the gait's own step there, in
## metres: the build reads 0.5 to 7 mm on the file's own keys, and the import's compression adds
## to it.
const JOIN_STEP := 0.012
## How far apart a pair's two clips must be, read as mirror images, at the worst bone (m).
const NOT_A_MIRROR := 0.01
## How far the compressed import may move a bone's place (m) and turn (degrees) from the file's.
const IMPORT_PLACE := 0.002
const IMPORT_TURN := 1.0

var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer


func _records() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(RECORDS)).clips


func _stage(model_path: String) -> void:
	_model = auto_free((load(model_path) as PackedScene).instantiate())
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = auto_free(AnimationPlayer.new())
	add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.add_animation_library(&"gds", load(OWN))


# Every bone's place in the model's space with a clip held at a frame.
func _places(clip: String, frame: float) -> Dictionary:
	_player.play(StringName("gds/" + clip))
	_player.seek(frame / 30.0, true)
	_player.pause()
	var out := {}
	for bone in _skeleton.get_bone_count():
		out[_skeleton.get_bone_name(bone)] = _skeleton.get_bone_global_pose(bone).origin
	return out


# Metres a second the root travels at between two keys of a record's travel curve.
func _speed(record: Dictionary, last: bool) -> float:
	var curve: Array = record.travel
	var a: Array = curve[-2] if last else curve[0]
	var b: Array = curve[-1] if last else curve[1]
	return (b[1] - a[1]) / ((b[0] - a[0]) / 30.0)


func _pairs() -> Array[String]:
	var out: Array[String] = []
	for gait in GAITS:
		out.append("Idle_To_" + gait)
		out.append(gait + "_Stop")
	return out


func test_every_gait_has_a_start_and_a_stop_on_each_foot() -> void:
	var records := _records()
	var library: AnimationLibrary = load(OWN)
	for gait in GAITS:
		var cycle: Dictionary = records[gait]
		for foot in FEET:
			for start: bool in [true, false]:
				var clip := ("Idle_To_%s_%s" if start else "%s_Stop_%s") % [gait, foot]
				assert_bool(library.has_animation(clip)).override_failure_message(clip).is_true()
				var record: Dictionary = records[clip]
				assert_str(record.kind).is_equal("transition")
				assert_bool(record.loop).is_false()
				var joins: Dictionary = record.joins
				assert_str(joins["first" if start else "last"]).is_equal("Idle")
				assert_str(joins["last" if start else "first"]).is_equal(gait)
				# It meets the gait as a foot strikes: the left at the cycle's start, the right
				# at its half.
				var frame: float = joins["last_frame" if start else "first_frame"]
				var strikes: Array = [0.0, cycle.frames / 2.0]
				assert_array(strikes).override_failure_message(clip).contains([frame])
				# A stop begins on the foot it is named for; a start is named for its first step.
				if not start:
					assert_float(frame).is_equal(0.0 if foot == "L" else cycle.frames / 2.0)
				else:
					assert_str(record.start_foot).is_equal("both")
					var first: Dictionary = record.events[0]
					assert_str(first.name).is_equal("footstep")
					assert_str(first.foot).override_failure_message(clip).is_equal(foot.to_lower())
				# Still at the idle's end, at the gait's speed at the gait's.
				var moving := _speed(record, start)
				var still := _speed(record, not start)
				(
					assert_float(moving)
					. override_failure_message("%s: %.3f m/s" % [clip, moving])
					. is_equal_approx(cycle.speed, 0.02 * cycle.speed)
				)
				assert_float(still).override_failure_message(clip).is_equal_approx(0.0, 0.002)
				# The frame the game may cut to new input from is inside the clip, and a stop's
				# is not before its last footstep.
				var free: Array = record.events.filter(
					func(event: Dictionary) -> bool: return event.name == "free"
				)
				assert_int(free.size()).override_failure_message(clip).is_equal(1)
				assert_float(free[0].frame).is_between(1.0, record.frames - 1.0)
				if not start:
					for event: Dictionary in record.events:
						assert_float(event.frame).is_less_equal(free[0].frame)


func test_a_start_and_a_stop_meet_their_gait_moving_as_it_moves() -> void:
	# The pose at a join is the gait's (`test_own_clips.gd`); here the step every bone takes over
	# the frame at the join is the gait's step too, so the clip that follows goes on at the speed
	# this one ends at and nothing pops.
	var records := _records()
	_stage(CharacterBodies.FEMALE)
	for gait in GAITS:
		var cycle: Dictionary = records[gait]
		for foot in FEET:
			for start: bool in [true, false]:
				var clip := ("Idle_To_%s_%s" if start else "%s_Stop_%s") % [gait, foot]
				var record: Dictionary = records[clip]
				var frame: float = record.joins["last_frame" if start else "first_frame"]
				var mine_a := _places(clip, record.frames - 1.0 if start else 0.0)
				var mine_b := _places(clip, record.frames if start else 1.0)
				var earlier := fposmod(frame - 1.0, cycle.frames) if start else frame
				var gait_a := _places(gait, earlier)
				var gait_b := _places(gait, earlier + 1.0)
				var worst := 0.0
				var worst_bone := ""
				for bone: String in mine_a:
					var mine: Vector3 = mine_b[bone] - mine_a[bone]
					var theirs: Vector3 = gait_b[bone] - gait_a[bone]
					if mine.distance_to(theirs) > worst:
						worst = mine.distance_to(theirs)
						worst_bone = bone
				var where := "%s: %s steps %.1f mm off the gait's" % [clip, worst_bone, worst * 1e3]
				print(where)
				assert_float(worst).override_failure_message(where).is_less(JOIN_STEP)


func test_the_two_clips_of_a_pair_are_not_mirror_images() -> void:
	# The idle stands on its left leg and each gait has its own numbers per side, so the clip on
	# the right foot is solved on its own (the kit's `own-animation.md#feel`, no mirror poses).
	var records := _records()
	_stage(CharacterBodies.FEMALE)
	for pair in _pairs():
		var left: Dictionary = records[pair + "_L"]
		var right: Dictionary = records[pair + "_R"]
		var frames: float = minf(left.frames, right.frames)
		var worst := 0.0
		for share: float in [0.25, 0.5, 0.75]:
			var one := _places(pair + "_L", roundf(share * frames))
			var two := _places(pair + "_R", roundf(share * frames))
			for bone: String in one:
				var twin := bone
				if bone.ends_with("_l"):
					twin = bone.trim_suffix("_l") + "_r"
				elif bone.ends_with("_r"):
					twin = bone.trim_suffix("_r") + "_l"
				var mirrored: Vector3 = two[twin] * Vector3(-1.0, 1.0, 1.0)
				worst = maxf(worst, (one[bone] as Vector3).distance_to(mirrored))
		var where := "%s: left and right differ by %.0f mm as mirror images" % [pair, worst * 1e3]
		print(where)
		assert_float(worst).override_failure_message(where).is_greater(NOT_A_MIRROR)


func test_the_import_keeps_every_start_and_stop_s_motion() -> void:
	# Godot's compressed import cuts the library into pages; with 8 KiB pages it held the pelvis's
	# place of `Idle_To_Walk_L` still from frame 13 to 26 (a planted foot 46 mm off its place),
	# with 32 every track is whole (kit docs, third-person/clips.md#animation-libraries). Every
	# bone's place and turn in the imported clips against the same file read uncompressed.
	var state := GLTFState.new()
	assert_int(GLTFDocument.new().append_from_file(OWN, state)).is_equal(OK)
	var scene: Node = auto_free(GLTFDocument.new().generate_scene(state))
	var raw: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var imported: AnimationLibrary = load(OWN)
	var compared := 0
	for pair in _pairs():
		for foot in FEET:
			var clip := StringName(pair + "_" + foot)
			assert_bool(raw.has_animation(clip)).override_failure_message(String(clip)).is_true()
			if not raw.has_animation(clip):
				continue
			var packed := imported.get_animation(clip)
			var source := raw.get_animation(clip)
			var tracks := {}
			for track in source.get_track_count():
				var bone := source.track_get_path(track).get_concatenated_subnames()
				tracks["%s %d" % [bone, source.track_get_type(track)]] = track
			var worst_place := 0.0
			var worst_turn := 0.0
			var where := ""
			for track in packed.get_track_count():
				var kind := packed.track_get_type(track)
				var bone := packed.track_get_path(track).get_concatenated_subnames()
				var key := "%s %d" % [bone, kind]
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
							where = "%s frame %d" % [bone, frame]
					elif kind == Animation.TYPE_ROTATION_3D:
						var turn := rad_to_deg(
							packed.rotation_track_interpolate(track, at).angle_to(
								source.rotation_track_interpolate(from, at)
							)
						)
						worst_turn = maxf(worst_turn, turn)
				compared += 1
			var message := (
				"%s: a place %.2f mm off (%s), a turn %.3f degrees off"
				% [clip, worst_place * 1000.0, where, worst_turn]
			)
			print(message)
			assert_float(worst_place).override_failure_message(message).is_less(IMPORT_PLACE)
			assert_float(worst_turn).override_failure_message(message).is_less(IMPORT_TURN)
	assert_int(compared).is_greater(0)


func test_the_player_plays_our_start_and_stop() -> void:
	# The tree of gdstudio #1158 picks a start and a stop by the names it is given
	# (`GaitTransitionSet`, `<base>_L` or `_R`); with the shipped settings it finds ours.
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var animation: CharacterAnimation = player.get_node("Animation")
	CommandDriver.take(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	animation.set_throttled(true)
	var walk := PlayerCommand.new()
	walk.move = Vector2(0.0, 1.0)
	walk.walk = true
	var played := {}
	var step := CommandDriver.tick_seconds()
	for command: PlayerCommand in [walk, PlayerCommand.new()]:
		for tick in 60:
			await get_tree().physics_frame
			player.step(command, step)
			animation.advance(step)
			var clip := animation.gait.transitions.clip
			if clip != &"":
				played[String(clip)] = true
	var names := played.keys()
	print("played: ", names)
	var started := names.any(func(n: String) -> bool: return n.begins_with("gds/Idle_To_Walk_"))
	var stopped := names.any(func(n: String) -> bool: return n.begins_with("gds/Walk_Stop_"))
	assert_bool(started).override_failure_message(str(names)).is_true()
	assert_bool(stopped).override_failure_message(str(names)).is_true()
