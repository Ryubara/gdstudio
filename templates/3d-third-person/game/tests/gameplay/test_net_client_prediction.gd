# A predicting client against the game server, each in a map of its own: the client moves its body
# at once with each quantized command (`Character.step`, the server's own step) and the server
# applies the same command a tick later. 600 ticks of a route with turns, a sprint and jumps,
# over the map's ramp, end with the client's body within 0.2 mm of the server's when nothing else
# moves; the reconciler's corrections and worst error are logged.
extends GdUnitTestSuite

const ROUTE_TICKS := 600
## Where the route goes in `world/prototype/prototype_level.tscn`: off the dais, to the foot of the
## ramp (`Landings/Ramp`, rising along +X to 2 m at x = 14), up it, back down and round.
const WAYPOINTS: Array[Vector3] = [
	Vector3(2.0, 0.0, 9.0),
	Vector3(6.5, 0.0, 16.0),
	Vector3(13.0, 2.0, 16.0),
	Vector3(6.0, 0.0, 15.0),
	Vector3(0.0, 0.0, 8.0),
	Vector3(-6.0, 0.0, 6.0),
]
const JUMPS: Array[int] = [140, 300, 470]

var _rig: OnlineRig
var _client: NetClient
var _waypoint := 0
var _highest := -INF


func before_test() -> void:
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_waypoint = 0
	_highest = -INF


func test_a_route_over_the_ramp_ends_where_the_server_body_ends() -> void:
	_client = await _rig.join("Ada")
	assert_object(_client).is_not_null()
	_rig.controllers[0].plan = _route
	await _rig.wait(ROUTE_TICKS + 90)
	var body := _client.player
	var server_body := _rig.server_body(_client)
	var gap := body.global_position.distance_to(server_body.global_position)
	var reconciler := _client.reconciler
	prints(
		"prediction: %d ticks, gap %.6f m," % [ROUTE_TICKS, gap],
		"corrections",
		reconciler.corrections,
		"snaps",
		reconciler.snaps,
		"worst error %.4f m," % reconciler.worst_error,
		"waypoint",
		_waypoint,
		"highest %.2f m" % _highest
	)
	(
		assert_float(gap)
		. override_failure_message(
			"client %s, server %s" % [body.global_position, server_body.global_position]
		)
		. is_less(0.0002)
	)
	# It went over the ramp and round, and the server answered every command.
	assert_float(_highest).is_greater(1.6)
	assert_int(_waypoint).is_greater_equal(WAYPOINTS.size() - 1)
	assert_int(_rig.server.peer_at(_client.slot).ack).is_greater(ROUTE_TICKS)
	assert_int(reconciler.lost).is_equal(0)
	assert_float(reconciler.worst_error).is_less(Reconciler.DEAD_ZONE)


func test_the_client_body_is_tuned_as_the_server_body() -> void:
	_client = await _rig.join("Ada")
	var body := _client.player
	var server_body := _rig.server_body(_client)
	for kind in ["tuning", "prone_tuning", "slide_tuning"]:
		var ours: Resource = body.get(kind)
		var theirs: Resource = server_body.get(kind)
		for property in ours.get_property_list():
			if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var field: String = property["name"]
			assert_that(ours.get(field)).override_failure_message("%s.%s" % [kind, field]).is_equal(
				theirs.get(field)
			)
	assert_float(body.floor_max_angle).is_equal(server_body.floor_max_angle)
	assert_float(body.floor_snap_length).is_equal(server_body.floor_snap_length)
	assert_int(body.collision_mask).is_equal(server_body.collision_mask)


# The route: toward each waypoint in turn, looking where it goes; sprinting on the flat, a jump at
# each of `JUMPS`; standing still after `ROUTE_TICKS`.
func _route(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var at := _client.player.global_position
	_highest = maxf(_highest, at.y)
	if tick >= ROUTE_TICKS:
		command.yaw = _client.player.view_yaw
		return command
	var target := WAYPOINTS[mini(_waypoint, WAYPOINTS.size() - 1)]
	var way := Vector3(target.x - at.x, 0.0, target.z - at.z)
	if way.length() < 0.8 and _waypoint < WAYPOINTS.size() - 1:
		_waypoint += 1
	command.set_from_world(way, way)
	command.sprint = _waypoint != 2
	command.jump_pressed = JUMPS.has(tick)
	command.jump = command.jump_pressed
	return command
