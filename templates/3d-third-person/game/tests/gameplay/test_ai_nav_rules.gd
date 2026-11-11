# The navigator's rules without a world: the path follower passes a corner it ran wide of and
# never the start of a link, the stuck watch judges progress along the path (a body sliding along a
# wall is stuck, a U-turn round a corner is not, a shuffle stays stuck until net progress), the
# ladder climbs its rungs in order, a route is kept while a new one is much longer (a target off
# the mesh flipping sides), and remembered goals expire.
extends GdUnitTestSuite

const TICK := 1.0 / 60.0


func _path(points: Array[Vector3], links: Array[int] = []) -> AiNavPath:
	var path := AiNavPath.new()
	var ids := PackedInt64Array()
	for index in points.size():
		ids.append(links[index] if index < links.size() else 0)
	path.assign(PackedVector3Array(points), ids)
	return path


func test_a_corner_run_wide_of_is_passed() -> void:
	var path := _path([Vector3.ZERO, Vector3(5, 0, 0), Vector3(5, 0, 5)])
	# 0.8 m wide of the corner, nearer the next point than the corner is.
	path.advance(Vector3(5.8, 0, 0.6), 0.6)
	assert_int(path.index).is_equal(2)


func test_the_start_of_a_link_is_passed_only_by_reaching_it() -> void:
	var path := _path([Vector3.ZERO, Vector3(5, 0, 0), Vector3(8, 0, 0)], [0, 7, 0])
	path.advance(Vector3(5.8, 0, 0.0), 0.6)
	assert_int(path.index).is_equal(1)
	path.advance(Vector3(5.3, 0, 0.0), 0.6)
	assert_int(path.index).is_equal(2)


func test_a_point_a_storey_up_is_not_reached_from_below() -> void:
	var path := _path([Vector3.ZERO, Vector3(2, 1.5, 0), Vector3(6, 1.5, 0)])
	path.advance(Vector3(2.1, 0, 0), 0.6)
	assert_int(path.index).is_equal(1)


func test_the_last_point_is_reached_only_within_the_arrive_distance() -> void:
	var path := _path([Vector3.ZERO, Vector3(4, 0, 0)])
	path.advance(Vector3(3.45, 0, 0), 0.6, 0.5)
	assert_bool(path.is_finished()).is_false()
	path.advance(Vector3(3.55, 0, 0), 0.6, 0.5)
	assert_bool(path.is_finished()).is_true()


func test_the_steer_point_skips_near_points_and_stops_at_a_link() -> void:
	var path := _path(
		[Vector3.ZERO, Vector3(0.3, 0, 0), Vector3(3, 0, 0), Vector3(6, 0, 0)], [0, 0, 9, 0]
	)
	assert_vector(path.steer_point(Vector3.ZERO, 0.5)).is_equal(Vector3(3, 0, 0))


func test_what_is_left_is_measured_along_the_path() -> void:
	var path := _path([Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 3)])
	assert_float(path.left(Vector3(1, 0, 0))).is_equal_approx(6.0, 0.001)


# A body pressed against a wall slides along it: it moves every tick and the path left stays.
func test_a_body_sliding_along_a_wall_is_stuck() -> void:
	var watch := AiStuckWatch.new()
	var began := false
	for tick in 60:
		began = watch.sample(TICK, 4.0, 10.0 - tick * 0.001) or began
	assert_bool(began).is_true()
	assert_int(watch.episodes).is_equal(1)


func test_a_u_turn_round_a_corner_is_not_stuck() -> void:
	var watch := AiStuckWatch.new()
	var left := 10.0
	for tick in 120:
		# Slow through the turn (a quarter of the speed for half a second), then on.
		var speed := 1.0 if tick > 20 and tick < 50 else 4.0
		left -= speed * TICK
		watch.sample(TICK, 4.0, left)
	assert_int(watch.episodes).is_equal(0)


func test_a_shuffle_stays_stuck_until_net_progress() -> void:
	var watch := AiStuckWatch.new()
	for tick in 40:
		watch.sample(TICK, 4.0, 10.0)
	assert_bool(watch.stuck).is_true()
	# Back and forth by 0.3 m: no net progress.
	for tick in 120:
		watch.sample(TICK, 4.0, 10.0 - 0.3 * absf(sin(tick * 0.2)))
	assert_bool(watch.stuck).is_true()
	watch.sample(TICK, 4.0, 9.4)
	assert_bool(watch.stuck).is_false()
	assert_float(watch.longest_episode).is_greater(2.0)


func test_a_slow_walk_is_never_judged() -> void:
	var watch := AiStuckWatch.new()
	for tick in 120:
		watch.sample(TICK, 0.9, 10.0)
	assert_int(watch.episodes).is_equal(0)


func test_the_ladder_climbs_its_rungs_in_order() -> void:
	var ladder := AiStuckLadder.new()
	ladder.start()
	var seen: Array[int] = [ladder.rung]
	for _step in 6:
		ladder.next()
		seen.append(ladder.rung)
	(
		assert_array(seen)
		. is_equal(
			[
				AiStuckLadder.Rung.SIDESTEP,
				AiStuckLadder.Rung.REPATH,
				AiStuckLadder.Rung.JUMP,
				AiStuckLadder.Rung.DROP_GOAL,
				AiStuckLadder.Rung.BREADCRUMB,
				AiStuckLadder.Rung.REPORT,
				AiStuckLadder.Rung.REPORT,
			]
		)
	)
	assert_int(ladder.reports).is_equal(1)


func test_the_sidestep_swaps_sides_each_climb() -> void:
	var ladder := AiStuckLadder.new()
	ladder.start()
	var first := ladder.side
	ladder.reset()
	ladder.start()
	assert_float(ladder.side).is_equal(-first)


# Deadnight #950: a target squeezed between two cars, whose nearest point changes side as it moves
# a metre; the routes to the sides were 10 m and 29 m.
func test_a_route_is_kept_while_a_new_one_is_much_longer() -> void:
	var target := Vector3(0, 0, 0)
	assert_bool(AiRouteRules.keeps_route(10.0, Vector3(1, 0, 0), 29.0, target)).is_true()
	assert_bool(AiRouteRules.keeps_route(10.0, Vector3(1, 0, 0), 14.0, target)).is_false()
	# An old route that ends far from the target, or is nearly walked, is not kept.
	assert_bool(AiRouteRules.keeps_route(10.0, Vector3(5, 0, 0), 29.0, target)).is_false()
	assert_bool(AiRouteRules.keeps_route(0.8, Vector3(1, 0, 0), 29.0, target)).is_false()


func test_a_remembered_goal_expires() -> void:
	var memory := AiRouteRules.GoalMemory.new()
	memory.remember(Vector3(3.2, 0, 4.7), 5.0)
	assert_bool(memory.holds(Vector3(3.4, 0, 4.9), 4.9)).is_true()
	assert_bool(memory.holds(Vector3(6.0, 0, 4.9), 4.9)).is_false()
	assert_bool(memory.holds(Vector3(3.4, 0, 4.9), 5.0)).is_false()
