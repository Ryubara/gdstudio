# How the body answers a shot (#876): a lethal shot throws the hit bone along it, a hit that does
# not kill flinches the hit part and gives the clip the skeleton back in its time, and a shot on a
# body already lying pushes the bone it hits and leaves a mark on that bone, which goes when the
# body gets up. Real projectiles in the physics world.
extends GdUnitTestSuite

## The most ticks a dead body gets to lie still (20 s).
const SETTLE_TICKS := 1200

var _arena: PlayArena
var _target: Character
var _zones: HitZones
var _reaction: HitReaction
var _ragdoll: CharacterRagdoll


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	_target = HitRange.target(_arena, Vector3(0.0, 0.0, -4.0))
	_zones = HitRange.zones_of(_target)
	_reaction = _target.get_node("HitReaction") as HitReaction
	_ragdoll = _target.ragdoll_body
	_ragdoll.settle_time = 1.0
	await InputSim.ticks(get_tree(), 6)
	HitRange.freeze(_target)
	await InputSim.ticks(get_tree(), 2)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


# The velocity of `bone`'s body along `along`, in the tick after a death made by `kill`.
func _speed_after(kill: Callable, bone: StringName, along: Vector3) -> float:
	kill.call()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return _ragdoll.body(bone).linear_velocity.dot(along)


func test_a_lethal_headshot_throws_the_head_along_the_shot() -> void:
	var line := HitRange.line_to(_target, _zones.zone(&"head"))
	var along: Vector3 = line[1]
	Health.of(_target).value = 1.0
	await HitRange.shoot(get_tree(), _arena, line[0], along)
	assert_bool(_target.is_dead()).is_true()
	assert_bool(_ragdoll.is_limp()).is_true()
	await get_tree().physics_frame
	var thrown := _ragdoll.body(&"Head").linear_velocity.dot(along)
	# The same death with no shot: the head only falls.
	var other := HitRange.target(_arena, Vector3(3.0, 0.0, -4.0))
	await InputSim.ticks(get_tree(), 6)
	HitRange.freeze(other)
	await InputSim.ticks(get_tree(), 2)
	other.die()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fallen := other.ragdoll_body.body(&"Head").linear_velocity.dot(along)
	assert_float(thrown).is_greater(2.0)
	assert_float(thrown - fallen).is_greater(2.0)


func test_a_lethal_body_shot_throws_the_chest_along_the_shot() -> void:
	var line := HitRange.line_to(_target, _zones.zone(&"chest"))
	var along: Vector3 = line[1]
	Health.of(_target).value = 1.0
	await HitRange.shoot(get_tree(), _arena, line[0], along)
	await get_tree().physics_frame
	assert_float(_ragdoll.body(&"spine_03").linear_velocity.dot(along)).is_greater(0.5)


func test_a_hit_that_does_not_kill_flinches_the_part_and_returns_to_the_clip_in_its_time() -> void:
	var line := HitRange.line_to(_target, _zones.zone(&"chest"))
	var ends := [0]
	_reaction.flinch_ended.connect(func() -> void: ends[0] += 1)
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_target.is_dead()).is_false()
	assert_bool(_reaction.is_flinching()).is_true()
	var bones := _reaction.flinch_bones()
	assert_array(bones).contains([&"spine_03", &"Head", &"upperarm_l", &"hand_r"])
	for leg in HitReaction.LEGS:
		assert_array(bones).not_contains([leg])
	assert_array(bones).not_contains([&"pelvis", &"spine_01"])
	var simulator := _ragdoll.simulator()
	assert_bool(_ragdoll.body(&"spine_03").is_simulating_physics()).is_true()
	assert_bool(_ragdoll.body(&"thigh_l").is_simulating_physics()).is_false()
	assert_float(simulator.influence).is_greater(0.5)
	# The chest is pushed off the clip's pose along the shot.
	var most := 0.0
	var ticks := ceili(_reaction.flinch_time * Engine.physics_ticks_per_second) + 3
	for tick in ticks:
		await get_tree().physics_frame
		if _reaction.is_flinching():
			var off := _ragdoll.body(&"spine_03").global_position
			most = maxf(most, off.distance_to(_ragdoll.animated_body(&"spine_03").origin))
	assert_float(most).is_greater(0.01)
	assert_bool(_reaction.is_flinching()).is_false()
	assert_int(ends[0]).is_equal(1)
	assert_bool(simulator.is_simulating_physics()).is_false()
	assert_bool(simulator.active).is_false()
	assert_float(simulator.influence).is_equal(1.0)


