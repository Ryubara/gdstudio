# The fixed clips (`assets/animation/fixed/fixed.glb`, built by `build_fixed_clips.py`, kit #1295)
# are the library's clips with one limb swung clear of the limb it passed through on the
# template's bodies: the file is the one the build measured, no limb is deeper than the limit in
# it, every bone but the swung one plays what the library keyed, the swung one leaves and comes
# back to the library's pose, and the game plays them where it played the library's. A leg is
# swivelled about the line from its hip to its ankle instead (kit #1320): its foot bone is keyed
# too, and the foot stays where the library's clip puts it.
extends GdUnitTestSuite

const FIXED := "res://assets/animation/fixed/fixed.glb"
const REPORT := "res://assets/animation/fixed/fixed_clips.json"
const LIBRARIES := {
	&"ual1": "res://assets/animation/universal/ual1.glb",
	&"ual2": "res://assets/animation/universal/ual2.glb",
	&"fixed": FIXED,
}
const RATE := 30.0
## How far a position key the fix did not touch may be from the library's (m), and a rotation
## (degrees): the same keys written by another exporter. The angle between two single-precision
## quaternions that are all but equal reads 0.03 to 0.09 degrees, so the turn's limit is over it.
const SAME := 0.0005
const SAME_TURN := 0.2
## How far a swivelled leg's foot may be from the library's on any frame (m): the build's limit.
const FOOT_STAYS := 0.001

var _report: Dictionary


func before() -> void:
	_report = JSON.parse_string(FileAccess.get_file_as_string(REPORT))


func _clip(clip: StringName) -> Animation:
	var parts := String(clip).split("/")
	return (load(LIBRARIES[StringName(parts[0])]) as AnimationLibrary).get_animation(parts[1])


func _bone(animation: Animation, track: int) -> String:
	return String(animation.track_get_path(track).get_concatenated_subnames())


# A rotation track's value on a frame, of length one. Godot's importer drops the keys a track
# can do without, and the value it then gives between two keys is not quite of length one where
# the library's fingers jitter: `angle_to` of two such quaternions that are equal reads 0.3
# degrees (kit #1320).
func _turn(animation: Animation, track: int, frame: int) -> Quaternion:
	return animation.rotation_track_interpolate(track, frame / RATE).normalized()


# The numbers in the sidecar are the Blender measure's, on the skinned meshes of both template
# bodies and both Quaternius mannequins (`assets/animation/limb_overlap.py`). A fixed.glb that is
# not the file they were read on has not been measured.
func test_the_file_is_the_one_the_build_measured_and_no_limb_is_deeper_than_the_limit() -> void:
	var measured: Dictionary = _report.measured
	(
		assert_str(FileAccess.get_sha256(FIXED))
		. override_failure_message(
			"fixed.glb is not the file fixed_clips.json was measured on: run build_fixed_clips.py"
		)
		. is_equal(measured.sha256)
	)
	assert_float(measured.limit_mm).is_less_equal(5.0)
	assert_array(measured.clear_on).contains_exactly_in_any_order(["form_female", "form_male"])
	for clip: String in _report.clips:
		var entry: Dictionary = _report.clips[clip]
		var crossed_before := false
		for body: String in measured.clear_on:
			var now: Dictionary = entry.after[body]
			(
				assert_float(now.deepest_mm)
				. override_failure_message(
					"%s on %s: %s by %.1f mm" % [clip, body, now.pair, now.deepest_mm]
				)
				. is_less_equal(measured.limit_mm)
			)
			crossed_before = crossed_before or entry.before[body].deepest_mm > measured.limit_mm
		# A clip is in the file because the library's crossed on a template body.
		assert_bool(crossed_before).override_failure_message(clip).is_true()
		for body: String in measured.not_worse_on:
			var limit := maxf(measured.limit_mm, entry.before[body].deepest_mm + 0.5)
			assert_float(entry.after[body].deepest_mm).is_less_equal(limit)
		# A swivelled leg comes with the build's measure of its foot, on every body.
		var swivelled := false
		for swing: Dictionary in entry.swings:
			swivelled = swivelled or swing.way == "swivel"
		assert_bool(entry.has("foot_drift_mm")).override_failure_message(clip).is_equal(swivelled)
		if swivelled:
			assert_float(measured.foot_drift_limit_mm).is_less_equal(FOOT_STAYS * 1000.0)
			assert_int(entry.foot_drift_mm.size()).is_equal(
				measured.clear_on.size() + measured.not_worse_on.size()
			)
			for body: String in entry.foot_drift_mm:
				(
					assert_float(entry.foot_drift_mm[body])
					. override_failure_message("%s on %s: the foot moved" % [clip, body])
					. is_less_equal(measured.foot_drift_limit_mm)
				)


