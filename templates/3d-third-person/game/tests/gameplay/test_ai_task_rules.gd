# The task runner against rows 7 to 13 of the edge-case table of the research for kit #882
# (timeouts, orders and needs, death, two reactions, assignment while dead, a script error, no
# allocation when idle; rows 1 to 6 are test_ai_task_runner.gd) and the replay of a decision log.
# Each test is written so that a runner without the row's rule fails it; the runner has no scene.
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


func _attack_task() -> ScriptedTask:
	var attack := ScriptedTask.make(&"attack", AiTask.Layer.RESPONSE, 1.0)
	attack.channels = AiTask.Channel.ACTION
	attack.shoots = true
	return attack


# 7. Soft and hard timeouts; the profile's hard timeout for -1; a task that never ends is an
# authoring warning.
func test_soft_and_hard_timeouts() -> void:
	var runner := _runner()
	runner.profile.task_hard_timeout = 1.5
	var wait := ScriptedTask.make(&"wait", AiTask.Layer.ROUTINE, 0.0)
	wait.timeout = 1.0
	wait.hard_timeout = 2.0
	runner.assign(wait)
	_run(runner, 1.1)
	assert_int(wait.timeouts).is_equal(1)
	assert_int(wait.state).is_equal(AiTask.State.RUNNING)
	_run(runner, 1.0)
	assert_int(wait.timeouts).is_equal(1)
	assert_int(wait.state).is_equal(AiTask.State.TIMED_OUT)
	var by_profile := ScriptedTask.make(&"linger", AiTask.Layer.ROUTINE, 0.0)
	runner.assign(by_profile)
	_run(runner, 1.7)
	assert_int(by_profile.state).is_equal(AiTask.State.TIMED_OUT)


func test_a_task_with_no_timeout_and_no_end_is_a_warning() -> void:
	var never := ScriptedTask.make(&"wait_forever", AiTask.Layer.ORDER, 1.0)
	never.hard_timeout = 0.0
	never.ends_on_condition = false
	assert_array(Array(never.authoring_problems())).has_size(1)
	never.ends_on_condition = true
	assert_array(Array(never.authoring_problems())).is_empty()
	var forever := AiTaskRepeat.new()
	forever.layer = AiTask.Layer.RESPONSE
	forever.hard_timeout = 0.0
	forever.children = [ScriptedTask.make(&"step", AiTask.Layer.RESPONSE, 1.0)]
	assert_array(Array(forever.authoring_problems())).has_size(1)
	forever.count = 3
	assert_array(Array(forever.authoring_problems())).is_empty()


# 8. Orders from a script, a mission and a squad: authority decides, revoke removes, a character
# that obeys little refuses a low one; the issuer hears the end of its task.
func test_orders_follow_authority_and_revoke() -> void:
	var runner := _runner()
	runner.profile.obeys_orders = 0.5
	var ended := []
	runner.task_finished.connect(
		func(task: AiTask, _state: int) -> void: ended.append([task.issuer, task.reason])
	)
	var squad := _order(&"follow", AiTask.AUTHORITY_SQUAD)
	var mission := _order(&"guard", AiTask.AUTHORITY_MISSION)
	runner.assign(squad, &"squad")
	_run(runner, 0.2)
	runner.assign(mission, &"mission")
	assert_array(ended).contains([[&"squad", AiTask.Reason.REPLACED]])
	var squad_again := _order(&"regroup", AiTask.AUTHORITY_SQUAD)
	runner.assign(squad_again, &"squad")
	assert_array(runner.queued(AiTask.Layer.ORDER)).is_equal([mission, squad_again])
	var script_order := _order(&"walk_to_mark", AiTask.AUTHORITY_SCRIPT)
	runner.assign(script_order, &"script")
	_run(runner, 0.2)
	assert_object(runner.active).is_same(script_order)
	assert_int(runner.revoke(&"script")).is_equal(1)
	_run(runner, 0.1)
	assert_object(runner.active).is_same(squad_again)
	var newer := _order(&"hold", AiTask.AUTHORITY_SQUAD)
	runner.assign(newer, &"squad_leader")
	_run(runner, 0.1)
	assert_object(runner.active).is_same(newer)