func test_a_hit_on_a_leg_flinches_the_trunk_and_never_a_leg() -> void:
	assert_array(_reaction.flinch_set(&"calf_l")).contains([&"spine_01", &"spine_03", &"Head"])
	assert_array(_reaction.flinch_set(&"calf_l")).not_contains([&"calf_l", &"thigh_l"])
	assert_array(_reaction.flinch_set(&"hand_l")).is_equal([&"hand_l"])
	assert_array(_reaction.flinch_set(&"lowerarm_r")).contains_exactly([&"lowerarm_r", &"hand_r"])
	# A bone with no body of its own counts as the body above it (the neck as the chest).
	assert_str(String(_reaction.body_for(&"neck_01"))).is_equal("spine_03")


func test_with_the_flinch_off_a_hit_moves_no_bone() -> void:
	_reaction.flinch_enabled = false
	var line := HitRange.line_to(_target, _zones.zone(&"chest"))
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_reaction.is_flinching()).is_false()
	assert_bool(_ragdoll.simulator().is_simulating_physics()).is_false()


func test_a_death_during_a_flinch_takes_the_whole_body() -> void:
	var line := HitRange.line_to(_target, _zones.zone(&"chest"))
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_reaction.is_flinching()).is_true()
	Health.of(_target).value = 1.0
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_ragdoll.is_limp()).is_true()
	assert_bool(_reaction.is_flinching()).is_false()
	await InputSim.ticks(get_tree(), 5)
	assert_bool(_ragdoll.body(&"thigh_l").is_simulating_physics()).is_true()


# The farthest a flinch body gets from the clip's pose over the first `ticks` ticks of a chest
# shot, in metres (INF for a body that is not finite).
func _flinch_spread(ticks: int) -> float:
	var line := HitRange.line_to(_target, _zones.zone(&"chest"))
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_reaction.is_flinching()).is_true()
	var most := 0.0
	for tick in ticks:
		for key in _reaction.flinch_bones():
			var body := _ragdoll.body(key)
			if not body.global_transform.is_finite():
				return INF
			most = maxf(most, body.global_position.distance_to(_ragdoll.animated_body(key).origin))
		await get_tree().physics_frame
	return most


# gdstudio #1326: the bodies a flinch leaves out follow the clip from where the physics server
# has them, which was where the last death left them, a metre away: their first move threw the
# flinching bones 1.1 m in a tick (and, in the AI soak, now and then to NaN).
func test_a_flinch_after_getting_up_starts_from_the_clip_pose() -> void:
	_target.die()
	await InputSim.ticks(get_tree(), 60)
	_target.revive()
	await InputSim.ticks(get_tree(), 120)
	HitRange.freeze(_target)
	await InputSim.ticks(get_tree(), 2)
	assert_float(await _flinch_spread(6)).is_less(0.1)


# gdstudio #1326: the push landed where the shot did, so a forearm (a thin capsule of a kilogram)
# spun at the engine's limit (47 rad/s; a swing at 3 m/s is about 25) and, in the AI soak, its
# arm left at 500 m/s. It lands on the body's middle and gives it at most `flinch_most_speed`.
func test_a_flinch_push_moves_a_light_limb_and_does_not_spin_it() -> void:
	var line := HitRange.line_to(_target, _zones.zone(&"forearm_l"))
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_reaction.is_flinching()).is_true()
	var spin := 0.0
	var speed := 0.0
	for tick in 3:
		for key in _reaction.flinch_bones():
			var rid := _ragdoll.body(key).get_rid()
			var turning: Vector3 = PhysicsServer3D.body_get_state(
				rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY
			)
			var moving: Vector3 = PhysicsServer3D.body_get_state(
				rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY
			)
			spin = maxf(spin, turning.length())
			speed = maxf(speed, moving.length())
		await get_tree().physics_frame
	assert_float(spin).is_less(35.0)
	assert_float(speed).is_less(_reaction.flinch_most_speed + 1.0)


