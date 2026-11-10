# Elbows and knees hold their range when the body rolls over its own limb (gdstudio #940): in the
# ragdoll lab's jog death on the male mannequin the left elbow folded to 178 degrees (range -5 to
# 150) with a 39 degree lean for about 0.4 s. The death is staged on the physics clock
# (`RagdollStage`), so it is the same death every run.
extends GdUnitTestSuite

## A joint's limit is a soft stop against a load (test_ragdoll_natural.gd). Degrees.
const LIMIT_SLACK := 25.0
## The lab's jog: Jog_Fwd at 4.5 m/s, dead 1.2 s in, watched for 2.8 s.
const JOG_SPEED := 4.5
const DIE_TICK := 72
const WATCH_TICKS := 168

var _stage: RagdollStage


func before_test() -> void:
	_stage = auto_free(RagdollStage.new())
	add_child(_stage)


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


# The worst bend past the range and the worst lean of any hinge over the watch, after the first
# tenth of a second (the pose pushed inside the limits), and where.
func _watch() -> Array:
	var bend := 0.0
	var lean := 0.0
	var where := ""
	for tick in WATCH_TICKS:
		await _ticks(1)
		if tick < 6:
			continue
		var found := _stage.hinge_overrun()
		for bone: StringName in found:
			var now: Vector2 = found[bone]
			if now.x > bend or now.y > lean:
				where = "%s past %.0f lean %.0f at tick %d" % [bone, now.x, now.y, tick]
			bend = maxf(bend, now.x)
			lean = maxf(lean, now.y)
	return [bend, lean, where]


func test_an_elbow_holds_its_range_when_a_jogging_male_rolls_over_it() -> void:
	_stage.setup(&"male", &"ual1/Jog_Fwd", JOG_SPEED)
	await _ticks(DIE_TICK)
	_stage.kill()
	assert_bool(_stage.ragdoll.is_limp()).is_true()
	var worst := await _watch()
	(
		assert_float(worst[0])
		. override_failure_message("a hinge folded past its range: %s" % worst[2])
		. is_less(LIMIT_SLACK)
	)
	(
		assert_float(worst[1])
		. override_failure_message("a hinge leaned off its axis: %s" % worst[2])
		. is_less(LIMIT_SLACK)
	)


# The control: the same death with each hinge solved once (the engine's own joint alone) folds
# the elbow past the slack, so the death above still loads the elbow and the passes hold it.
func test_with_one_pass_the_same_death_folds_the_elbow() -> void:
	_stage.setup(&"male", &"ual1/Jog_Fwd", JOG_SPEED)
	_stage.ragdoll.hinge_passes = 1
	await _ticks(DIE_TICK)
	_stage.kill()
	var worst := await _watch()
	assert_float(maxf(worst[0], worst[1])).is_greater(LIMIT_SLACK)
