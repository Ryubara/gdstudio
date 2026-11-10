# Every export of the Ragdoll node is live: each one is changed on a player that is already
# running, as the inspector and the remote inspector do, and its effect on the bones is read. The
# defaults are pinned in test_ragdoll.gd, with the death and get-up behaviour (carry_velocity and
# get_up_time are proved there by what the body does).
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _ragdoll: PlayerRagdoll


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_ragdoll = _player.ragdoll_body
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _bones() -> Array[PhysicalBone3D]:
	var found: Array[PhysicalBone3D] = []
	for entry: Dictionary in PlayerRagdoll.BODIES:
		found.append(_ragdoll.body(entry.bone))
	return found


func _radius(bone: StringName) -> float:
	return (
		((_ragdoll.body(bone).get_node("Shape") as CollisionShape3D).shape as CapsuleShape3D).radius
	)


func test_mass_is_shared_out_between_the_bones() -> void:
	_ragdoll.mass = 90.0
	var total := 0.0
	for bone in _bones():
		total += bone.mass
	assert_float(total).is_equal_approx(90.0, 0.01)
	assert_float(_ragdoll.body(&"pelvis").mass).is_greater(_ragdoll.body(&"hand_l").mass)


func test_thickness_scales_every_capsule() -> void:
	var thick := _radius(&"thigh_l")
	_ragdoll.thickness = 1.5
	assert_int(_ragdoll.body_count()).is_equal(16)
	assert_float(_radius(&"thigh_l")).is_equal_approx(thick * 1.5, 0.0001)


func test_joint_range_scales_the_limits() -> void:
	var swing: float = _ragdoll.body(&"thigh_l").get(&"joint_constraints/swing_span")
	var knee: float = _ragdoll.body(&"calf_l").get(&"joint_constraints/angular_limit_upper")
	_ragdoll.joint_range = 0.5
	assert_float(_ragdoll.body(&"thigh_l").get(&"joint_constraints/swing_span")).is_equal_approx(
		swing * 0.5, 0.01
	)
	(
		assert_float(_ragdoll.body(&"calf_l").get(&"joint_constraints/angular_limit_upper"))
		. is_equal_approx(knee * 0.5, 0.01)
	)


func test_hinge_passes_sets_how_many_hinges_hold_each_elbow_and_knee() -> void:
	# Four elbows and knees, each held by `hinge_passes` hinges.
	assert_int(_ragdoll.hinge_count()).is_equal(16)
	_ragdoll.hinge_passes = 1
	assert_int(_ragdoll.hinge_count()).is_equal(4)
	assert_int(_ragdoll.body_count()).is_equal(16)
	_ragdoll.hinge_passes = 6
	assert_int(_ragdoll.hinge_count()).is_equal(24)


func test_damping_friction_and_bounce_reach_every_bone() -> void:
	_ragdoll.linear_damp = 0.7
	_ragdoll.angular_damp = 5.0
	_ragdoll.friction = 0.3
	_ragdoll.bounce = 0.4
	for bone in _bones():
		assert_float(bone.linear_damp).is_equal_approx(0.7, 0.0001)
		assert_float(bone.angular_damp).is_equal_approx(5.0, 0.0001)
		assert_float(bone.friction).is_equal_approx(0.3, 0.0001)
		assert_float(bone.bounce).is_equal_approx(0.4, 0.0001)


func test_the_layer_and_mask_reach_every_bone() -> void:
	_ragdoll.collision_layer = 32
	_ragdoll.collision_mask = 3
	for bone in _bones():
		assert_int(bone.collision_layer).is_equal(32)
		assert_int(bone.collision_mask).is_equal(3)


func test_a_mask_without_the_floor_lets_the_body_fall_through() -> void:
	_ragdoll.collision_mask = 0
	_player.die()
	await InputSim.ticks(get_tree(), 90)
	assert_float(_ragdoll.hips().y).is_less(-1.0)


func test_a_change_while_dead_keeps_the_body_limp() -> void:
	_player.die()
	await InputSim.ticks(get_tree(), 20)
	_ragdoll.thickness = 1.2
	assert_bool(_ragdoll.is_limp()).is_true()
	assert_bool(_ragdoll.is_active()).is_true()
	await InputSim.ticks(get_tree(), 150)
	assert_float(_ragdoll.hips().y).is_between(0.05, 0.4)
