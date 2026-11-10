# What makes the ragdoll look like a body (gdstudio #872): limbs rest on the trunk and on each
# other instead of passing through it, elbows and knees are hinges, a death in the air goes limp
# there, the layers keep everything else off the bones, and the cost stays small (a cap on limp
# ragdolls, sleep after settling, the clip when the ragdoll declines). The exports of the node are
# in test_ragdoll_live.gd, dying and getting up in test_ragdoll.gd, the stress test in
# test_ragdoll_physics.gd.
extends GdUnitTestSuite

## A limb resting on the trunk overlaps it by a few centimetres (the engine's contact softness and
## the capsules being rounder than a body); through it is 13 to 17 cm. Metres.
const MOST_OVERLAP := 0.06
## A joint's limit is a soft stop against a load (`test_ragdoll_physics.gd`). Degrees.
const LIMIT_SLACK := 25.0

var _arena: PlayArena
var _player: Player
var _ragdoll: PlayerRagdoll


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_ragdoll = _player.ragdoll_body
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


# --- limbs meet ---


func test_limbs_do_not_pass_through_the_body_after_a_fall() -> void:
	_player.die()
	await _ticks(20)
	var deepest := 0.0
	var worst := ""
	for _step in 20:
		await _ticks(10)
		var found := _deepest_overlap()
		if found[0] > deepest:
			deepest = found[0]
			worst = found[1]
	(
		assert_float(deepest)
		. override_failure_message("%s overlap by %.1f cm" % [worst, deepest * 100.0])
		. is_less(MOST_OVERLAP)
	)


func test_limbs_do_not_pass_through_the_body_after_a_run_and_a_shove() -> void:
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await _ticks(40)
	_player.die()
	# A shove from the side, harder the higher the bone, topples the body onto its side.
	for entry: Dictionary in PlayerRagdoll.BODIES:
		var bone := _ragdoll.body(entry.bone)
		bone.linear_velocity += Vector3(3.5 * clampf(bone.global_position.y / 1.7, 0.0, 1.2), 0, 0)
	var deepest := 0.0
	var worst := ""
	for _step in 20:
		await _ticks(10)
		var found := _deepest_overlap()
		if found[0] > deepest:
			deepest = found[0]
			worst = found[1]
	(
		assert_float(deepest)
		. override_failure_message("%s overlap by %.1f cm" % [worst, deepest * 100.0])
		. is_less(MOST_OVERLAP)
	)


# The deepest overlap between two capsules that are not a body and the one it hangs from, in
# metres, and which pair.
func _deepest_overlap() -> Array:
	var skeleton := _player.model.skeleton()
	var deepest := 0.0
	var worst := ""
	var entries := PlayerRagdoll.BODIES
	for i in entries.size():
		for j in range(i + 1, entries.size()):
			var a: StringName = entries[i].bone
			var b: StringName = entries[j].bone
			if _ragdoll._parent_body(skeleton, a) == b or _ragdoll._parent_body(skeleton, b) == a:
				continue
			var found := _capsule_overlap(_ragdoll.body(a), _ragdoll.body(b))
			if found > deepest:
				deepest = found
				worst = "%s and %s" % [a, b]
	return [deepest, worst]


func _capsule_overlap(a: PhysicalBone3D, b: PhysicalBone3D) -> float:
	var seg_a := _segment(a)
	var seg_b := _segment(b)
	var points := Geometry3D.get_closest_points_between_segments(
		seg_a[0], seg_a[1], seg_b[0], seg_b[1]
	)
	return seg_a[2] + seg_b[2] - points[0].distance_to(points[1])


# A capsule's axis as two end points and its radius, in world space.
func _segment(bone: PhysicalBone3D) -> Array:
	var shape := bone.get_node("Shape") as CollisionShape3D
	var capsule := shape.shape as CapsuleShape3D
	var axis := shape.global_basis.y.normalized()
	var half := maxf(capsule.height / 2.0 - capsule.radius, 0.0)
	return [
		shape.global_position - axis * half, shape.global_position + axis * half, capsule.radius
	]


# --- layers ---


func test_the_bones_have_their_own_layer_and_only_the_level_and_themselves_in_the_mask() -> void:
	for entry: Dictionary in PlayerRagdoll.BODIES:
		var bone := _ragdoll.body(entry.bone)
		assert_int(bone.collision_layer).is_equal(16)
		assert_int(bone.collision_mask).is_equal(17)


func test_a_ray_that_looks_for_the_level_passes_through_the_lying_body() -> void:
	_player.die()
	await _ticks(180)
	var from := _ragdoll.hips() + Vector3.UP * 2.0
	var to := _ragdoll.hips() + Vector3.DOWN * 0.1
	var space := _player.get_world_3d().direct_space_state
	var level := PhysicsRayQueryParameters3D.create(from, to, 1)
	var bones := PhysicsRayQueryParameters3D.create(from, to, 16)
	var found_by_level := space.intersect_ray(level)
	var found_by_bones := space.intersect_ray(bones)
	# The camera's walls, the shots and the player's ground probes all look at layer 1: they see
	# the floor (or nothing in this arena) and never a bone.
	if not found_by_level.is_empty():
		assert_bool(found_by_level.collider is PhysicalBone3D).is_false()
	(
		assert_bool(not found_by_bones.is_empty() and found_by_bones.collider is PhysicalBone3D)
		. is_true()
	)


