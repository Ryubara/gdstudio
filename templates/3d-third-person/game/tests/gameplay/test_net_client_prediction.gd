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
## The client's thread stalls this many ticks each (0.5 s, inside the server's repeats, and 2 s,
## past them), after walking `STALL_LEAD_TICKS`; the corrections of `STALL_AFTER_TICKS` after each
## are counted.
const STALLS: Array[int] = [30, 120]
const STALL_LEAD_TICKS := 150
const STALL_AFTER_TICKS := 90
## The circles of the stall test: radius (m) and ticks a lap.
const CIRCLE_RADIUS := 3.0
const CIRCLE_TICKS := 360

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


func test_commands_that_arrive_unevenly_are_waited_for_not_repeated() -> void:
	# Two machines' frames drift: a command lands a step late now and then, and the next step has
	# two. The server holds the body a few steps for a late one (`NetServer.hold_ticks`), so the
	# client's prediction stays exact; with no hold each late command is a repeat that leaves the
	# server's body a step ahead, which the client's reconciler has to correct.
	var gaps := {}
	var corrections := {}
	for hold in [4, 0]:
		_rig = auto_free(OnlineRig.new())
		_rig.jitter = 0.03
		add_child(_rig)
		_rig.start()
		_rig.server.hold_ticks = hold
		_waypoint = 0
		_client = await _rig.join("Ada")
		_rig.controllers[0].plan = _route
		await _rig.wait(ROUTE_TICKS + 90)
		var server_body := _rig.server_body(_client)
		gaps[hold] = _client.player.global_position.distance_to(server_body.global_position)
		corrections[hold] = _client.reconciler.corrections
		var peer := _rig.server.peer_at(_client.slot)
		var first := peer.history.find(1)
		prints(
			"uneven commands, hold %d:" % hold,
			"gap %.4f m," % gaps[hold],
			"held",
			peer.history.slice(first).count(PeerSlot.HELD),
			"repeated",
			peer.history.slice(first).count(PeerSlot.REPEATED),
			"corrections",
			_client.reconciler.corrections
		)
	assert_float(gaps[4]).is_less(0.0002)
	assert_int(corrections[4]).is_equal(0)
	# Without the hold the reconciler pulls the body back after every repeat.
	assert_int(corrections[0]).is_greater(50)


func test_a_stall_walks_the_client_body_as_the_server_walked_its_own() -> void:
	# Through a stall of the client's thread the server repeats the last command, then stands its
	# body (`PeerSlot.take`). The answer after the stall puts the client's body on the server's
	# point; a body that kept its speed through the stall then drifts off the server's for a second
	# and every answer corrects it (gdstudio #1127). Stepped as the server stepped (`SilenceWalk`),
	# the second after each stall corrects centimetres; with the walk taken out, decimetres.
	var corrected := {}
	for walked in [true, false]:
		_rig = auto_free(OnlineRig.new(false))
		add_child(_rig)
		assert_bool(_rig.start()).is_true()
		_waypoint = 0
		_client = await _rig.join("Ada")
		assert_object(_client).is_not_null()
		if not walked:
			_client.silence_walk.command_ticks = 0
			_client.silence_walk.most_standing = 0
		_rig.controllers[0].plan = _circle
		await _rig.wait(STALL_LEAD_TICKS)
		corrected[walked] = 0.0
		for stall in STALLS:
			var corrected_before := _client.reconciler.corrected
			_client.process_mode = Node.PROCESS_MODE_DISABLED
			await _rig.wait(stall)
			_client.process_mode = Node.PROCESS_MODE_INHERIT
			await _rig.wait(STALL_AFTER_TICKS)
			corrected[walked] += _client.reconciler.corrected - corrected_before
		prints(
			"stalls, walked %s:" % walked,
			"corrected %.3f m," % corrected[walked],
			"snaps",
			_client.reconciler.snaps,
			"stalls",
			_client.stall_guard.resyncs,
			"walked steps",
			_client.silence_walk.steps
		)
		assert_int(_client.stall_guard.resyncs).is_equal(STALLS.size())
		assert_int(_client.reconciler.lost).is_equal(0)
	# Measured: 0.000 m walked (no snap: the answer after each stall is already exact), 0.170 m
	# and a snap with the walk taken out.
	assert_float(corrected[true]).is_less(0.02)
	assert_float(corrected[false]).is_greater(0.1)


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


# Circles round the point (0, 0, 8), sprinting: the server's repeats go straight on through a
# stall, so its body comes out of it with another speed than one that stood still.
func _circle(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var angle := TAU * tick / CIRCLE_TICKS
	var target := Vector3(cos(angle), 0.0, sin(angle) + 8.0 / CIRCLE_RADIUS) * CIRCLE_RADIUS
	var at := _client.player.global_position
	var way := Vector3(target.x - at.x, 0.0, target.z - at.z)
	var ahead := Vector3(-sin(angle), 0.0, cos(angle))
	command.set_from_world(way + ahead, ahead)
	command.sprint = true
	return command


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