func test_the_file_holds_exactly_the_clips_with_a_stand_in() -> void:
	var library := load(FIXED) as AnimationLibrary
	var names: Array[String] = []
	var bare: Array[String] = []
	for clip in library.get_animation_list():
		names.append("fixed/%s" % clip)
		bare.append(String(clip))
	var stand_ins: Array[String] = []
	for clip: StringName in _fixed_clips():
		stand_ins.append(String(clip))
		assert_bool(CharacterClips.ALL.has(CharacterClips.STAND_INS[clip])).is_true()
	assert_array(names).contains_exactly_in_any_order(stand_ins)
	assert_array(_report.clips.keys()).contains_exactly_in_any_order(bare)


# The fix is a correction of the library's clip, not a new clip: the same length, the same
# tracks, and on every frame every key equal to the library's but the swung bone's rotation,
# which is the library's on the first and last frame and never further from it than the build
# says.
func test_only_the_swung_bone_differs_from_the_library_and_only_inside_the_clip() -> void:
	for fixed_name: StringName in _fixed_clips():
		var fixed := _clip(fixed_name)
		var library := _clip(CharacterClips.STAND_INS[fixed_name])
		var entry: Dictionary = _report.clips[String(fixed_name).get_slice("/", 1)]
		var swung := {}
		for swing: Dictionary in entry.swings:
			swung[swing.bone] = swing.peak_degrees
			# A swivelled leg's foot is turned back to the library's turn in the world.
			if swing.has("keeps"):
				swung[swing.keeps] = swing.keeps_peak_degrees
		assert_float(fixed.length).is_equal_approx(library.length, 0.0001)
		assert_int(fixed.loop_mode).is_equal(library.loop_mode)
		assert_int(fixed.get_track_count()).is_equal(library.get_track_count())
		var frames := roundi(fixed.length * RATE)
		var moved := {}
		for track in fixed.get_track_count():
			var path := fixed.track_get_path(track)
			var type := fixed.track_get_type(track)
			var other := library.find_track(path, type)
			assert_int(other).override_failure_message("%s: %s" % [fixed_name, path]).is_not_equal(
				-1
			)
			if other == -1:
				continue
			var bone := _bone(fixed, track)
			for frame in frames + 1:
				var time := frame / RATE
				if type == Animation.TYPE_POSITION_3D:
					var off := fixed.position_track_interpolate(track, time).distance_to(
						library.position_track_interpolate(other, time)
					)
					(
						assert_float(off)
						. override_failure_message("%s %s" % [fixed_name, bone])
						. is_less(SAME)
					)
					continue
				if type != Animation.TYPE_ROTATION_3D:
					continue
				var degrees := rad_to_deg(
					_turn(fixed, track, frame).angle_to(_turn(library, other, frame))
				)
				if not swung.has(bone) or frame == 0 or frame == frames:
					(
						assert_float(degrees)
						. override_failure_message(
							(
								"%s: %s is %.3f degrees off the library at frame %d"
								% [fixed_name, bone, degrees, frame]
							)
						)
						. is_less(SAME_TURN)
					)
				else:
					assert_float(degrees).is_less_equal(swung[bone] + SAME_TURN)
					moved[bone] = maxf(moved.get(bone, 0.0), degrees)
		for bone: String in swung:
			(
				assert_float(moved.get(bone, 0.0))
				. override_failure_message("%s: %s is not swung" % [fixed_name, bone])
				. is_equal_approx(swung[bone], SAME_TURN)
			)


# In Godot's own pose, on the template's two bodies: the limbs (as the capsules of `BodyMeasure`)
# are no deeper in each other in a fixed clip than in the library's, and every track finds its
# bone.
func test_on_the_template_bodies_the_fixed_clips_overlap_no_more_than_the_librarys() -> void:
	for model: String in [CharacterBodies.FEMALE, CharacterBodies.MALE]:
		var holder: Node3D = auto_free(Node3D.new())
		add_child(holder)
		var body := BodyMeasure.stage(holder, model, LIBRARIES)
		for fixed_name: StringName in _fixed_clips():
			assert_array(Array(body.missing_tracks(fixed_name))).is_empty()
			var fixed: Dictionary = body.measure_clip(fixed_name)
			var library: Dictionary = body.measure_clip(CharacterClips.STAND_INS[fixed_name])
			(
				assert_float(fixed.overlap)
				. override_failure_message(
					(
						"%s on %s: %s by %.1f mm, the library's %.1f mm"
						% [
							fixed_name,
							model,
							fixed.pair,
							fixed.overlap * 1000.0,
							library.overlap * 1000.0
						]
					)
				)
				. is_less_equal(library.overlap + 0.001)
			)
		body.free_nodes()


