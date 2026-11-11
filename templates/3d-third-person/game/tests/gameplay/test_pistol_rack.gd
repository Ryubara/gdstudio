# The pistol's slide-rack clip (`assets/animation/pistol/pistol_rack.glb`, kit #1081) imports as a
# library beside the Universal Animation Library and plays on both mannequins: it starts and ends
# on the pose `Pistol_Reload` ends on, the right hand holds the pistol through it with the finger
# off the trigger, and the left hand is on its support grip at the ends and on the slide while it
# racks, within the hold's limits (2 mm in, 5 mm off; `HandContact`), never deeper than the
# reload's passing depth on the way. Measured on the skinned mesh after the hold's modifiers and
# the reach to the slide ran (`RackStage`).
extends GdUnitTestSuite

const LIBRARY := "res://assets/animation/pistol/pistol_rack.glb"
const UAL1 := "res://assets/animation/universal/ual1.glb"
const CLIP := &"Pistol_Rack"
const MODELS: Array[String] = ["female", "male"]
## The clip's last frame (30 a second): every one is measured.
const FRAMES := 28
## How deep the left hand may pass through the gun or the right hand while it moves between its
## places, in metres (the reload's own cap, `test_pistol_hold.gd`).
const PASSING_DEPTH := 0.006
## How far the left hand's bone may stop from its place, in metres.
const REACH := 0.005
## How far the index finger's tip stays from the trigger, in metres.
const OFF_TRIGGER := 0.02
## How far a bone of the clip's ends may be turned from the reload's last frame, in degrees.
const JOIN_DEGREES := 0.05

var _holder: Node3D


func before_test() -> void:
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func test_the_library_holds_the_rack_clip() -> void:
	var library: AnimationLibrary = load(LIBRARY)
	assert_array(library.get_animation_list()).is_equal([CLIP])
	var clip := library.get_animation(CLIP)
	assert_float(clip.length).is_equal_approx(FRAMES / 30.0, 0.002)
	assert_int(clip.loop_mode).is_equal(Animation.LOOP_NONE)
	var rack := load(RackStage.RACK) as SlideRack
	assert_str(String(rack.clip)).is_equal("pistol/" + CLIP)


func test_every_track_drives_a_bone_of_the_mannequins() -> void:
	var clip := (load(LIBRARY) as AnimationLibrary).get_animation(CLIP)
	for model in MODELS:
		var body: Node3D = auto_free((load(HoldStage.MODELS[model]) as PackedScene).instantiate())
		add_child(body)
		var skeleton: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
		var driven := {}
		var names := {}
		for track in clip.get_track_count():
			var path := clip.track_get_path(track)
			var node := body.get_node_or_null(NodePath(path.get_concatenated_names()))
			assert_object(node).override_failure_message("%s: %s" % [model, path]).is_same(skeleton)
			var bone := skeleton.find_bone(String(path.get_concatenated_subnames()))
			assert_int(bone).override_failure_message(str(path)).is_greater_equal(0)
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				driven[bone] = true
				names[skeleton.get_bone_name(bone)] = true
		# The import drops a track that never leaves the rest pose (ten bones of the 65).
		assert_int(driven.size()).is_greater_equal(50)
		for side: String in ["l", "r"]:
			for bone: String in [
				"upperarm", "lowerarm", "hand", "index_01", "thumb_03", "pinky_02"
			]:
				var bone_name := "%s_%s" % [bone, side]
				assert_bool(names.has(bone_name)).override_failure_message(bone_name).is_true()
		for bone_name: String in ["spine_02", "spine_03", "Head", "pelvis"]:
			assert_bool(names.has(bone_name)).override_failure_message(bone_name).is_true()


