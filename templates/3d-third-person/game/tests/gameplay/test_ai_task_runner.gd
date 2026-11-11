# The task runner against rows 1 to 6 of the edge-case table of the research for kit #882 (section
# 3.3; the kit's docs/engines/godot/third-person/ai.md#edge-cases; rows 7 to 13 are
# test_ai_task_rules.gd): each test is written so that a runner without the row's rule fails it.
# A runner here has no scene: a bare `AiController` for its channels and a profile, stepped at
# the 10 Hz of a think.
extends GdUnitTestSuite

const STEP := 0.1

var _controller: AiController


func before_test() -> void:
	_controller = auto_free(AiController.new())


func _runner() -> AiTaskRunner:
	var runner := AiTaskRunner.new()
	runner.profile = AiProfile.new()
	runner.controller = _controller
	return runner


func _run(runner: AiTaskRunner, seconds: float) -> void:
	for _i in roundi(seconds / STEP):
		runner.tick(STEP)


func _attacker() -> Node3D:
	return auto_free(Node3D.new())


# 1. A patrol interrupted by a noise is suspended, the response runs, and the patrol continues
# from its own point (not restarted).
func test_an_interrupted_task_resumes_where_it_was() -> void:
	var runner := _runner()
	var patrol := ScriptedTask.make(&"patrol", AiTask.Layer.ROUTINE, 10.0)
	runner.assign(patrol)
	_run(runner, 3.0)
	var investigate := ScriptedTask.make(&"investigate", AiTask.Layer.RESPONSE, 1.0)
	runner.assign(investigate)
	_run(runner, 0.1)
	assert_object(runner.active).is_same(investigate)
	assert_int(patrol.state).is_equal(AiTask.State.SUSPENDED)
	assert_int(patrol.suspends).is_equal(1)
	_run(runner, 1.2)
	assert_int(investigate.state).is_equal(AiTask.State.SUCCEEDED)
	assert_object(runner.active).is_same(patrol)
	assert_int(patrol.starts).is_equal(1)
	assert_int(patrol.resumes).is_equal(1)
	assert_float(patrol.progress).is_between(3.0, 3.4)


# 2. Same layer: REPLACE cancels the old one, QUEUE waits, IGNORE drops itself, MERGE updates the
# running one; 50 identical events make one task.
func test_a_same_layer_task_replaces_queues_ignores_or_merges() -> void:
	var runner := _runner()
	runner.profile.commit_seconds = 0.0
	var first := ScriptedTask.make(&"flee", AiTask.Layer.RESPONSE, 5.0)
	runner.assign(first)
	_run(runner, 0.2)
	var queued := ScriptedTask.make(&"cover", AiTask.Layer.RESPONSE, 1.0)
	queued.replace_policy = AiTask.ReplacePolicy.QUEUE
	runner.assign(queued)
	var ignored := ScriptedTask.make(&"wave", AiTask.Layer.RESPONSE, 1.0)
	ignored.replace_policy = AiTask.ReplacePolicy.IGNORE
	assert_object(runner.assign(ignored)).is_null()
	var merged := ScriptedTask.make(&"flee", AiTask.Layer.RESPONSE, 5.0)
	merged.goal = Vector3(4.0, 0.0, 2.0)
	assert_object(runner.assign(merged)).is_same(first)
	assert_vector(first.goal).is_equal(Vector3(4.0, 0.0, 2.0))
	assert_int(first.merges).is_equal(1)
	assert_array(runner.queued(AiTask.Layer.RESPONSE)).is_equal([first, queued])
	var replacing := ScriptedTask.make(&"charge", AiTask.Layer.RESPONSE, 1.0)
	replacing.replace_policy = AiTask.ReplacePolicy.REPLACE
	runner.assign(replacing)
	assert_int(first.state).is_equal(AiTask.State.CANCELLED)
	assert_int(first.reason).is_equal(AiTask.Reason.REPLACED)
	_run(runner, 0.1)
	assert_object(runner.active).is_same(replacing)
	_run(runner, 1.0)
	assert_object(runner.active).is_same(queued)


