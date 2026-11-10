# A character's first death takes a set of bones the `RagdollPool` made earlier instead of making
# them then (gdstudio #1022): the pooled set must fall exactly as one made at the death, on the
# same mannequin and on the other one (a set made on one is fitted to the other's rests), and
# carry nothing of the character that held it before. The deaths are staged on the physics clock
# (`RagdollStage`), so the same death gives the same fall.
extends GdUnitTestSuite

## The lab's jog: Jog_Fwd at 4.5 m/s, dead 1.2 s in, watched for half a second.
const JOG_SPEED := 4.5
const DIE_TICK := 72
const WATCH_TICKS := 30
## How far a pooled body may lie from the one made at the death, per bone, in metres.
const SAME_FALL := 0.001
const CHARACTER := "res://gameplay/character/character_dressed.tscn"


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func _pool() -> RagdollPool:
	return RagdollPool.instance(get_tree())


# Stages the jog death on `model` and returns where each body is, in the stage's space, half a
# second after it went limp. `fresh` makes the bones at the death; otherwise the stage takes a
# set from the pool (one must be parked).
func _fall(model: StringName, fresh: bool) -> Dictionary:
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
	await _ticks(WATCH_TICKS)
	var where := {}
	for entry: Dictionary in CharacterRagdoll.BODIES:
		where[entry.bone] = stage.to_local(stage.ragdoll.body(entry.bone).global_position)
	stage.ragdoll.stop(false)
	stage.queue_free()
	await _ticks(2)
	return where


func _farthest(a: Dictionary, b: Dictionary) -> Array:
	var worst := 0.0
	var where := ""
	for bone: StringName in a:
		var apart: float = (a[bone] as Vector3).distance_to(b[bone])
		if apart > worst:
			worst = apart
			where = "%s %.4f m apart" % [bone, apart]
	return [worst, where]


# Waits until the pool has made its sets (it makes one a frame after a ragdoll asks).
func _fill_pool() -> void:
	for _i in 30:
		if _pool().parked() >= _pool().wanted:
			return
		await _ticks(1)


func test_a_pooled_set_falls_as_one_made_at_the_death() -> void:
	var made := await _fall(&"male", true)
	await _fill_pool()
	var pooled := await _fall(&"male", false)
	var apart := _farthest(made, pooled)
	assert_float(apart[0]).override_failure_message(apart[1]).is_less(SAME_FALL)


func test_a_set_made_on_the_other_mannequin_falls_as_one_made_at_the_death() -> void:
	var made := await _fall(&"male", true)
	# Sets made on the female: drain the pool and let a female stage make them again.
	_pool().clear()
	var maker: RagdollStage = auto_free(RagdollStage.new())
	add_child(maker)
	maker.setup(&"female", &"ual1/Idle_Loop", 0.0)
	await _fill_pool()
	maker.queue_free()
	var pooled := await _fall(&"male", false)
	var apart := _farthest(made, pooled)
	assert_float(apart[0]).override_failure_message(apart[1]).is_less(SAME_FALL)


func test_the_pool_makes_sets_after_a_character_arrives() -> void:
	_pool().clear()
	var body := (load(CHARACTER) as PackedScene).instantiate() as Character
	add_child(body)
	await _fill_pool()
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
	await _fill_pool()
	body.die()
	await _ticks(10)
	var pelvis := body.ragdoll_body.body(&"pelvis")
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