# A swivelled leg turns about the line from its hip to its ankle, so its foot does not move: on
# the template's two bodies, in Godot's own pose, the ankle and the ball of that foot are where
# the library's clip puts them on every frame, and the foot is turned the same way.
func test_a_swivelled_legs_foot_stays_where_the_library_puts_it() -> void:
	var checked := 0
	for model: String in [CharacterBodies.FEMALE, CharacterBodies.MALE]:
		var holder: Node3D = auto_free(Node3D.new())
		add_child(holder)
		var body := BodyMeasure.stage(holder, model, LIBRARIES)
		for fixed_name: StringName in _fixed_clips():
			var entry: Dictionary = _report.clips[String(fixed_name).get_slice("/", 1)]
			var bones: Array[int] = []
			for swing: Dictionary in entry.swings:
				if swing.way != "swivel":
					continue
				var foot := body.skeleton.find_bone(swing.keeps)
				assert_int(foot).is_not_equal(-1)
				bones.append(foot)
				bones.append_array(body.skeleton.get_bone_children(foot))
			if bones.is_empty():
				continue
			var worst := 0.0
			var turned := 0.0
			var frames := int(entry.last_frame) - int(entry.first_frame) + 1
			for frame in frames:
				var time: float = frame / RATE
				body.pose(CharacterClips.STAND_INS[fixed_name], time)
				var library: Array[Transform3D] = []
				for bone in bones:
					library.append(body.skeleton.get_bone_global_pose(bone))
				body.pose(fixed_name, time)
				for i in bones.size():
					var now := body.skeleton.get_bone_global_pose(bones[i])
					worst = maxf(worst, now.origin.distance_to(library[i].origin))
					turned = maxf(
						turned,
						rad_to_deg(
							now.basis.get_rotation_quaternion().angle_to(
								library[i].basis.get_rotation_quaternion()
							)
						)
					)
			(
				assert_float(worst)
				. override_failure_message(
					(
						"%s on %s: the foot is %.2f mm off the library's"
						% [fixed_name, model, worst * 1e3]
					)
				)
				. is_less(FOOT_STAYS)
			)
			(
				assert_float(turned)
				. override_failure_message(
					"%s on %s: the foot is turned %.2f degrees" % [fixed_name, model, turned]
				)
				. is_less(SAME_TURN)
			)
			checked += 1
		body.free_nodes()
	# Both sword clips, on both bodies.
	assert_int(checked).is_equal(4)


func test_the_game_plays_the_fixed_landing_and_slide_exit() -> void:
	# The landing is our own since gdstudio #1161; the fixed one is its stand-in.
	assert_str(String(CharacterClips.stand_in(CharacterClips.LAND))).is_equal("fixed/Jump_Land")
	assert_str(String(CharacterClips.SLIDE_EXIT)).is_equal("fixed/Slide_Exit")
	var player: Player = auto_free(load("res://gameplay/player/player.tscn").instantiate())
	player.start_at_spawn = false
	add_child(player)
	var animation: CharacterAnimation = player.get_node("Animation")
	var animation_player: AnimationPlayer = player.get_node("AnimationPlayer")
	assert_str(String(animation.land_clip)).is_equal(String(CharacterClips.LAND))
	assert_str(String(animation.slide_exit_clip)).is_equal(String(CharacterClips.SLIDE_EXIT))
	for clip: StringName in _fixed_clips():
		assert_bool(animation_player.has_animation(clip)).is_true()
		assert_bool(animation_player.has_animation(CharacterClips.STAND_INS[clip])).is_true()


# The fixed clips of `CharacterClips.STAND_INS`, which also holds the clips of our own that
# replace a library clip (the library `gds`).
func _fixed_clips() -> Array[StringName]:
	var fixed: Array[StringName] = []
	for clip: StringName in CharacterClips.STAND_INS:
		if String(clip).begins_with("%s/" % CharacterClips.LIBRARY_FIXED):
			fixed.append(clip)
	return fixed
