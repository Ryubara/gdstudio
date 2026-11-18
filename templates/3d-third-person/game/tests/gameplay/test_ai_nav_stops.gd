# An AI that runs or sprints to a point comes to rest on it (gdstudio #1415): since a body on its
# feet slows over its stop clip (`CharacterTuning.stop_deceleration`, 0.85 m from a jog and 2.09 m
# from a sprint since gdstudio #1567), the navigator lets go of the stick once what is left of the
# path is the body's stopping distance (`CharacterTuning.stop_distance`), not at `arrive_distance`.
# Every stock task's walk (a patrol point, a cover point, a spot to look at) is a `go_to`, measured
# here at a jog and a sprint, straight and round a corner; a follower comes to rest inside its band
# and so counts as arrived (gdstudio #1529).
#
# Before, it let go at 0.5 m and ran on past the point by the rest of the stop. A follower let
# go to stop on the band's edge, came to rest up to `arrive_distance` outside it and stood there
# "walking" (not arrived, its stuck watch never sampled) until its leader moved: the AI soak's
# allies broke its stuck share.
extends GdUnitTestSuite

## The furthest a body may come to rest past its point, or short of it (m).
const OVERSHOOT := 0.35
const SHORT := 0.6
## Ticks after arriving for the body to come to rest.
const REST_TICKS := 180
## The band the follow cases keep (the stock `AiFollow`'s).
const BAND := 2.5
## Seconds a follow case runs: the longest (14 m at a walk) arrives in about 6.
const FOLLOW_SECONDS := 8.0

var _arena: NavArena


func before_test() -> void:
	_arena = auto_free(NavArena.new())
	add_child(_arena)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


# Walks from `from` to `goal` at `speed` and returns where it came to rest: the distance past the
# goal along the way it last came (negative: short of it), the distance from the goal, the top
# speed and the seconds from letting go to rest.
func _walk(from: Vector3, goal: Vector3, speed: float) -> Dictionary:
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()
	var navigator := _arena.add_walker(from)
	var body := navigator.character
	navigator.go_to(goal, speed)
	var top := 0.0
	var heading := Vector3.ZERO
	var ticks := roundi(20.0 * Engine.physics_ticks_per_second)
	var arrived := false
	for _tick in ticks:
		await get_tree().physics_frame
		top = maxf(top, body.ground_speed())
		if body.ground_speed() > 0.5:
			heading = Vector3(body.velocity.x, 0.0, body.velocity.z).normalized()
		if navigator.is_arrived():
			arrived = true
			break
	assert_bool(arrived).override_failure_message("never arrived").is_true()
	for _tick in REST_TICKS:
		await get_tree().physics_frame
		if body.ground_speed() > 0.5:
			heading = Vector3(body.velocity.x, 0.0, body.velocity.z).normalized()
	var off := AiNavPath.flat(body.global_position - goal)
	return {
		"past": off.dot(heading),
		"away": off.length(),
		"top": top,
		"resting": body.ground_speed(),
	}


func _check(run: String, found: Dictionary) -> String:
	var line := (
		"%s: top %.2f m/s, at rest %.3f m past the point (%.3f m from it), %.3f m/s"
		% [run, found.top, found.past, found.away, found.resting]
	)
	print(line)
	if found.past > OVERSHOOT or found.past < -SHORT or found.resting > 0.05:
		return line
	return ""


func test_a_jog_to_a_point_ends_on_it() -> void:
	var failure := _check("jog", await _walk(Vector3(-10, 0, -6), Vector3(9, 0, -6), 1.0))
	assert_str(failure).is_empty()


func test_a_sprint_to_a_point_ends_on_it() -> void:
	var failure := _check("sprint", await _walk(Vector3(-10, 0, -6), Vector3(9, 0, -6), 1.5))
	assert_str(failure).is_empty()


func test_a_sprint_round_the_arena_ends_on_its_point() -> void:
	var failure := _check(
		"sprint, diagonal", await _walk(Vector3(-8, 0, -8), Vector3(8, 0, 6), 1.5)
	)
	assert_str(failure).is_empty()