func test_fifty_identical_events_make_one_task() -> void:
	var runner := _runner()
	var started := []
	runner.task_started.connect(func(task: AiTask) -> void: started.append(task))
	for index in 50:
		runner.assign(ScriptedTask.make(&"noticed", AiTask.Layer.RESPONSE, 2.0))
		if index % 5 == 0:
			_run(runner, 0.1)
	assert_int(runner.count()).is_equal(1)
	assert_int(started.size()).is_equal(1)


# 3. A task that must complete: an event during it waits and is delivered after; `clear` skips
# it; a never-ending one ends at its hard timeout as TIMED_OUT.
func test_a_must_complete_task_defers_events_and_ends_at_its_hard_timeout() -> void:
	var runner := _runner()
	var door := ScriptedTask.make(&"open_door", AiTask.Layer.ORDER, 2.0)
	door.authority = AiTask.AUTHORITY_SCRIPT
	door.interruptible = AiTask.Interruptible.NO
	runner.assign(door)
	_run(runner, 0.5)
	assert_int(runner.clear()).is_equal(0)
	var noise := ScriptedTask.make(&"investigate", AiTask.Layer.RESPONSE, 1.0)
	runner.assign(noise)
	assert_array(runner.deferred()).has_size(1)
	_run(runner, 1.0)
	assert_object(runner.active).is_same(door)
	assert_int(noise.state).is_equal(AiTask.State.PENDING)
	_run(runner, 0.7)
	assert_int(door.state).is_equal(AiTask.State.SUCCEEDED)
	_run(runner, 0.1)
	assert_object(runner.active).is_same(noise)
	var stuck := ScriptedTask.make(&"scripted_beat", AiTask.Layer.ORDER, 0.0)
	stuck.authority = AiTask.AUTHORITY_SCRIPT
	stuck.interruptible = AiTask.Interruptible.NO
	stuck.hard_timeout = 1.5
	var failures := []
	runner.task_failed.connect(func(task: AiTask, why: int) -> void: failures.append([task, why]))
	runner.assign(stuck)
	_run(runner, 3.0)
	assert_int(stuck.state).is_equal(AiTask.State.TIMED_OUT)
	assert_array(failures).contains([[stuck, AiTask.Reason.TIMED_OUT]])


func test_force_cancel_ends_a_must_complete_task() -> void:
	var runner := _runner()
	var beat := ScriptedTask.make(&"beat", AiTask.Layer.ROUTINE, 0.0)
	beat.interruptible = AiTask.Interruptible.NO
	runner.assign(beat)
	_run(runner, 0.3)
	assert_int(runner.clear(-1)).is_equal(0)
	runner.force_cancel(beat)
	assert_int(beat.state).is_equal(AiTask.State.CANCELLED)
	assert_int(beat.cancels).is_equal(1)
	assert_object(runner.active).is_null()


# 4. Attacked during an uninterruptible task, one test per `under_attack` policy.
func _must_complete(policy: AiTask.UnderAttack) -> ScriptedTask:
	var task := ScriptedTask.make(&"revive", AiTask.Layer.ROUTINE, 2.0)
	task.interruptible = AiTask.Interruptible.NO
	task.under_attack = policy
	task.walk = Vector3.FORWARD
	return task


func _attack_task() -> ScriptedTask:
	var attack := ScriptedTask.make(&"attack", AiTask.Layer.RESPONSE, 1.0)
	attack.channels = AiTask.Channel.ACTION
	attack.shoots = true
	return attack


func test_attacked_under_ignore_changes_nothing() -> void:
	var runner := _runner()
	runner.attack_task = _attack_task()
	var pending := []
	runner.attacker_pending.connect(func(source: Object) -> void: pending.append(source))
	var task := _must_complete(AiTask.UnderAttack.IGNORE)
	runner.assign(task)
	_run(runner, 0.5)
	runner.report_damage(30.0, _attacker())
	_run(runner, 2.0)
	assert_int(task.state).is_equal(AiTask.State.SUCCEEDED)
	assert_array(pending).is_empty()
	assert_object(runner.active).is_null()


