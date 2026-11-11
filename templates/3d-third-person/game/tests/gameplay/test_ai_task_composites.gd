# Composite tasks are tasks: a sequence, a parallel, a repeat and a selector run their children
# under each child's own contract (time limits, `on_fail`, the watchdog, `when_interrupted`), so
# a patrol route is data; a task kept as a template is copied, never run itself.
extends GdUnitTestSuite

const STEP := 0.1

var _controller: AiController


func before_test() -> void:
	_controller = auto_free(AiController.new())


func _runner() -> AiTaskRunner:
	var runner := AiTaskRunner.new()
	runner.profile = AiProfile.new()
	runner.profile.failure_budget = 50
	runner.controller = _controller
	return runner


func _run(runner: AiTaskRunner, seconds: float) -> void:
	for _i in roundi(seconds / STEP):
		runner.tick(STEP)


func _leg(task_id: StringName, seconds: float) -> ScriptedTask:
	return ScriptedTask.make(task_id, AiTask.Layer.ROUTINE, seconds)


func _sequence(task_id: StringName, steps: Array[AiTask]) -> AiTaskSequence:
	var sequence := AiTaskSequence.new()
	sequence.id = task_id
	sequence.children = steps
	return sequence


func test_a_sequence_runs_its_children_in_order() -> void:
	var runner := _runner()
	var first := _leg(&"walk", 0.5)
	var second := _leg(&"wait", 0.5)
	var route := _sequence(&"route", [first, second])
	runner.assign(route)
	_run(runner, 0.3)
	assert_int(first.state).is_equal(AiTask.State.RUNNING)
	assert_int(second.state).is_equal(AiTask.State.PENDING)
	_run(runner, 0.4)
	assert_int(first.state).is_equal(AiTask.State.SUCCEEDED)
	assert_int(second.state).is_equal(AiTask.State.RUNNING)
	_run(runner, 0.5)
	assert_int(route.state).is_equal(AiTask.State.SUCCEEDED)


func test_an_interrupted_sequence_follows_its_child_when_interrupted() -> void:
	var runner := _runner()
	var skipped := _leg(&"look_around", 2.0)
	skipped.when_interrupted = AiTask.WhenInterrupted.SKIP_TO_NEXT
	var restarted := _leg(&"walk", 1.0)
	restarted.when_interrupted = AiTask.WhenInterrupted.RESTART
	var route := _sequence(&"route", [skipped, restarted])
	runner.assign(route)
	_run(runner, 0.5)
	runner.assign(ScriptedTask.make(&"noise", AiTask.Layer.RESPONSE, 0.3))
	_run(runner, 0.6)
	assert_int(skipped.state).is_equal(AiTask.State.CANCELLED)
	assert_int(route.step).is_equal(1)
	assert_int(restarted.state).is_equal(AiTask.State.RUNNING)
	_run(runner, 0.4)
	runner.assign(ScriptedTask.make(&"noise_again", AiTask.Layer.RESPONSE, 0.3))
	_run(runner, 0.6)
	assert_int(restarted.starts).is_equal(2)
	assert_float(restarted.progress).is_less(0.5)


func test_an_aborting_child_ends_its_sequence() -> void:
	var runner := _runner()
	var aborting := _leg(&"scripted_line", 2.0)
	aborting.when_interrupted = AiTask.WhenInterrupted.ABORT
	var route := _sequence(&"route", [aborting, _leg(&"after_line", 1.0)])
	runner.assign(route)
	_run(runner, 0.3)
	runner.assign(ScriptedTask.make(&"noise", AiTask.Layer.RESPONSE, 0.3))
	_run(runner, 0.6)
	assert_int(route.state).is_equal(AiTask.State.FAILED)
	assert_int(route.reason).is_equal(AiTask.Reason.CANCELLED)


func test_a_parallel_drives_its_channels_together() -> void:
	var runner := _runner()
	var walk := _leg(&"walk", 0.5)
	walk.walk = Vector3.RIGHT
	var shoot := _leg(&"shoot", 1.0)
	shoot.channels = AiTask.Channel.ACTION
	shoot.shoots = true
	var both := AiTaskParallel.new()
	both.id = &"advance"
	both.children = [walk, shoot]
	assert_int(both.claimed_channels()).is_equal(AiTask.Channel.MOVE | AiTask.Channel.ACTION)
	runner.assign(both)
	_run(runner, 0.3)
	assert_vector(_controller.walk_direction).is_equal(Vector3.RIGHT)
	assert_bool(_controller.fire).is_true()
	_run(runner, 0.4)
	assert_int(walk.state).is_equal(AiTask.State.SUCCEEDED)
	assert_int(both.state).is_equal(AiTask.State.RUNNING)
	_run(runner, 0.5)
	assert_int(both.state).is_equal(AiTask.State.SUCCEEDED)
	assert_bool(_controller.fire).is_false()