func test_the_stopping_distance_is_the_stop_decelerations_ground() -> void:
	# Called by name, so the suite loads where the function is missing.
	var tuning := CharacterTuning.new()
	assert_bool(tuning.has_method(&"stop_distance")).is_true()
	if not tuning.has_method(&"stop_distance"):
		return
	assert_float(tuning.call(&"stop_distance", 0.0)).is_equal(0.0)
	var walk_rate: float = tuning.get(&"walk_stop_deceleration")
	var run_rate: float = tuning.get(&"run_stop_deceleration")
	var walk := pow(tuning.walk_speed, 2.0) / (2.0 * walk_rate)
	assert_float(tuning.call(&"stop_distance", tuning.walk_speed)).is_equal_approx(walk, 0.0001)
	var jog := walk + (pow(tuning.run_speed, 2.0) - pow(tuning.walk_speed, 2.0)) / (2.0 * run_rate)
	assert_float(tuning.call(&"stop_distance", tuning.run_speed)).is_equal_approx(jog, 0.0001)
	assert_float(tuning.call(&"stop_distance", tuning.sprint_speed)).is_equal_approx(2.02, 0.05)


# The farthest from its leader a follower stays arrived: once inside the band it walks again only
# past the band and `AiNavigator.FOLLOW_SLACK` (a leader that stops while it stands may be there).
func _kept() -> float:
	return BAND + AiNavigator.FOLLOW_SLACK


# Follows a still leader from `start` metres away at `speed` in the built arena and returns what
# failed (empty: it was arrived and at rest `FOLLOW_SECONDS` on, within `_kept()`).
func _follow_still(start: float, speed: float) -> String:
	var leader := Node3D.new()
	_arena.add_child(leader)
	leader.position = Vector3(9, 0, -6)
	var navigator := _arena.add_walker(Vector3(9.0 - start, 0, -6))
	var body := navigator.character
	navigator.follow(leader, BAND, speed)
	for _tick in roundi(FOLLOW_SECONDS * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	var away := AiNavPath.flat(leader.global_position - body.global_position).length()
	var line := (
		"follow from %.1f m at %.1f: at rest %.3f m from the leader (band %.1f), %.3f m/s, arrived %s"
		% [start, speed, away, BAND, body.ground_speed(), navigator.is_arrived()]
	)
	print(line)
	var failed := not navigator.is_arrived() or away > _kept() or body.ground_speed() > 0.05
	leader.free()
	body.free()
	return line if failed else ""


func test_a_follower_comes_to_rest_inside_its_band() -> void:
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()
	var failures := PackedStringArray()
	for speed: float in [0.4, 1.0, 1.5]:
		for start: float in [3.1, 3.6, 4.5, 9.0]:
			var failure := await _follow_still(start, speed)
			if not failure.is_empty():
				failures.append(failure)
	assert_str("\n".join(failures)).is_empty()


# Follows a leader that walks off at `pace` m/s for `walk_seconds`, then stands, and returns what
# failed (empty: the follower was arrived and at rest within `_kept()` `FOLLOW_SECONDS` later).
func _follow_walker(pace: float, walk_seconds: float, speed: float) -> String:
	var leader := Node3D.new()
	_arena.add_child(leader)
	leader.position = Vector3(-6, 0, -6)
	var navigator := _arena.add_walker(Vector3(-9, 0, -6))
	var body := navigator.character
	navigator.follow(leader, BAND, speed)
	var walk_ticks := roundi(walk_seconds * Engine.physics_ticks_per_second)
	for tick in roundi(FOLLOW_SECONDS * Engine.physics_ticks_per_second) + walk_ticks:
		if tick < walk_ticks:
			leader.position.x += pace / Engine.physics_ticks_per_second
		await get_tree().physics_frame
	var away := AiNavPath.flat(leader.global_position - body.global_position).length()
	var line := (
		"leader at %.1f m/s for %.2f s, follow at %.1f: %.3f m from it (band %.1f), %.3f m/s, arrived %s"
		% [pace, walk_seconds, speed, away, BAND, body.ground_speed(), navigator.is_arrived()]
	)
	print(line)
	var failed := not navigator.is_arrived() or away > _kept() or body.ground_speed() > 0.05
	leader.free()
	body.free()
	return line if failed else ""


func test_a_follower_of_a_leader_that_stops_comes_to_rest_inside_its_band() -> void:
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()
	var failures := PackedStringArray()
	for speed: float in [1.0, 1.5]:
		for pace: float in [2.0, 3.5]:
			for walk_seconds: float in [1.0, 1.6, 2.3, 3.1]:
				var failure := await _follow_walker(pace, walk_seconds, speed)
				if not failure.is_empty():
					failures.append(failure)
	assert_str("\n".join(failures)).is_empty()