# The clip joins the reload: every bone's rotation on its first and its last frame is the one
# `Pistol_Reload` ends on (which is the one it starts on, so the rack also follows a plain aim).
func test_the_clip_starts_and_ends_on_the_reloads_last_frame() -> void:
	var clip := (load(LIBRARY) as AnimationLibrary).get_animation(CLIP)
	var reload := (load(UAL1) as AnimationLibrary).get_animation(&"Pistol_Reload")
	var compared := 0
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var other := reload.find_track(clip.track_get_path(track), Animation.TYPE_ROTATION_3D)
		if other < 0:
			continue
		compared += 1
		var joins := reload.rotation_track_interpolate(other, reload.length)
		var starts := reload.rotation_track_interpolate(other, 0.0)
		for time: float in [0.0, clip.length]:
			var mine := clip.rotation_track_interpolate(track, time)
			for theirs: Quaternion in [joins, starts]:
				(
					assert_float(rad_to_deg(mine.angle_to(theirs)))
					. override_failure_message(
						(
							"%s at %.2f s is %.2f degrees from the reload's"
							% [clip.track_get_path(track), time, rad_to_deg(mine.angle_to(theirs))]
						)
					)
					. is_less(JOIN_DEGREES)
				)
	assert_int(compared).is_greater_equal(50)


func test_the_shares_run_in_order_and_the_slide_follows_the_hand() -> void:
	var rack := load(RackStage.RACK) as SlideRack
	var order: Array[float] = [
		rack.leave.x, rack.leave.y, rack.grip.x, rack.grip.y, rack.pull.x, rack.pull.y
	]
	order.append_array([rack.release.x, rack.release.y, rack.back.x, rack.back.y])
	for index in order.size() - 1:
		assert_float(order[index + 1]).is_greater_equal(order[index])
	assert_float(rack.release.x).is_equal_approx(rack.pull.y, 0.0001)
	assert_float(rack.support_weight(0.0)).is_equal(1.0)
	assert_float(rack.support_weight(1.0)).is_equal(1.0)
	assert_float(rack.support_weight(rack.grip.y)).is_equal(0.0)
	# The reach has the hand from before it closes on the slide until after it has let go.
	assert_float(rack.hand_weight(0.0)).is_equal(0.0)
	assert_float(rack.hand_weight(rack.grip.x)).is_equal(1.0)
	assert_float(rack.hand_weight(rack.release.y)).is_equal(1.0)
	assert_float(rack.hand_weight(1.0)).is_equal(0.0)
	assert_float(rack.places_from).is_less_equal(rack.reach.x)
	assert_float(rack.places_to).is_greater_equal(rack.away.y)
	assert_int(rack.places.size()).is_greater(10)
	assert_float(rack.slide_pull(rack.pull.x)).is_equal(0.0)
	assert_float(rack.slide_pull(rack.pull.y)).is_equal(1.0)
	# Let go, the slide is home within `slam`.
	assert_float(rack.slide_pull(rack.release.x + rack.slam)).is_equal_approx(0.0, 0.0001)
	assert_float(rack.travel.length()).is_between(0.03, 0.06)
	# On the slide the hand's place is its place on the closed slide moved by the slide's travel.
	var closed := rack.hand_place(rack.grip.y)
	var pulled := rack.hand_place(rack.pull.y)
	assert_vector(closed.origin).is_equal_approx(rack.hand.origin, Vector3.ONE * 0.0005)
	assert_vector(pulled.origin - closed.origin).is_equal_approx(rack.travel, Vector3.ONE * 0.0005)


func test_the_right_hand_holds_the_pistol_through_the_rack() -> void:
	for model in MODELS:
		var made: RackStage = await RackStage.make(_holder, model)
		for frame in FRAMES + 1:
			var share := float(frame) / FRAMES
			made.pose(share)
			await made.stage.settle()
			var tag := "%s rack frame %d r:" % [model, frame]
			var parts := made.stage.contact.measure("r")
			var fails := HandContact.failures(tag, parts, HoldStage.RIGHT_CONTACTS)
			assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
			var trigger := made.stage.pistol.find_child("Trigger", true, false) as Node3D
			var off := made.stage.contact.part_distance_to(
				"r", "index_tip", trigger.global_position
			)
			(
				assert_float(off)
				. override_failure_message(
					"%s the finger is %.1f mm from the trigger" % [tag, off * 1e3]
				)
				. is_greater(OFF_TRIGGER)
			)
		made.free_stage()