func test_attacked_under_finish_then_react_answers_once_the_task_ends() -> void:
	var runner := _runner()
	runner.attack_task = _attack_task()
	var attacker := _attacker()
	var pending := []
	runner.attacker_pending.connect(func(source: Object) -> void: pending.append(source))
	var task := _must_complete(AiTask.UnderAttack.FINISH_THEN_REACT)
	runner.assign(task)
	_run(runner, 0.5)
	runner.report_damage(30.0, attacker)
	_run(runner, 0.5)
	assert_object(runner.active).is_same(task)
	assert_array(pending).is_empty()
	_run(runner, 1.2)
	assert_array(pending).is_equal([attacker])
	_run(runner, 0.1)
	assert_str(String(runner.active_kind())).is_equal("attack")
	assert_object(runner.active.target).is_same(attacker)


func test_attacked_under_fight_back_fires_on_the_action_channel_while_it_finishes() -> void:
	var runner := _runner()
	runner.attack_task = _attack_task()
	var task := _must_complete(AiTask.UnderAttack.FIGHT_BACK_WHILE)
	runner.assign(task)
	_run(runner, 0.5)
	runner.report_damage(10.0, _attacker())
	_run(runner, 0.3)
	assert_object(runner.side_task).is_not_null()
	assert_bool(_controller.fire).is_true()
	assert_vector(_controller.walk_direction).is_equal(Vector3.FORWARD)
	assert_object(runner.active).is_same(task)
	_run(runner, 1.5)
	assert_int(task.state).is_equal(AiTask.State.SUCCEEDED)
	assert_object(runner.side_task).is_null()
	assert_bool(_controller.fire).is_false()


func test_attacked_under_abort_above_aborts_past_the_threshold() -> void:
	var runner := _runner()
	runner.attack_task = _attack_task()
	var task := _must_complete(AiTask.UnderAttack.ABORT_ABOVE)
	task.abort_damage = 20.0
	task.abort_window = 1.0
	runner.assign(task)
	_run(runner, 0.3)
	runner.report_damage(12.0, _attacker())
	_run(runner, 1.2)
	runner.report_damage(12.0, _attacker())
	assert_object(runner.active).is_same(task)
	_run(runner, 0.2)
	runner.report_damage(12.0, _attacker())
	assert_int(task.state).is_equal(AiTask.State.FAILED)
	assert_int(task.reason).is_equal(AiTask.Reason.ATTACKED)
	_run(runner, 0.1)
	assert_str(String(runner.active_kind())).is_equal("attack")


# 5. Resume after a changed world: the suspended task decides (carry on, restart, reached,
# unreachable), and a long interruption checks `still_valid`.
func test_resume_after_a_changed_world_follows_the_task_answer() -> void:
	var runner := _runner()
	var walk := ScriptedTask.make(&"go_to", AiTask.Layer.ROUTINE, 5.0)
	walk.resume_answer = AiTask.Resume.FAILED
	walk.resume_reason = AiTask.Reason.NO_PATH
	var next := ScriptedTask.make(&"wander", AiTask.Layer.ROUTINE, 5.0)
	next.replace_policy = AiTask.ReplacePolicy.QUEUE
	runner.assign(walk)
	runner.assign(next)
	_run(runner, 1.0)
	runner.assign(ScriptedTask.make(&"look", AiTask.Layer.RESPONSE, 0.5))
	_run(runner, 1.0)
	assert_int(walk.state).is_equal(AiTask.State.FAILED)
	assert_int(walk.reason).is_equal(AiTask.Reason.NO_PATH)
	assert_object(runner.active).is_same(next)


