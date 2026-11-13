# An AI that runs or sprints to a point comes to rest on it (gdstudio #1415): since a body on its
# feet slows over its stop clip (`CharacterTuning.stop_deceleration`, 1.96 m from a jog and 4.82
# m from a sprint), the navigator lets go of the stick once what is left of the path is the
# body's stopping distance (`CharacterTuning.stop_distance`), not at `arrive_distance`. Every
# stock task's walk (a patrol point, a cover point, a spot to look at) is a `go_to`, measured here
# at a jog and a sprint, straight and round a corner; a follower stops at its band.
#
# Before, it let go at 0.5 m and ran on past the point by the rest of the stop.
extends GdUnitTestSuite

## The furthest a body may come to rest past its point, or short of it (m).
const OVERSHOOT := 0.35
const SHORT := 0.6
## Ticks after arriving for the body to come to rest.
const REST_TICKS := 180

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
	assert_float(tuning.call(&"stop_distance", tuning.sprint_speed)).is_equal_approx(4.80, 0.08)