func test_a_character_that_obeys_little_refuses_a_low_order() -> void:
	var runner := _runner()
	runner.profile.obeys_orders = 0.2
	var refused := []
	runner.task_refused.connect(func(task: AiTask, _why: int) -> void: refused.append(task.id))
	assert_object(runner.assign(_order(&"follow", AiTask.AUTHORITY_SQUAD), &"squad")).is_null()
	assert_array(refused).is_equal([&"follow"])
	(
		assert_object(runner.assign(_order(&"guard", AiTask.AUTHORITY_MISSION), &"mission"))
		. is_not_null()
	)


func test_an_order_gives_way_to_a_need_only_as_the_table_says() -> void:
	var runner := _runner()
	runner.needs = AiNeeds.new()
	runner.needs.rows = [_row(&"ammo", &"hold", 1.0), _row(&"ammo", &"*", 0.0)]
	var hold := _order(&"hold", AiTask.AUTHORITY_MISSION)
	runner.assign(hold, &"mission")
	_run(runner, 0.2)
	runner.beliefs[&"ammo"] = 0.5
	assert_object(runner.assign(_need_task())).is_null()
	runner.beliefs[&"ammo"] = 1.0
	var fetch := runner.assign(_need_task())
	assert_object(fetch).is_not_null()
	_run(runner, 0.1)
	assert_object(runner.active).is_same(fetch)
	runner.clear(AiTask.Layer.RESPONSE)
	runner.revoke(&"mission")
	runner.assign(_order(&"roam", AiTask.AUTHORITY_MISSION), &"mission")
	runner.beliefs[&"ammo"] = 0.2
	assert_object(runner.assign(_need_task())).is_not_null()


func _order(task_id: StringName, authority: int) -> ScriptedTask:
	var order := ScriptedTask.make(task_id, AiTask.Layer.ORDER, 30.0)
	order.authority = authority
	return order


func _row(need: StringName, order: StringName, at: float) -> AiNeedRow:
	var row := AiNeedRow.new()
	row.need = need
	row.order = order
	row.gives_way_at = at
	return row


func _need_task() -> ScriptedTask:
	var fetch := ScriptedTask.make(&"fetch_ammo", AiTask.Layer.RESPONSE, 3.0)
	fetch.need = &"ammo"
	return fetch


# 9. The body cannot act: everything pauses with its timers frozen and resumes on revive.
func test_death_pauses_the_runner_and_a_revive_resumes_it() -> void:
	var runner := _runner()
	var patrol := ScriptedTask.make(&"patrol", AiTask.Layer.ROUTINE, 10.0)
	patrol.hard_timeout = 4.0
	patrol.walk = Vector3.LEFT
	runner.assign(patrol)
	_run(runner, 2.0)
	assert_vector(_controller.walk_direction).is_equal(Vector3.LEFT)
	runner.set_can_think(false)
	assert_vector(_controller.walk_direction).is_equal(Vector3.ZERO)
	_run(runner, 6.0)
	assert_int(patrol.state).is_equal(AiTask.State.SUSPENDED)
	assert_float(patrol.elapsed).is_between(1.95, 2.05)
	runner.set_can_think(true)
	_run(runner, 1.0)
	assert_int(patrol.state).is_equal(AiTask.State.RUNNING)
	assert_int(patrol.starts).is_equal(1)
	assert_float(patrol.progress).is_between(2.9, 3.1)


# 10. Two reactions at once: a reaction preempts a response and returns; responses wobbling on a
# threshold change the task once inside the commit time.
func test_a_wobble_changes_the_response_once_and_a_reaction_preempts() -> void:
	var runner := _runner()
	runner.profile.commit_seconds = 0.5
	var started := []
	runner.task_started.connect(func(task: AiTask) -> void: started.append(task.id))
	for index in 4:
		var id := &"take_cover" if index % 2 == 0 else &"flee"
		var task := ScriptedTask.make(id, AiTask.Layer.RESPONSE, 3.0)
		task.replace_policy = AiTask.ReplacePolicy.REPLACE
		runner.assign(task)
		_run(runner, 0.1)
	assert_array(started).is_equal([&"take_cover"])
	var cover := runner.active
	var flinch := ScriptedTask.make(&"flinch", AiTask.Layer.REACTION, 0.3)
	runner.assign(flinch)
	_run(runner, 0.1)
	assert_object(runner.active).is_same(flinch)
	_run(runner, 0.4)
	assert_object(runner.active).is_same(cover)
	assert_int(cover.state).is_equal(AiTask.State.RUNNING)


