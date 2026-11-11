# Each stock task on a real body (kit #968), assigned by hand to a guard whose brain routes nothing:
# a wait, a walk and its unreachable goal, a follow and its lost leader, a wander that stays home, a
# look and a look round, a search that visits its spots, a chase that loses the trail, a flight, a
# cower that calms, a guard that goes back to its post, a door used with the use button, a link
# crossed by a task, and a bark. The fight, cover and patrol are in `test_ai_reactions.gd`.
extends GdUnitTestSuite

var _arena: BehaviourArena


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_arena.add_director()


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _ready_arena() -> void:
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()


func _until(done: Callable, limit: int) -> int:
	for tick in limit:
		if done.call():
			return tick
		await get_tree().physics_frame
	return -1 if not done.call() else limit


# A guard at `spot` facing `heading` whose brain routes nothing (its tasks come from the test).
func _body(spot: Vector3, heading := 0.0) -> AiCharacter:
	var character := _arena.add_kind(BehaviourArena.GUARD, spot, heading)
	var brain := BehaviourArena.brain_of(character)
	brain.behaviour = null
	brain.home = spot
	return character


func _give(character: AiCharacter, task: AiTask, subject: Node3D = null) -> AiTask:
	task.target = subject
	return BehaviourArena.runner_of(character).assign(task, &"test")


func _ended(task: AiTask) -> Callable:
	return func() -> bool: return task.is_done()


func test_a_wait_waits_its_seconds_and_drives_nothing() -> void:
	await _ready_arena()
	var body := _body(Vector3.ZERO)
	var wait := AiWait.new()
	wait.seconds = 1.0
	_give(body, wait)
	var took := await _until(_ended(wait), 120)
	assert_int(took).is_between(55, 75)
	assert_int(wait.state).is_equal(AiTask.State.SUCCEEDED)
	assert_int(wait.claimed_channels()).is_equal(0)


func test_a_go_to_walks_there_and_fails_on_a_goal_it_cannot_reach() -> void:
	# A walled pocket, x and z 9 to 13 inside: on the mesh, but no way in.
	_arena.add_wall(Rect2i(8, 8, 6, 1))
	_arena.add_wall(Rect2i(8, 13, 6, 1))
	_arena.add_wall(Rect2i(8, 9, 1, 4))
	_arena.add_wall(Rect2i(13, 9, 1, 4))
	await _ready_arena()
	var body := _body(Vector3(-6, 0, -6))
	var walk := AiGoTo.new()
	walk.goal = Vector3(6, 0, -6)
	_give(body, walk)
	assert_int(await _until(_ended(walk), 1200)).is_not_negative()
	assert_int(walk.state).is_equal(AiTask.State.SUCCEEDED)
	assert_float(body.global_position.distance_to(Vector3(6, 0, -6))).is_less(1.2)
	var blocked := AiGoTo.new()
	blocked.goal = Vector3(11, 0, 11)
	_give(body, blocked)
	assert_int(await _until(_ended(blocked), 900)).is_not_negative()
	assert_int(blocked.state).is_equal(AiTask.State.FAILED)
	assert_int(blocked.reason).is_equal(AiTask.Reason.NO_PATH)


func test_a_follow_keeps_near_a_moving_leader_and_fails_when_it_is_gone() -> void:
	await _ready_arena()
	var body := _body(Vector3(-6, 0, 0))
	var leader := _arena.add_target("Leader", Vector3(-4, 0, 0))
	var follow := AiFollow.new()
	_give(body, follow, leader)
	leader.global_position = Vector3(6, 0, 0)
	var near := func() -> bool:
		return body.global_position.distance_to(leader.global_position) < 3.2
	assert_int(await _until(near, 600)).is_not_negative()
	leader.free()
	assert_int(await _until(_ended(follow), 30)).is_not_negative()
	assert_int(follow.reason).is_equal(AiTask.Reason.TARGET_LOST)


func test_a_wander_walks_about_and_stays_within_its_home_radius() -> void:
	await _ready_arena()
	var body := _body(Vector3(2, 0, 2))
	BehaviourArena.brain_of(body).home_radius = 4.0
	_give(body, AiWander.new())
	var farthest := 0.0
	var walked := 0.0
	var last := body.global_position
	for _tick in 900:
		await get_tree().physics_frame
		farthest = maxf(farthest, body.global_position.distance_to(Vector3(2, 0, 2)))
		walked += body.global_position.distance_to(last)
		last = body.global_position
	assert_float(walked).is_greater(3.0)
	assert_float(farthest).is_less(4.8)


func test_a_look_at_turns_the_look_to_its_goal_and_a_look_around_sweeps_both_ways() -> void:
	await _ready_arena()
	var body := _body(Vector3.ZERO, 0.0)
	var look := AiLookAt.new()
	look.goal = Vector3(5, 0, 0)
	look.seconds = 0.5
	_give(body, look)
	await _until(func() -> bool: return look.state == AiTask.State.RUNNING, 30)
	await get_tree().physics_frame
	assert_float(body.ai_controller().look_direction.x).is_greater(0.9)
	await _until(_ended(look), 60)
	var around := AiLookAround.new()
	around.seconds = 3.0
	_give(body, around)
	var lowest := 0.0
	var highest := 0.0
	for _tick in 180:
		await get_tree().physics_frame
		var x := body.ai_controller().look_direction.x
		lowest = minf(lowest, x)
		highest = maxf(highest, x)
	assert_float(highest).is_greater(0.5)
	assert_float(lowest).is_less(-0.5)


