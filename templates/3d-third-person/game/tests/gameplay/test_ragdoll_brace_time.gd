# A limp body lets go of its extra joints once it has landed (gdstudio #1372): the copies of each
# joint (`RagdollBraces`, `hinge_passes` and `cone_passes`) hold the limbs through the fall, and a
# body that kept them while it lay wedged against two blocks in the AI soak turned an arm at the
# engine's limit of 47 rad/s and went to NaN 2.3 s after the death. With `brace_time` the body
# lies on its own joints after the landing, and the next death has every copy again. The death
# is staged on the physics clock (`RagdollStage`), so it is the same every run.
extends GdUnitTestSuite

const JOG_SPEED := 4.5
const DIE_TICK := 72
## Elbows and knees, and the other joints, each held by 6 joints while braced.
const OWN_HINGES := 4
const OWN_CONES := 11
const PASSES := 6
## The ragdoll's `brace_time` (pinned in test_ragdoll.gd), seconds.
const BRACE_TIME := 1.5

var _stage: RagdollStage


func before_test() -> void:
	_stage = auto_free(RagdollStage.new())
	add_child(_stage)


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func _joints() -> Vector2i:
	return Vector2i(_stage.ragdoll.hinge_count(), _stage.ragdoll.cone_count())


# The ticks of `seconds` on the physics clock, and two more.
func _ticks_of(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 2


func test_a_landed_body_lets_go_of_the_extra_joints_and_the_next_death_has_them() -> void:
	_stage.setup(&"male", &"ual1/Jog_Fwd", JOG_SPEED)
	await _ticks(DIE_TICK)
	_stage.kill()
	var braced := Vector2i(OWN_HINGES * PASSES, OWN_CONES * PASSES)
	assert_that(_joints()).is_equal(braced)
	# Through the landing they hold.
	await _ticks(_ticks_of(BRACE_TIME) - 10)
	assert_that(_joints()).is_equal(braced)
	await _ticks(10)
	assert_that(_joints()).is_equal(Vector2i(OWN_HINGES, OWN_CONES))
	# The body gets up and dies again: every copy is back for the fall.
	_stage.ragdoll.stop(false)
	await _ticks(2)
	assert_bool(_stage.ragdoll.start()).is_true()
	assert_that(_joints()).is_equal(braced)


func test_a_body_that_lies_on_its_own_joints_comes_to_rest() -> void:
	_stage.setup(&"male", &"ual1/Jog_Fwd", JOG_SPEED)
	_stage.ragdoll.settle_time = 3.0
	await _ticks(DIE_TICK)
	_stage.kill()
	var ticks := 0
	while not _stage.ragdoll.is_settled() and ticks < _ticks_of(10.0):
		await _ticks(1)
		ticks += 1
	assert_bool(_stage.ragdoll.is_settled()).is_true()
	assert_that(_joints()).is_equal(Vector2i(OWN_HINGES, OWN_CONES))


func test_brace_time_is_read_live() -> void:
	_stage.setup(&"male", &"ual1/Jog_Fwd", JOG_SPEED)
	_stage.ragdoll.brace_time = 1000.0
	await _ticks(DIE_TICK)
	_stage.kill()
	await _ticks(_ticks_of(2.0))
	assert_that(_joints()).is_equal(Vector2i(OWN_HINGES * PASSES, OWN_CONES * PASSES))
	_stage.ragdoll.brace_time = 0.5
	await _ticks(2)
	assert_that(_joints()).is_equal(Vector2i(OWN_HINGES, OWN_CONES))