# --- hinges ---


func test_elbows_and_knees_are_hinges_the_same_on_both_sides() -> void:
	for pair in [[&"lowerarm_l", &"lowerarm_r"], [&"calf_l", &"calf_r"]]:
		var left := _entry(pair[0])
		var right := _entry(pair[1])
		assert_str(String(left.joint)).is_equal("hinge")
		assert_str(String(right.joint)).is_equal("hinge")
		assert_vector(left.range).is_equal(right.range)
		assert_int(_ragdoll.body(pair[0]).joint_type).is_equal(PhysicalBone3D.JOINT_TYPE_HINGE)
		assert_int(_ragdoll.body(pair[1]).joint_type).is_equal(PhysicalBone3D.JOINT_TYPE_HINGE)


func test_elbows_and_knees_never_lean_sideways_or_roll_after_a_run() -> void:
	InputSim.key(KEY_W, true)
	await _ticks(30)
	_player.die()
	var worst := 0.0
	var where := ""
	for _step in 10:
		await _ticks(20)
		for entry: Dictionary in PlayerRagdoll.BODIES:
			if entry.joint != &"hinge":
				continue
			var angles := _hinge_angles(entry)
			var off := maxf(absf(angles.y), absf(angles.z))
			if off > worst:
				worst = off
				where = "%s lean %.0f roll %.0f" % [entry.bone, angles.y, angles.z]
	assert_float(worst).override_failure_message("a hinge turned off its axis: %s" % where).is_less(
		LIMIT_SLACK
	)


# The angles of a hinge joint from the straight limb, in degrees: x the bend (about the hinge),
# y the sideways lean and z the roll about the bone.
func _hinge_angles(entry: Dictionary) -> Vector3:
	var skeleton := _player.model.skeleton()
	var parent: StringName = _ragdoll._parent_body(skeleton, entry.bone)
	var rest := _ragdoll.rest_body(parent).basis.inverse() * _ragdoll.rest_body(entry.bone).basis
	var now := _ragdoll.body(parent).global_basis.inverse() * _ragdoll.body(entry.bone).global_basis
	var frame := PlayerRagdoll.hinge_frame(entry.axis)
	var q := Quaternion(frame.inverse() * rest.inverse() * now * frame).normalized()
	if q.w < 0.0:
		q = -q
	return Vector3(
		rad_to_deg(2.0 * atan2(q.z, q.w)),
		rad_to_deg(2.0 * asin(clampf(q.y, -1.0, 1.0))),
		rad_to_deg(2.0 * asin(clampf(q.x, -1.0, 1.0)))
	)


func _entry(bone: StringName) -> Dictionary:
	for entry: Dictionary in PlayerRagdoll.BODIES:
		if entry.bone == bone:
			return entry
	return {}


func test_a_turn_is_held_inside_the_limits_of_its_joint() -> void:
	var ragdoll := auto_free(PlayerRagdoll.new()) as PlayerRagdoll
	var elbow := _entry(&"lowerarm_l")
	var half: float = (elbow.range.y - elbow.range.x) / 2.0
	# Too far a bend with a lean and a roll in it: the lean and roll go, the bend stops at the range.
	var turn := (
		Basis(Vector3.BACK, deg_to_rad(half + 60.0))
		* Basis(Vector3.UP, deg_to_rad(40.0))
		* Basis(Vector3.RIGHT, deg_to_rad(50.0))
	)
	var held := ragdoll.inside_limits(elbow, turn)
	var q := Quaternion(held)
	assert_float(rad_to_deg(q.get_angle())).is_equal_approx(half, 0.5)
	assert_float(absf(q.get_axis().dot(Vector3.BACK))).is_greater(0.999)
	# A turn inside the range stays as it is.
	var inside := Basis(Vector3.BACK, deg_to_rad(half - 10.0))
	(
		assert_float(rad_to_deg(Quaternion(ragdoll.inside_limits(elbow, inside)).get_angle()))
		. is_equal_approx(half - 10.0, 0.5)
	)
	# A cone: a swing of 150 degrees and a twist of 120 stop at the spans.
	var hip := _entry(&"thigh_l")
	var wide := Basis(Vector3.UP, deg_to_rad(150.0)) * Basis(Vector3.RIGHT, deg_to_rad(120.0))
	var cut := Quaternion(ragdoll.inside_limits(hip, wide))
	assert_float(rad_to_deg(cut.get_angle())).is_less(hip.swing + hip.twist + 0.5)
	var swing_part := cut * Quaternion(cut.x, 0.0, 0.0, cut.w).normalized().inverse()
	assert_float(rad_to_deg(swing_part.get_angle())).is_equal_approx(hip.swing, 0.5)


# --- mass ---