# gdstudio #1326: the bodies a flinch leaves out follow the clip as kinematic bodies; on the
# ragdoll's layers they pressed a flinching arm against its own joint until it flew off.
func test_the_bodies_a_flinch_leaves_out_touch_nothing() -> void:
	var line := HitRange.line_to(_target, _zones.zone(&"forearm_l"))
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_reaction.is_flinching()).is_true()
	var flinching := _reaction.flinch_bones()
	for entry: Dictionary in CharacterRagdoll.BODIES:
		var rid := _ragdoll.body(entry.bone).get_rid()
		var layers := PhysicsServer3D.body_get_collision_layer(rid)
		var mask := PhysicsServer3D.body_get_collision_mask(rid)
		if flinching.has(entry.bone):
			assert_int(layers).override_failure_message(String(entry.bone)).is_not_equal(0)
		else:
			assert_int(layers | mask).override_failure_message(String(entry.bone)).is_equal(0)


# gdstudio #1326: the copies of the joints that hold a limp body's limbs (`RagdollBraces`) turned a
# flinching arm, hung from a body the clip moves, at the engine's limit; they go for the flinch
# and come back after it.
func test_a_flinch_lifts_the_extra_joints_and_gives_them_back() -> void:
	assert_int(_ragdoll.body_count()).is_greater(0)
	var braced := _ragdoll.hinge_count() + _ragdoll.cone_count()
	var line := HitRange.line_to(_target, _zones.zone(&"forearm_l"))
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_reaction.is_flinching()).is_true()
	assert_int(_ragdoll.hinge_count() + _ragdoll.cone_count()).is_less(braced)
	await InputSim.ticks(get_tree(), ceili(_reaction.flinch_time * 60.0) + 3)
	assert_bool(_reaction.is_flinching()).is_false()
	assert_int(_ragdoll.hinge_count() + _ragdoll.cone_count()).is_equal(braced)


func test_a_shot_on_a_lying_body_pushes_the_bone_and_leaves_a_mark_that_goes_with_it() -> void:
	var impacts := ImpactShots.impacts_of(_arena)
	_target.die()
	for tick in SETTLE_TICKS:
		if _ragdoll.is_settled():
			break
		await get_tree().physics_frame
	assert_bool(_ragdoll.is_settled()).is_true()
	var at := _ragdoll.body(&"spine_03").global_position
	var records: Array[HitRecord] = []
	_target.hit_received.connect(func(record: HitRecord) -> void: records.append(record))
	# From the side, nearly level: a shot from above pushes the body into the floor, which holds it.
	ImpactShots.fire(_arena, at + Vector3(3.0, 0.1, 0.0), at)
	var pushed := 0.0
	var bone: PhysicalBone3D = null
	for tick in 60:
		await get_tree().physics_frame
		if bone == null and not records.is_empty():
			bone = _ragdoll.body(records[0].bone)
		if bone != null:
			pushed = maxf(pushed, bone.linear_velocity.length())
	assert_int(records.size()).is_equal(1)
	assert_object(bone).is_not_null()
	assert_float(_target.health).is_equal(0.0)
	assert_float(pushed).is_greater(0.2)
	assert_int(impacts.mark_count()).is_equal(1)
	var mark := impacts.marks()[0]
	assert_object(mark.get_parent()).is_same(bone)
	var chest := bone
	# It rides the bone: the body is moved and the mark keeps its place on it.
	var held := chest.global_transform.affine_inverse() * mark.global_position
	chest.apply_central_impulse(Vector3(0.0, 30.0, 0.0))
	await InputSim.ticks(get_tree(), 10)
	var now := chest.global_transform.affine_inverse() * mark.global_position
	assert_vector(now).is_equal_approx(held, Vector3.ONE * 0.001)
	# Getting up takes it off.
	_target.revive()
	await get_tree().physics_frame
	assert_int(impacts.mark_count()).is_equal(0)


func test_the_hit_reaction_and_the_health_pin_their_exports() -> void:
	var pins := {
		&"character": null,
		&"ragdoll": null,
		&"death_push": 1.5,
		&"lying_push": 0.5,
		&"flinch_enabled": true,
		&"flinch_push": 0.6,
		&"flinch_most_speed": 3.0,
		&"flinch_strength": 0.85,
		&"flinch_time": 0.45,
		&"flinch_hold": 0.25,
	}
	var reaction := auto_free(HitReaction.new()) as HitReaction
	assert_array(ExportPins.differences(reaction, pins)).is_empty()
	assert_array(ExportPins.wrong_values(reaction, pins)).is_empty()
	# The dressed scene's numbers are the script's.
	assert_float(_reaction.death_push).is_equal(1.5)
	assert_float(_target.max_health).is_equal(100.0)
	assert_float(_target.health).is_equal(100.0)