func test_a_parallel_can_finish_on_its_first_child_and_warns_on_a_shared_channel() -> void:
	var runner := _runner()
	var short := _leg(&"short", 0.3)
	var long := _leg(&"long", 5.0)
	long.channels = AiTask.Channel.LOOK
	var race := AiTaskParallel.new()
	race.finish_on_first = true
	race.children = [short, long]
	runner.assign(race)
	_run(runner, 0.5)
	assert_int(race.state).is_equal(AiTask.State.SUCCEEDED)
	assert_int(long.state).is_equal(AiTask.State.CANCELLED)
	long.channels = AiTask.Channel.MOVE
	assert_array(Array(race.authoring_problems())).has_size(1)


func test_a_repeat_runs_its_count_and_a_forever_route_resumes_on_its_leg() -> void:
	var runner := _runner()
	var leg := _leg(&"leg", 0.3)
	var thrice := AiTaskRepeat.new()
	thrice.count = 3
	thrice.children = [leg]
	runner.assign(thrice)
	_run(runner, 1.2)
	assert_int(leg.starts).is_equal(3)
	assert_int(thrice.state).is_equal(AiTask.State.SUCCEEDED)
	var first := _leg(&"first", 1.0)
	var second := _leg(&"second", 1.0)
	var patrol := AiTaskRepeat.new()
	patrol.id = &"patrol"
	patrol.children = [_sequence(&"route", [first, second])]
	runner.assign(patrol)
	_run(runner, 1.5)
	runner.assign(ScriptedTask.make(&"noise", AiTask.Layer.RESPONSE, 0.5))
	_run(runner, 0.8)
	assert_int(second.state).is_equal(AiTask.State.RUNNING)
	assert_int(second.starts).is_equal(1)
	assert_int(first.starts).is_equal(1)
	_run(runner, 1.0)
	assert_int(patrol.rounds).is_equal(1)
	assert_int(first.starts).is_equal(2)


func test_a_selector_tries_children_until_one_succeeds() -> void:
	var runner := _runner()
	var blocked := _leg(&"cover_left", 0.2)
	blocked.fail_with = AiTask.Reason.NO_PATH
	var open := _leg(&"cover_right", 0.2)
	var choose := AiTaskSelector.new()
	choose.children = [blocked, open]
	runner.assign(choose)
	_run(runner, 0.6)
	assert_int(choose.state).is_equal(AiTask.State.SUCCEEDED)
	assert_int(open.state).is_equal(AiTask.State.SUCCEEDED)
	var none := _leg(&"cover_far", 0.2)
	none.fail_with = AiTask.Reason.BLOCKED
	var only_bad := AiTaskSelector.new()
	only_bad.children = [none]
	runner.assign(only_bad)
	_run(runner, 0.4)
	assert_int(only_bad.state).is_equal(AiTask.State.FAILED)
	assert_int(only_bad.reason).is_equal(AiTask.Reason.BLOCKED)


func test_a_child_time_limit_and_skip_keep_the_sequence_going() -> void:
	var runner := _runner()
	var stuck := _leg(&"stuck", 0.0)
	stuck.hard_timeout = 0.5
	var last := _leg(&"last", 0.2)
	var route := _sequence(&"route", [stuck, last])
	runner.assign(route)
	_run(runner, 1.0)
	assert_int(stuck.state).is_equal(AiTask.State.TIMED_OUT)
	assert_int(route.state).is_equal(AiTask.State.SUCCEEDED)


func test_a_child_script_error_fails_the_whole_sequence_invalid() -> void:
	var runner := _runner()
	var broken := _leg(&"broken", 1.0)
	broken.breaks = true
	var route := _sequence(&"route", [broken, _leg(&"after_broken", 0.2)])
	runner.assign(route)
	await (
		assert_error(func() -> void: _run(runner, 0.3))
		. is_runtime_error("Cannot call method 'call' on a null value.")
	)
	assert_int(route.state).is_equal(AiTask.State.FAILED)
	assert_int(route.reason).is_equal(AiTask.Reason.INVALID)
	assert_bool(runner.in_fallback()).is_true()


func test_a_template_task_is_copied_and_keeps_its_target() -> void:
	var target: Node3D = auto_free(Node3D.new())
	var template := _sequence(&"route", [_leg(&"walk", 1.0)])
	template.target = target
	var one := _runner()
	var other := _runner()
	var first := one.assign(template)
	var second := other.assign(template)
	assert_object(first).is_same(template)
	assert_object(second).is_not_same(template)
	assert_object(second.target).is_same(target)
	var copied := second as AiTaskSequence
	assert_object(copied.children[0]).is_not_same(template.children[0])
	_run(other, 0.3)
	assert_int((template.children[0] as AiTask).state).is_equal(AiTask.State.PENDING)
