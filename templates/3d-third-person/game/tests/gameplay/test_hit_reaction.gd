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
	_target.health = 1.0
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
	_target.health = 1.0
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
	_target.health = 1.0
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_bool(_ragdoll.is_limp()).is_true()
	assert_bool(_reaction.is_flinching()).is_false()
	await InputSim.ticks(get_tree(), 5)
	assert_bool(_ragdoll.body(&"thigh_l").is_simulating_physics()).is_true()


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