func test_a_search_visits_its_spots_and_ends() -> void:
	await _ready_arena()
	var body := _body(Vector3(-4, 0, -4))
	var search := AiSearch.new()
	search.goal = Vector3(2, 0, 2)
	search.spots = 2
	search.look_seconds = 0.5
	_give(body, search)
	assert_int(await _until(_ended(search), 1800)).is_not_negative()
	assert_int(search.state).is_equal(AiTask.State.SUCCEEDED)
	assert_int(search.visited).is_equal(3)


func test_a_chase_that_reaches_the_place_with_nothing_there_loses_the_trail() -> void:
	await _ready_arena()
	var body := _body(Vector3(-6, 0, 0))
	var chase := AiChase.new()
	chase.goal = Vector3(4, 0, 0)
	_give(body, chase)
	assert_int(await _until(_ended(chase), 900)).is_not_negative()
	assert_int(chase.reason).is_equal(AiTask.Reason.TARGET_LOST)
	assert_str(String(chase.event_for(chase.reason))).is_equal("lost_trail")
	assert_float(body.global_position.distance_to(Vector3(4, 0, 0))).is_less(2.0)


func test_a_flight_gets_away_from_the_threat() -> void:
	await _ready_arena()
	var body := _body(Vector3(0, 0, 0))
	var flee := AiFlee.new()
	flee.goal = Vector3(0, 0, -2)
	flee.safe_distance = 10.0
	_give(body, flee)
	assert_int(await _until(_ended(flee), 900)).is_not_negative()
	assert_int(flee.state).is_equal(AiTask.State.SUCCEEDED)
	assert_float(body.global_position.distance_to(Vector3(0, 0, -2))).is_greater_equal(9.5)


func test_a_cower_crouches_and_gets_up_once_the_threat_is_gone() -> void:
	await _ready_arena()
	var body := _body(Vector3.ZERO)
	body.situation.request(AiSituation.Situation.FLEEING)
	var cower := AiCower.new()
	cower.calm_seconds = 1.0
	_give(body, cower)
	await _until(func() -> bool: return cower.state == AiTask.State.RUNNING, 30)
	await get_tree().physics_frame
	assert_bool(body.ai_controller().crouch).is_true()
	assert_int(await _until(_ended(cower), 180)).is_not_negative()
	assert_bool(body.ai_controller().crouch).is_false()
	await _until(func() -> bool: return body.situation.current == AiSituation.Situation.ALERT, 120)
	assert_int(body.situation.current).is_equal(AiSituation.Situation.ALERT)


func test_a_guard_goes_back_to_its_post() -> void:
	await _ready_arena()
	var body := _body(Vector3(0, 0, 0))
	var guard := AiGuard.new()
	guard.goal = Vector3(0, 0, 0)
	_give(body, guard)
	await get_tree().physics_frame
	body.teleport(Vector3(5, 0, 3), 0.0)
	var home := func() -> bool: return body.global_position.distance_to(Vector3.ZERO) < guard.radius
	assert_int(await _until(home, 600)).is_not_negative()
	assert_bool(guard.is_done()).is_false()


func test_a_door_is_used_with_the_use_button() -> void:
	await _ready_arena()
	# Added after the map settled (the door brings navigation of its own).
	var door := (load("res://gameplay/door/door.tscn") as PackedScene).instantiate() as Door
	door.position = Vector3(4, 0, 0)
	_arena.add_child(door)
	var body := _body(Vector3(-4, 0, 0), PI / 2.0)
	var use := AiUseObject.new()
	_give(body, use, door)
	assert_int(await _until(_ended(use), 600)).is_not_negative()
	assert_int(use.state).is_equal(AiTask.State.SUCCEEDED)
	assert_bool(use.used).is_true()
	var moving := func() -> bool: return door.is_open() or door.is_moving()
	assert_int(await _until(moving, 60)).is_not_negative()


func test_a_link_left_to_a_task_is_crossed_and_the_walk_goes_on() -> void:
	# A strip with no mesh across the arena, the floor still under it, and a link over it.
	_arena.add_wall(Rect2i(-1, -14, 2, 28), 2.0, false)
	_arena.add_link(Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0))
	await _ready_arena()
	var body := _arena.add_kind(BehaviourArena.GUARD, Vector3(-6, 0, 0), PI / 2.0)
	(body.navigator as AiNavigator).auto_traverse_links = false
	var started: Array[StringName] = []
	var runner := BehaviourArena.runner_of(body)
	runner.task_started.connect(func(task: AiTask) -> void: started.append(task.id))
	await _until(func() -> bool: return BehaviourArena.active_of(body) != &"", 60)
	BehaviourArena.brain_of(body).order(AiBehaviourSet.ORDER_GO, Vector3(6, 0, 0))
	var there := func() -> bool: return body.global_position.distance_to(Vector3(6, 0, 0)) < 1.2
	assert_int(await _until(there, 900)).override_failure_message(str(started)).is_not_negative()
	assert_array(started).contains([&"traverse_link"])


func test_a_say_barks_once_through_the_brain() -> void:
	await _ready_arena()
	var body := _body(Vector3.ZERO)
	var lines: Array[StringName] = []
	BehaviourArena.brain_of(body).barked.connect(func(line: StringName) -> void: lines.append(line))
	var say := AiSay.new()
	say.line = &"over_here"
	_give(body, say)
	assert_int(await _until(_ended(say), 30)).is_not_negative()
	assert_array(lines).is_equal([&"over_here"])