# The left hand through the rack: on its support grip at the clip's ends, on the slide from the
# share it has closed on it to the share it lets go (wherever the slide is by then), and no deeper
# than `PASSING_DEPTH` in the gun or the right hand on the way.
func test_the_left_hand_grips_the_slide_and_pulls_it_back() -> void:
	for model in MODELS:
		var made: RackStage = await RackStage.make(_holder, model)
		var rack := made.rack
		var gripped := 0
		for frame in FRAMES + 1:
			var share := float(frame) / FRAMES
			made.pose(share)
			await made.stage.settle()
			var tag := "%s rack frame %d l:" % [model, frame]
			var parts := made.stage.contact.measure("l", true)
			if frame == 0 or frame == FRAMES:
				var fails := HandContact.failures(tag, parts, HoldStage.LEFT_CONTACTS)
				assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
			elif rack.is_gripping(share):
				gripped += 1
				var fails := HandContact.failures(tag, parts, RackStage.SLIDE_CONTACTS)
				assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
				var gap := made.reach(share)
				(
					assert_float(gap)
					. override_failure_message(
						"%s %.1f mm from its place on the slide" % [tag, gap * 1e3]
					)
					. is_less(REACH)
				)
			else:
				for part: String in parts:
					var depth: float = -parts[part].distance
					(
						assert_float(depth)
						. override_failure_message(
							"%s %s %.1f mm inside on the way" % [tag, part, depth * 1e3]
						)
						. is_less(PASSING_DEPTH)
					)
		assert_int(gripped).is_greater_equal(4)
		made.free_stage()


# The slide moves with the hand: at the end of the pull the gripping hand and the `Slide` node are
# both `travel` back from where they closed.
func test_the_hand_and_the_slide_travel_together() -> void:
	var made: RackStage = await RackStage.make(_holder, "female")
	var rack := made.rack
	var rest := made.slide.position
	made.pose(rack.grip.y)
	await made.stage.settle()
	var gun := made.stage.pistol.global_transform.affine_inverse()
	var closed := gun * made.stage.bone_origin(&"hand_l")
	assert_vector(made.slide.position).is_equal_approx(rest, Vector3.ONE * 1e-5)
	made.pose(rack.pull.y)
	await made.stage.settle()
	gun = made.stage.pistol.global_transform.affine_inverse()
	var pulled := gun * made.stage.bone_origin(&"hand_l")
	assert_vector(made.slide.position - rest).is_equal_approx(rack.travel, Vector3.ONE * 1e-5)
	assert_vector(pulled - closed).is_equal_approx(rack.travel, Vector3.ONE * 0.002)
	made.pose(rack.release.x + rack.slam)
	assert_vector(made.slide.position).is_equal_approx(rest, Vector3.ONE * 1e-5)
	made.free_stage()


# Why the reach is there: the clip's own arm puts the hand on the slide of the mannequin it was
# keyed on, with the pistol where the clip's right hand has it; it misses on the other mannequin,
# whose arms are longer, and on either once the hold moves the pistol after the clip (the carried
# arm held out from the thigh, `WeaponHold.carry_arm_out`).
func test_the_clips_own_arm_is_on_the_slide_only_where_it_was_keyed() -> void:
	var gaps := {}
	for model in MODELS:
		for carried: bool in [false, true]:
			var made: RackStage = await RackStage.make(_holder, model)
			made.reach_on = false
			if not carried:
				made.stage.hold.set(&"carry_arm_out", 0.0)
			made.pose(made.rack.pull.x)
			await made.stage.settle()
			gaps["%s %s" % [model, "carried" if carried else "as keyed"]] = made.reach(
				made.rack.pull.x
			)
			made.free_stage()
	assert_float(gaps["female as keyed"]).is_less(0.002)
	assert_float(gaps["male as keyed"]).is_greater(0.01)
	assert_float(gaps["female carried"]).is_greater(0.01)
	assert_float(gaps["male carried"]).is_greater(0.01)