func test_the_mass_follows_the_body_segments() -> void:
	var total := 0.0
	for entry: Dictionary in PlayerRagdoll.BODIES:
		total += _ragdoll.body(entry.bone).mass
	assert_float(total).is_equal_approx(_ragdoll.mass, 0.01)
	# Winter and Dempster: a thigh is 10 per cent of the body, a hand 0.6, the head 8.1.
	assert_float(_ragdoll.body(&"thigh_l").mass / total).is_equal_approx(0.10 / 0.985, 0.002)
	assert_float(_ragdoll.body(&"hand_l").mass / total).is_equal_approx(0.006 / 0.985, 0.002)
	assert_float(_ragdoll.body(&"Head").mass / total).is_equal_approx(0.081 / 0.985, 0.002)


# --- going limp in the air ---


func test_a_death_at_the_top_of_a_jump_goes_limp_in_the_air() -> void:
	InputSim.key(KEY_SPACE, true)
	await _ticks(3)
	InputSim.key(KEY_SPACE, false)
	# Up to the top of the jump.
	for _tick in 90:
		await _ticks(1)
		if _player.velocity.y <= 0.3:
			break
	assert_bool(_player.is_on_floor()).is_false()
	_player.die()
	var hand := _ragdoll.body(&"hand_l")
	var pelvis := _ragdoll.body(&"pelvis")
	var foot := _ragdoll.body(&"foot_l")
	var hand_start := hand.global_position - pelvis.global_position
	var foot_start := foot.global_position - pelvis.global_position
	await _ticks(14)
	assert_bool(_player.is_on_floor()).is_false()
	var hand_moved := (hand.global_position - pelvis.global_position - hand_start).length()
	var foot_moved := (foot.global_position - pelvis.global_position - foot_start).length()
	# Limbs are let drop: with one velocity for every bone nothing would move against the pelvis
	# until the body lands.
	assert_float(maxf(hand_moved, foot_moved)).is_greater(0.2)


func test_without_the_pose_velocity_and_the_relax_a_death_in_the_air_keeps_its_pose() -> void:
	_ragdoll.pose_velocity = false
	_ragdoll.relax_gravity = 0.0
	InputSim.key(KEY_SPACE, true)
	await _ticks(3)
	InputSim.key(KEY_SPACE, false)
	for _tick in 90:
		await _ticks(1)
		if _player.velocity.y <= 0.3:
			break
	_player.die()
	var hand := _ragdoll.body(&"hand_l")
	var pelvis := _ragdoll.body(&"pelvis")
	var start := hand.global_position - pelvis.global_position
	await _ticks(14)
	assert_float((hand.global_position - pelvis.global_position - start).length()).is_less(0.12)


# --- cost ---


func test_a_death_over_the_cap_plays_the_death_clip_and_a_free_slot_brings_the_ragdoll_back(
) -> void:
	var second := _arena.add_player(Vector3(6.0, 0.0, 0.0))
	var third := _arena.add_player(Vector3(12.0, 0.0, 0.0))
	await _ticks(4)
	for who: Player in [_player, second, third]:
		who.ragdoll_body.max_active = 2
	_player.die()
	second.die()
	third.die()
	assert_bool(_player.ragdoll_body.is_limp()).is_true()
	assert_bool(second.ragdoll_body.is_limp()).is_true()
	assert_bool(third.is_dead()).is_true()
	assert_bool(third.died_by_clip).is_true()
	assert_bool(third.ragdoll_body.is_limp()).is_false()
	var player_clip := third.get_node("Animation") as PlayerAnimation
	await _ticks(10)
	assert_str(String(player_clip.animation_player.current_animation)).is_equal(
		String(CharacterClips.DEATH)
	)
	# Getting up frees the slot; the third dies as a ragdoll the next time.
	third.revive()
	_player.revive()
	assert_bool(third.died_by_clip).is_false()
	third.die()
	assert_bool(third.ragdoll_body.is_limp()).is_true()
	assert_bool(third.died_by_clip).is_false()
	for who: Player in [_player, second, third]:
		who.ragdoll_body.max_active = 4
		who.revive()


func test_a_settled_body_sleeps_and_says_so() -> void:
	_ragdoll.settle_time = 3.0
	var seen := [false]
	_ragdoll.settled.connect(func() -> void: seen[0] = true)
	_player.die()
	# How long a body takes to lie still depends on the pose it died in (the animation's clock is
	# real time): about 3 s after the fall in most, a few more in an unlucky one.
	for _second in 15:
		await _ticks(60)
		if _ragdoll.is_settled():
			break
	assert_bool(seen[0]).is_true()
	assert_bool(_ragdoll.is_settled()).is_true()
	for entry: Dictionary in PlayerRagdoll.BODIES:
		var asleep: bool = PhysicsServer3D.body_get_state(
			_ragdoll.body(entry.bone).get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING
		)
		assert_bool(asleep).override_failure_message("%s is awake" % entry.bone).is_true()
	# A settled body no longer counts toward the cap.
	assert_bool(_ragdoll.can_start()).is_true()