# 11. A task assigned while dead waits for the revive, unless it expired meanwhile.
func test_a_task_assigned_while_dead_waits_or_expires() -> void:
	var runner := _runner()
	runner.set_can_think(false)
	var order := _order(&"regroup", AiTask.AUTHORITY_MISSION)
	runner.assign(order, &"mission")
	var shout := ScriptedTask.make(&"answer_shout", AiTask.Layer.RESPONSE, 1.0)
	shout.expires_after = 2.0
	runner.assign(shout)
	_run(runner, 3.0)
	assert_int(order.state).is_equal(AiTask.State.PENDING)
	assert_int(order.starts).is_equal(0)
	runner.set_can_think(true)
	_run(runner, 0.1)
	assert_int(shout.state).is_equal(AiTask.State.CANCELLED)
	assert_int(shout.reason).is_equal(AiTask.Reason.EXPIRED)
	assert_object(runner.active).is_same(order)


# 12. A script error in a task: the watchdog ends it FAILED(INVALID), never retries it, logs it
# and keeps the character on DEFAULT.
func test_a_task_that_errors_ends_invalid_and_default_runs() -> void:
	var runner := _runner()
	var idle := ScriptedTask.make(&"idle", AiTask.Layer.DEFAULT, 0.0)
	runner.assign(idle)
	var broken := ScriptedTask.make(&"broken", AiTask.Layer.ROUTINE, 5.0)
	broken.breaks = true
	broken.on_fail = AiTask.OnFail.RETRY
	broken.retry_count = 5
	runner.assign(broken)
	await (
		assert_error(func() -> void: _run(runner, 0.3))
		. is_runtime_error("Cannot call method 'call' on a null value.")
	)
	assert_int(broken.state).is_equal(AiTask.State.FAILED)
	assert_int(broken.reason).is_equal(AiTask.Reason.INVALID)
	assert_int(broken.starts).is_equal(1)
	assert_object(runner.active).is_same(idle)
	assert_bool(runner.in_fallback()).is_true()
	var whats := runner.decisions.entries().map(
		func(entry: Dictionary) -> StringName: return entry.what
	)
	assert_array(whats).contains([&"failed", &"fallback"])


# 13. An idle runner does no work on a step: the counter of steps that ran a task and the decision
# log stay still, and 2000 steps leave the memory and the object count where they were. (Static
# memory sees what a step keeps, not what it frees before it returns; the work counter is what
# catches a runner that selects or describes on an idle step.)
func test_an_idle_runner_does_no_work_and_allocates_nothing_per_step() -> void:
	var runner := _runner()
	runner.assign(ScriptedTask.make(&"blink", AiTask.Layer.RESPONSE, 0.1))
	_run(runner, 0.5)
	assert_int(runner.count()).is_equal(0)
	var written := runner.decisions.written
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var grew := 0
	for _trial in 3:
		var memory := OS.get_static_memory_usage()
		for _i in 2000:
			runner.tick(STEP)
		grew = OS.get_static_memory_usage() - memory
		if grew == 0:
			break
	var objects_now := Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_int(grew).is_equal(0)
	assert_float(objects_now).is_equal(objects)
	assert_int(runner.busy_steps).is_equal(1)
	assert_int(runner.decisions.written).is_equal(written)


# The same event stream, stepped the same way, gives the same decision log.
func test_a_replay_gives_the_same_decisions() -> void:
	var attacker := _attacker()
	var first := _replay(attacker)
	var second := _replay(attacker)
	assert_int(first.size()).is_greater(15)
	assert_array(second).is_equal(first)


func _replay(attacker: Node3D) -> Array[Dictionary]:
	var runner := _runner()
	runner.attack_task = _attack_task()
	var rng := RandomNumberGenerator.new()
	rng.seed = 965
	var route := AiTaskRepeat.new()
	route.id = &"patrol"
	route.children = [ScriptedTask.make(&"leg", AiTask.Layer.ROUTINE, 1.5)]
	runner.assign(route)
	for tick in 200:
		var roll := rng.randi_range(0, 99)
		if roll < 3:
			runner.assign(
				ScriptedTask.make(&"investigate", AiTask.Layer.RESPONSE, rng.randf_range(0.3, 2.0))
			)
		elif roll < 4:
			runner.assign(ScriptedTask.make(&"flinch", AiTask.Layer.REACTION, 0.2))
		elif roll < 5:
			runner.report_damage(rng.randf_range(1.0, 30.0), attacker)
		runner.beliefs[&"tick"] = tick
		runner.tick(STEP)
	return runner.decisions.entries()