func test_resume_can_restart_or_finish_the_task() -> void:
	var runner := _runner()
	var restarted := ScriptedTask.make(&"route", AiTask.Layer.ROUTINE, 5.0)
	restarted.resume_answer = AiTask.Resume.RESTART
	runner.assign(restarted)
	_run(runner, 1.0)
	runner.assign(ScriptedTask.make(&"look", AiTask.Layer.RESPONSE, 0.3))
	_run(runner, 0.6)
	assert_int(restarted.starts).is_equal(2)
	assert_float(restarted.progress).is_less(0.5)
	restarted.resume_answer = AiTask.Resume.SUCCEEDED
	runner.assign(ScriptedTask.make(&"look_again", AiTask.Layer.RESPONSE, 0.3))
	_run(runner, 0.6)
	assert_int(restarted.state).is_equal(AiTask.State.SUCCEEDED)


func test_a_long_interruption_asks_still_valid() -> void:
	var runner := _runner()
	var guard := ScriptedTask.make(&"guard", AiTask.Layer.ROUTINE, 9.0)
	guard.resume_valid_for = 1.0
	guard.valid = false
	runner.assign(guard)
	_run(runner, 0.5)
	runner.assign(ScriptedTask.make(&"short", AiTask.Layer.RESPONSE, 0.5))
	_run(runner, 0.8)
	assert_int(guard.state).is_equal(AiTask.State.RUNNING)
	runner.assign(ScriptedTask.make(&"long", AiTask.Layer.RESPONSE, 2.0))
	_run(runner, 2.5)
	assert_int(guard.state).is_equal(AiTask.State.FAILED)
	assert_int(guard.reason).is_equal(AiTask.Reason.STALE)


# 6. A failure under each `on_fail`, and the failure budget against a storm.
func test_a_failure_follows_on_fail() -> void:
	var runner := _runner()
	runner.profile.failure_budget = 50
	var skipped := ScriptedTask.make(&"skip", AiTask.Layer.ROUTINE, 0.2)
	skipped.fail_with = AiTask.Reason.TARGET_LOST
	var next_up := ScriptedTask.make(&"after", AiTask.Layer.ROUTINE, 0.5)
	next_up.replace_policy = AiTask.ReplacePolicy.QUEUE
	runner.assign(skipped)
	runner.assign(next_up)
	_run(runner, 0.4)
	assert_int(skipped.state).is_equal(AiTask.State.FAILED)
	assert_object(runner.active).is_same(next_up)
	_run(runner, 1.0)
	var retried := ScriptedTask.make(&"retry", AiTask.Layer.ROUTINE, 0.2)
	retried.fail_with = AiTask.Reason.BLOCKED
	retried.on_fail = AiTask.OnFail.RETRY
	retried.retry_count = 2
	retried.retry_delay = 0.0
	runner.assign(retried)
	_run(runner, 2.0)
	assert_int(retried.starts).is_equal(3)
	assert_int(retried.state).is_equal(AiTask.State.FAILED)
	var with_fallback := ScriptedTask.make(&"shoot", AiTask.Layer.ROUTINE, 0.2)
	with_fallback.fail_with = AiTask.Reason.NO_AMMO
	with_fallback.on_fail = AiTask.OnFail.FALLBACK
	with_fallback.fallback = ScriptedTask.make(&"melee", AiTask.Layer.ROUTINE, 0.5)
	runner.assign(with_fallback)
	_run(runner, 0.4)
	assert_int(with_fallback.state).is_equal(AiTask.State.RUNNING)
	_run(runner, 0.6)
	assert_int(with_fallback.state).is_equal(AiTask.State.SUCCEEDED)


