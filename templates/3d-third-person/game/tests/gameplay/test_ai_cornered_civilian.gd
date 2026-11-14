# A civilian penned where no flee point is reachable, with a hostile in view and shots going off
# round it (kit #1246, found by the AI soak of #971): it cowers within 2 s and keeps cowering. A
# penned character's walks fail `NO_PATH` (here a walk out of the pen, as a wander or the walk
# home did in the soak), so the runner's failure budget runs out; its flee fails `NO_PATH` too,
# and the flee's own fallback (the cower) must still run then, or it stands looking about with the
# hostile in view while every reminder's flee fails and keeps the budget spent.
extends GdUnitTestSuite

## Where the civilian stands, in the middle of its pen.
const SPOT := Vector3(-0.5, 0.0, -0.5)
## Physics ticks a second (the suites run at 60).
const SECOND := 60

var _arena: BehaviourArena


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_arena.add_director()


func after_test() -> void:
	AudioDrain.stop_all(_arena)
	AiNoise._runs_here = -1


# A pen of tall walls round the cells -3 to 2 on x and z: an island of the mesh, nothing outside
# it reachable.
func _pen() -> void:
	_arena.add_wall(Rect2i(-4, -4, 8, 1))
	_arena.add_wall(Rect2i(-4, 3, 8, 1))
	_arena.add_wall(Rect2i(-4, -3, 1, 6))
	_arena.add_wall(Rect2i(3, -3, 1, 6))
	_arena.build()
	var answered := await _arena.settle(SPOT)
	assert_bool(answered).override_failure_message("the map never answered").is_true()


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


# A walk out of the pen, tried again until the failure budget stops it.
func _walk_out() -> AiGoTo:
	var walk := AiGoTo.new()
	walk.layer = AiTask.Layer.ROUTINE
	walk.goal = Vector3(10.0, 0.0, 10.0)
	walk.on_fail = AiTask.OnFail.RETRY
	walk.retry_count = 10
	walk.retry_delay = 0.2
	return walk


func _crouched(character: AiCharacter) -> bool:
	return character.ai_controller().crouch


func test_a_penned_civilian_with_a_hostile_in_view_cowers_and_stays_cowering() -> void:
	await _pen()
	var civilian := _arena.add_kind(BehaviourArena.CIVILIAN, SPOT, 0.0, {"courage": 0.5})
	var runner := BehaviourArena.runner_of(civilian)
	await _ticks(SECOND / 2)
	runner.assign(_walk_out(), &"test")
	for _i in 5 * SECOND:
		if runner.in_fallback():
			break
		await get_tree().physics_frame
	(
		assert_bool(runner.in_fallback())
		. override_failure_message("the walk out never failed")
		. is_true()
	)
	var hostile := _arena.add_target("Grunt", SPOT + Vector3(0.0, 0.0, 1.8), &"enemy")
	var first := -1
	var longest_up := 0
	var up := 0
	for tick in 16 * SECOND:
		# The fight goes on round it: a shot by the hostile every second.
		if tick % SECOND == 0:
			AiNoise.emit(_arena, &"shot", hostile.global_position, 1.0, hostile)
		await get_tree().physics_frame
		if first < 0:
			if _crouched(civilian):
				first = tick
			continue
		up = 0 if _crouched(civilian) else up + 1
		longest_up = maxi(longest_up, up)
	var story := runner.decisions.dump()
	assert_int(first).override_failure_message("never cowered:\n" + story).is_between(0, 2 * SECOND)
	# A flee placed again lets go of the crouch for a think or two before its cower starts.
	(
		assert_int(longest_up)
		. override_failure_message(
			"stood %d ticks with the hostile in view:\n%s" % [longest_up, story]
		)
		. is_less(SECOND / 2)
	)
	assert_float(civilian.global_position.distance_to(SPOT)).is_less(3.0)


# A civilian near a corner of the mesh with a hostile on the inner side (gdstudio #1532, the AI
# soak's cornered civilians): every point straight away from the hostile lies off the mesh, more
# than the navigator's snap reaches. The flee must pick a point the navigator takes (open ground
# along the edge) and run; on main it picked the farthest point, which the path to the mesh's edge
# called near enough, and the navigator refused it as off open ground, again and again.
func test_a_civilian_in_a_corner_of_the_mesh_runs_along_open_ground() -> void:
	_arena.build()
	var corner := Vector3(11.5, 0.0, 11.5)
	var answered := await _arena.settle(corner)
	assert_bool(answered).override_failure_message("the map never answered").is_true()
	var civilian := _arena.add_kind(BehaviourArena.CIVILIAN, corner, PI * 1.25, {"courage": 0.5})
	var navigator := civilian.navigator as AiNavigator
	var runner := BehaviourArena.runner_of(civilian)
	await _ticks(SECOND / 2)
	var hostile := _arena.add_target("Grunt", corner - Vector3(3.0, 0.0, 3.0), &"enemy")
	var refusals: Array[String] = []
	navigator.failed.connect(func(_why: int) -> void: refusals.append(navigator.refusal))
	var farthest := 0.0
	for tick in 4 * SECOND:
		if tick % SECOND == 0:
			AiNoise.emit(_arena, &"shot", hostile.global_position, 1.0, hostile)
		await get_tree().physics_frame
		farthest = maxf(farthest, civilian.global_position.distance_to(corner))
	var story := "refusals %s\n%s" % [refusals, runner.decisions.dump()]
	(
		assert_float(farthest)
		. override_failure_message("ran %.2f m:\n%s" % [farthest, story])
		. is_greater(4.0)
	)
	assert_array(refusals).override_failure_message(story).is_empty()
