# The `AiTasks` node on a real AI character: it steps its runner on the character's think, gives
# the default task and the routine at the start (copies: the inspector's stay untouched), pauses
# on death and resumes on revive, reports a hit, shows the stack with the debug overlay, reads
# the profile live and warns about a task that never ends.
extends GdUnitTestSuite

var _arena: AiArena


func before_test() -> void:
	_arena = auto_free(AiArena.new())
	add_child(_arena)


# Walking characters play footsteps; a voice still playing at exit is reported as a leak.
func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _tasks(character: AiCharacter) -> AiTasks:
	return character.task_runner as AiTasks


func test_the_runner_steps_on_each_think_and_walks_the_body() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	_arena.add_director()
	var walk := ScriptedTask.make(&"walk", AiTask.Layer.ROUTINE, 0.0)
	walk.walk = Vector3.BACK
	_tasks(character).runner.assign(walk)
	await _ticks(40)
	assert_int(walk.updates).is_greater(3)
	assert_float(character.global_position.z).is_greater(-2.0)
	assert_object(_tasks(character).runner.controller).is_same(character.ai_controller())


func test_death_pauses_it_and_a_revive_resumes_it() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	_arena.add_director()
	var walk := ScriptedTask.make(&"walk", AiTask.Layer.ROUTINE, 0.0)
	walk.walk = Vector3.BACK
	var runner := _tasks(character).runner
	runner.assign(walk)
	await _ticks(12)
	character.take_hit(HitRecord.blow(Health.of(character).max_value * 2.0))
	assert_bool(runner.can_think).is_false()
	assert_int(walk.state).is_equal(AiTask.State.SUSPENDED)
	assert_vector(character.ai_controller().walk_direction).is_equal(Vector3.ZERO)
	var updates := walk.updates
	await _ticks(30)
	assert_int(walk.updates).is_equal(updates)
	character.revive()
	await _ticks(12)
	assert_bool(runner.can_think).is_true()
	assert_int(walk.state).is_equal(AiTask.State.RUNNING)
	assert_int(walk.starts).is_equal(1)


func test_a_hit_is_reported_to_the_runner() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	var attacker: Node3D = auto_free(Node3D.new())
	character.take_hit(HitRecord.blow(1.0, attacker))
	assert_object(_tasks(character).runner.beliefs.get(&"attacker")).is_same(attacker)


func test_the_default_task_and_the_routine_start_as_copies() -> void:
	var character := (load(AiArena.CHARACTER) as PackedScene).instantiate() as AiCharacter
	var tasks := character.get_node("AiTasks") as AiTasks
	var idle := ScriptedTask.make(&"idle", AiTask.Layer.DEFAULT, 0.0)
	var patrol := ScriptedTask.make(&"patrol", AiTask.Layer.ROUTINE, 0.0)
	tasks.default_task = idle
	tasks.routine = patrol
	_arena.add_child(character)
	assert_int(tasks.runner.count()).is_equal(2)
	assert_array(tasks.runner.queued(AiTask.Layer.ROUTINE)).not_contains([patrol])
	tasks.runner.tick(0.1)
	assert_str(String(tasks.runner.active_kind())).is_equal("patrol")
	assert_int(patrol.starts).is_equal(0)


func test_the_overlay_shows_the_stack_while_debug_is_on() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	var tasks := _tasks(character)
	tasks.runner.assign(ScriptedTask.make(&"patrol", AiTask.Layer.ROUTINE, 0.0))
	tasks.think(0.1)
	assert_bool(tasks.label.visible).is_false()
	character.debug = true
	tasks.runner.assign(ScriptedTask.make(&"investigate", AiTask.Layer.RESPONSE, 2.0))
	tasks.think(0.1)
	assert_bool(tasks.label.visible).is_true()
	assert_str(tasks.label.text).contains("> Response: investigate")
	assert_str(tasks.label.text).contains("Routine: patrol (suspended)")


func test_it_reads_the_profile_live() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	var tasks := _tasks(character)
	var linger := ScriptedTask.make(&"linger", AiTask.Layer.ROUTINE, 0.0)
	tasks.runner.assign(linger)
	character.profile.task_hard_timeout = 0.5
	for _i in 6:
		tasks.think(0.1)
	assert_int(linger.state).is_equal(AiTask.State.TIMED_OUT)


func test_a_task_that_never_ends_is_a_configuration_warning() -> void:
	var tasks: AiTasks = auto_free(AiTasks.new())
	assert_array(Array(tasks._get_configuration_warnings())).is_empty()
	var order := ScriptedTask.make(&"guard_forever", AiTask.Layer.RESPONSE, 1.0)
	order.hard_timeout = 0.0
	order.ends_on_condition = false
	tasks.attack_task = order
	assert_array(Array(tasks._get_configuration_warnings())).has_size(1)