func test_propagate_fails_the_sequence_and_skip_goes_on() -> void:
	var runner := _runner()
	runner.profile.failure_budget = 50
	var failing := ScriptedTask.make(&"step", AiTask.Layer.ROUTINE, 0.2)
	failing.fail_with = AiTask.Reason.BLOCKED
	failing.on_fail = AiTask.OnFail.PROPAGATE
	var route := AiTaskSequence.new()
	route.id = &"route"
	route.children = [failing, ScriptedTask.make(&"last", AiTask.Layer.ROUTINE, 0.2)]
	runner.assign(route)
	_run(runner, 0.5)
	assert_int(route.state).is_equal(AiTask.State.FAILED)
	assert_int(route.reason).is_equal(AiTask.Reason.BLOCKED)
	var skipping := ScriptedTask.make(&"step", AiTask.Layer.ROUTINE, 0.2)
	skipping.fail_with = AiTask.Reason.BLOCKED
	var last := ScriptedTask.make(&"last", AiTask.Layer.ROUTINE, 0.2)
	var tolerant := AiTaskSequence.new()
	tolerant.id = &"tolerant"
	tolerant.children = [skipping, last]
	runner.assign(tolerant)
	_run(runner, 0.6)
	assert_int(last.state).is_equal(AiTask.State.SUCCEEDED)
	assert_int(tolerant.state).is_equal(AiTask.State.SUCCEEDED)


func test_a_failing_task_cannot_storm() -> void:
	var runner := _runner()
	runner.profile.failure_budget = 3
	runner.profile.failure_window = 10.0
	runner.profile.fallback_seconds = 5.0
	var idle := ScriptedTask.make(&"idle", AiTask.Layer.DEFAULT, 0.0)
	runner.assign(idle)
	var unreachable := ScriptedTask.make(&"go_to", AiTask.Layer.ROUTINE, 0.1)
	unreachable.fail_with = AiTask.Reason.NO_PATH
	unreachable.on_fail = AiTask.OnFail.RETRY
	unreachable.retry_count = 1000
	unreachable.retry_delay = 0.0
	runner.assign(unreachable)
	_run(runner, 4.0)
	assert_int(unreachable.starts).is_equal(3)
	assert_int(unreachable.state).is_equal(AiTask.State.FAILED)
	assert_bool(runner.in_fallback()).is_true()
	assert_object(runner.active).is_same(idle)


# Kit #1246: a storm stops retries, not a task's own fallback (a cornered flight's cower), which
# runs once per task and cannot loop; a response that fails during the storm still answers.
func test_a_failure_storm_still_runs_a_tasks_own_fallback() -> void:
	var runner := _runner()
	runner.profile.failure_budget = 1
	runner.profile.fallback_seconds = 5.0
	runner.assign(ScriptedTask.make(&"idle", AiTask.Layer.DEFAULT, 0.0))
	var walk := ScriptedTask.make(&"walk", AiTask.Layer.ROUTINE, 0.1)
	walk.fail_with = AiTask.Reason.NO_PATH
	runner.assign(walk)
	_run(runner, 0.3)
	assert_bool(runner.in_fallback()).is_true()
	var flee := ScriptedTask.make(&"flee", AiTask.Layer.RESPONSE, 0.1)
	flee.fail_with = AiTask.Reason.NO_PATH
	flee.on_fail = AiTask.OnFail.FALLBACK
	flee.fallback = ScriptedTask.make(&"cower", AiTask.Layer.RESPONSE, 1.0)
	var again := ScriptedTask.make(&"flee_again", AiTask.Layer.RESPONSE, 0.1)
	again.fail_with = AiTask.Reason.NO_PATH
	again.on_fail = AiTask.OnFail.RETRY
	again.retry_count = 5
	again.retry_delay = 0.0
	again.replace_policy = AiTask.ReplacePolicy.QUEUE
	runner.assign(flee)
	runner.assign(again)
	_run(runner, 0.5)
	assert_bool(runner.in_fallback()).is_true()
	assert_object(runner.active).is_same(flee)
	assert_int(flee.state).is_equal(AiTask.State.RUNNING)
	_run(runner, 1.0)
	assert_int(flee.state).is_equal(AiTask.State.SUCCEEDED)
	_run(runner, 0.5)
	assert_int(again.starts).is_equal(1)
	assert_int(again.state).is_equal(AiTask.State.FAILED)
