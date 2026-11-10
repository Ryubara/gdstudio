# A character's first death takes a set of bones the `RagdollPool` made earlier instead of making
# them then (gdstudio #1022): the pooled set must fall as one made at the death, on the same
# mannequin and on the other one (a set made on one is fitted to the other's rests), keep its
# joints in the order that holds a shoulder, and carry nothing of the character that held it
# before. The deaths are staged on the physics clock (`RagdollStage`).
extends GdUnitTestSuite

## The lab's jog: Jog_Fwd at 4.5 m/s, dead 1.2 s in, watched for half a second.
const JOG_SPEED := 4.5
const DIE_TICK := 72
const WATCH_TICKS := 30
## How far a pooled body may lie from one made at the death half a second after, per bone, in
## metres. Two deaths made the same way lie up to 1 cm apart (the physics bodies are new each time,
## and Jolt orders its work by them); a joint made in the wrong pose put a hand 0.46 m away.
const FALL_SPREAD := 0.03
## The cone suite's watch and slack (test_ragdoll_cones.gd): a shoulder within 25 degrees of a
## person's range over 2.8 s.
const SHOULDER_TICKS := 168
const LIMIT_SLACK := 25.0
const PERSON_SWING := 100.0
const PERSON_TWIST := 60.0
const CHARACTER := "res://gameplay/character/character_dressed.tscn"


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func _pool() -> RagdollPool:
	return RagdollPool.instance(get_tree())


# Stages the jog death on `model` and returns where each body is, in the stage's space, half a
# second after it went limp. `fresh` makes the bones at the death; otherwise the stage takes a
# set from the pool (one must be parked).
func _fall(model: StringName, fresh: bool) -> Dictionary:
	var stage := await _die(model, fresh)
	await _ticks(WATCH_TICKS)
	var where := {}
	for entry: Dictionary in CharacterRagdoll.BODIES:
		where[entry.bone] = stage.to_local(stage.ragdoll.body(entry.bone).global_position)
	await _end(stage)
	return where


func _die(model: StringName, fresh: bool) -> RagdollStage:
	# Staged on a tick, whatever the caller waited for last: a stage set up between two frames
	# rather than at a tick starts its walk a tick off, and lies 0.3 m from the others.
	await _ticks(1)
	var stage: RagdollStage = auto_free(RagdollStage.new())
	add_child(stage)
	stage.setup(model, &"ual1/Jog_Fwd", JOG_SPEED)
	await _ticks(DIE_TICK)
	if fresh:
		stage.ragdoll._build()
	else:
		assert_bool(stage.ragdoll.has_bones()).is_false()
		assert_int(_pool().parked()).is_greater(0)
	stage.kill()
	assert_bool(stage.ragdoll.is_limp()).is_true()
	return stage


func _end(stage: RagdollStage) -> void:
	stage.ragdoll.stop(false)
	stage.queue_free()
	await _ticks(2)


func _farthest(a: Dictionary, b: Dictionary) -> Array:
	var worst := 0.0
	var where := ""
	for bone: StringName in a:
		var apart: float = (a[bone] as Vector3).distance_to(b[bone])
		if apart > worst:
			worst = apart
			where = "%s %.4f m apart" % [bone, apart]
	return [worst, where]


# Fills the pool with sets made on a stage of `model` (it makes one a frame).
func _fill_pool(model: StringName) -> void:
	_pool().clear()
	var maker: RagdollStage = auto_free(RagdollStage.new())
	add_child(maker)
	maker.setup(model, &"ual1/Idle", 0.0)
	for _i in 30:
		if _pool().parked() >= _pool().wanted:
			break
		await _ticks(1)
	maker.queue_free()
	await _ticks(1)


func test_a_pooled_set_falls_as_one_made_at_the_death() -> void:
	var made := await _fall(&"male", true)
	await _fill_pool(&"male")
	var pooled := await _fall(&"male", false)
	var apart := _farthest(made, pooled)
	assert_float(apart[0]).override_failure_message(apart[1]).is_less(FALL_SPREAD)


func test_a_set_made_on_the_other_mannequin_falls_as_one_made_at_the_death() -> void:
	var made := await _fall(&"male", true)
	await _fill_pool(&"female")
	var pooled := await _fall(&"male", false)
	var apart := _farthest(made, pooled)
	assert_float(apart[0]).override_failure_message(apart[1]).is_less(FALL_SPREAD)


# The cone suite's shoulder death, as that suite stages it, on a set the stage itself made for the
# pool while it jogged: with its extra joints kept over the move (they came back body by body),
# the left shoulder twisted 44 degrees past a person's.
func test_a_pooled_set_holds_a_shoulder_the_body_rolls_over() -> void:
	_pool().clear()
	var stage: RagdollStage = auto_free(RagdollStage.new())
	add_child(stage)
	stage.setup(&"male", &"ual1/Jog_Fwd", JOG_SPEED)
	await _ticks(DIE_TICK)
	assert_int(_pool().parked()).is_equal(_pool().wanted)
	stage.kill()
	var worst := 0.0
	for tick in SHOULDER_TICKS:
		await _ticks(1)
		if tick < 6:
			continue
		for entry: Dictionary in CharacterRagdoll.BODIES:
			if entry.bone in [&"upperarm_l", &"upperarm_r"]:
				var angles := stage.cone_angles(entry)
				worst = maxf(worst, maxf(angles.x - PERSON_SWING, absf(angles.y) - PERSON_TWIST))
	await _end(stage)
	assert_float(worst).is_less(LIMIT_SLACK)


func test_the_pool_makes_sets_after_a_character_arrives() -> void:
	_pool().clear()
	var body := (load(CHARACTER) as PackedScene).instantiate() as Character
	add_child(body)
	for _i in 30:
		await _ticks(1)
	assert_int(_pool().parked()).is_equal(body.ragdoll_body.max_active)
	# The maker carries none of them.
	assert_bool(body.ragdoll_body.has_bones()).is_false()
	body.die()
	assert_bool(body.ragdoll_body.is_limp()).is_true()
	assert_int(_pool().parked()).is_equal(body.ragdoll_body.max_active - 1)
	body.free()


func test_a_character_freed_with_bones_gives_them_back_clean() -> void:
	_pool().clear()
	var body := (load(CHARACTER) as PackedScene).instantiate() as Character
	add_child(body)
	for _i in 30:
		await _ticks(1)
	body.die()
	await _ticks(10)
	var pelvis := body.ragdoll_body.body(&"pelvis")
	assert_bool(pelvis.has_meta(&"hit_zones")).is_true()
	var held := _pool().parked()
	body.queue_free()
	await _ticks(2)
	assert_int(_pool().parked()).is_equal(held + 1)
	# Parked: out of the physics world, no joint, no tag of the old character.
	assert_bool(pelvis.is_inside_tree()).is_true()
	assert_bool(pelvis.can_process()).is_false()
	assert_bool(pelvis.has_meta(&"hit_zones")).is_false()
	var arm := pelvis.get_parent().get_node(^"lowerarm_l") as PhysicalBone3D
	assert_int(arm.joint_type).is_equal(PhysicalBone3D.JOINT_TYPE_NONE)
