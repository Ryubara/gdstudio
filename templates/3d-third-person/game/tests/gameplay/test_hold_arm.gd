# The two small rules the pistol hold's modifiers add to a straight reach and a straight blend:
# an arm too short for the hand's place backs the hand off along a line to the nearest place it
# reaches (kit #1078, `HoldArm.backed_off`), and a bone blended to a second pose goes through a
# pose between when it has one (kit #1079, `HandPoseModifier.second_via`).
extends GdUnitTestSuite

const ARM := 0.5

var _read := Quaternion.IDENTITY


func test_a_place_within_reach_is_not_backed_off() -> void:
	assert_float(HoldArm.backed_off(Vector3(0.0, 0.0, 0.4), Vector3.BACK, ARM)).is_equal(0.0)
	assert_float(HoldArm.backed_off(Vector3(0.0, 0.0, 0.4), Vector3.FORWARD, ARM)).is_equal(0.0)


func test_a_place_out_of_reach_backs_off_to_the_first_place_the_arm_reaches() -> void:
	# 0.7 m ahead of the shoulder, the line straight back to it: 0.2 m back is at the arm's end.
	var back := HoldArm.backed_off(Vector3(0.0, 0.0, 0.7), Vector3.FORWARD, ARM)
	assert_float(back).is_equal_approx(0.2, 1e-5)
	# A line that slants past the shoulder: the place it gives is exactly an arm from it.
	var line := Vector3(-0.3, -0.2, -1.0).normalized()
	var to_goal := Vector3(0.1, 0.2, 0.7)
	back = HoldArm.backed_off(to_goal, line, ARM)
	assert_float(back).is_greater(0.0)
	assert_float((to_goal + line * back).length()).is_equal_approx(ARM, 1e-5)


func test_a_line_that_never_comes_within_reach_gives_its_nearest_place() -> void:
	# The line passes the shoulder 0.6 m to the side: its nearest place is 0.7 m along it.
	var back := HoldArm.backed_off(Vector3(0.6, 0.0, 0.7), Vector3.FORWARD, ARM)
	assert_float(back).is_equal_approx(0.7, 1e-5)


func test_a_line_that_leads_away_from_the_shoulder_is_not_followed() -> void:
	assert_float(HoldArm.backed_off(Vector3(0.0, 0.0, 0.7), Vector3.BACK, ARM)).is_equal(0.0)


func test_a_bone_goes_to_its_second_pose_through_the_pose_between() -> void:
	var skeleton: Skeleton3D = auto_free(Skeleton3D.new())
	skeleton.add_bone("finger")
	add_child(skeleton)
	var pose := HandPose.new()
	pose.rotations = {&"finger": Quaternion.IDENTITY}
	var via := HandPose.new()
	via.rotations = {&"finger": Quaternion(Vector3.UP, 1.0)}
	var second := HandPose.new()
	second.rotations = {&"finger": Quaternion(Vector3.RIGHT, 1.0)}
	var modifier := HandPoseModifier.new()
	modifier.pose = pose
	modifier.second = second
	modifier.second_via = via
	skeleton.add_child(modifier)
	skeleton.skeleton_updated.connect(func() -> void: _read = skeleton.get_bone_pose_rotation(0))
	var expected: Dictionary[float, Quaternion] = {
		0.0: Quaternion.IDENTITY,
		0.25: Quaternion(Vector3.UP, 0.5),
		0.5: Quaternion(Vector3.UP, 1.0),
		0.75: Quaternion(Vector3.UP, 1.0).slerp(Quaternion(Vector3.RIGHT, 1.0), 0.5),
		1.0: Quaternion(Vector3.RIGHT, 1.0),
	}
	for weight: float in expected:
		modifier.second_weight = weight
		# A written pose makes the skeleton run its modifiers on the next frame.
		skeleton.set_bone_pose_rotation(0, Quaternion.IDENTITY)
		await get_tree().process_frame
		await get_tree().process_frame
		(
			assert_bool(_read.is_equal_approx(expected[weight]))
			. override_failure_message(
				"at %.2f the bone is %s, not %s" % [weight, _read, expected[weight]]
			)
			. is_true()
		)
	# With no pose between, the blend is the straight one.
	modifier.second_via = null
	modifier.second_weight = 0.5
	skeleton.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	await get_tree().process_frame
	await get_tree().process_frame
	(
		assert_bool(
			_read.is_equal_approx(Quaternion.IDENTITY.slerp(second.rotations[&"finger"], 0.5))
		)
		. is_true()
	)
