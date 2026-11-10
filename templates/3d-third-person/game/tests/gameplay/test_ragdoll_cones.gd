# Shoulders stay near a person's range when the body rolls over an arm (gdstudio #975): in the
# ragdoll lab's jog death on the male mannequin the left upper arm twisted to 174 degrees (a
# person: 60) with one cone joint. The death is staged on the physics clock (`RagdollStage`), so
# it is the same death every run.
extends GdUnitTestSuite

## A joint's limit is a soft stop against a load (test_ragdoll_natural.gd). Degrees.
const LIMIT_SLACK := 25.0
## The lab's jog: Jog_Fwd at 4.5 m/s, dead 1.2 s in, watched for 2.8 s.
const JOG_SPEED := 4.5
const DIE_TICK := 72
const WATCH_TICKS := 168
const SHOULDERS: Array[StringName] = [&"upperarm_l", &"upperarm_r"]
## A person's shoulder, swing and twist in degrees: the ragdoll holds the twist at 45 so that a
## shoulder pushed past its limit stays near these (docs/engines/godot/ragdoll.md#limits).
const PERSON_SWING := 100.0
const PERSON_TWIST := 60.0

var _stage: RagdollStage


func before_test() -> void:
	_stage = auto_free(RagdollStage.new())
	add_child(_stage)


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


# The worst swing or twist past a person's of either shoulder over the watch, after the first tenth
# of a second (the pose pushed inside the limits), and where.
func _watch() -> Array:
	var worst := 0.0
	var where := ""
	for tick in WATCH_TICKS:
		await _ticks(1)
		if tick < 6:
			continue
		for entry: Dictionary in CharacterRagdoll.BODIES:
			if not entry.bone in SHOULDERS:
				continue
			var angles := _stage.cone_angles(entry)
			var now := Vector2(
				maxf(angles.x - PERSON_SWING, 0.0), maxf(absf(angles.y) - PERSON_TWIST, 0.0)
			)
			var bone: StringName = entry.bone
			if maxf(now.x, now.y) > worst:
				worst = maxf(now.x, now.y)
				where = "%s swing past %.0f twist past %.0f at tick %d" % [bone, now.x, now.y, tick]
	return [worst, where]


func test_a_shoulder_stays_near_its_range_when_a_jogging_male_rolls_over_it() -> void:
	_stage.setup(&"male", &"ual1/Jog_Fwd", JOG_SPEED)
	await _ticks(DIE_TICK)
	_stage.kill()
	assert_bool(_stage.ragdoll.is_limp()).is_true()
	var worst := await _watch()
	(
		assert_float(worst[0])
		. override_failure_message("a shoulder went past a person's range: %s" % worst[1])
		. is_less(LIMIT_SLACK)
	)


# The control: the same death with each cone solved once (the engine's own joint alone) twists the
# shoulder past the slack, so the death above still loads the shoulder and the passes hold it.
func test_with_one_pass_the_same_death_twists_the_shoulder() -> void:
	_stage.setup(&"male", &"ual1/Jog_Fwd", JOG_SPEED)
	_stage.ragdoll.cone_passes = 1
	await _ticks(DIE_TICK)
	_stage.kill()
	var worst := await _watch()
	assert_float(worst[0]).is_greater(LIMIT_SLACK)
