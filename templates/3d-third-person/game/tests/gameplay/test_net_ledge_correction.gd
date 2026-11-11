# A predicting client's body on one side of a ledge while the server's is on the other (gdstudio
# #1119), 240 ms round trip: the client's body stands on the spawn dais's top (`Landings/Dais`,
# 8 m square, 1 m high, round the origin), the server's on the ground against its south wall. A
# quarter of the correction from the top toward a point below and beyond the edge puts the body
# inside the dais, and the next step pushes it back on top; a controller that keeps the body where
# it wants it on the top (the gate's walk round the spawn did) walks it back each time, while the
# server's body, given the same commands, walks into the wall below. Taken in parts the two never
# met (1.4 m apart after 3 s, 12.5 m corrected); the part that lands inside is now followed by the
# rest at once (`BodyOverlap`, `Reconciler.take_rest`), and the bodies agree within a second.
extends GdUnitTestSuite

## On the dais's top, 1 m in from its south edge (z = 4).
const ON_TOP := Vector3(0.5, 1.0, 3.0)
## On the ground against the dais's south wall (the capsule's radius is 0.34 m).
const BELOW := Vector3(0.5, 0.0, 4.4)
## A second of physics ticks.
const SECOND := NetLimits.TICK_RATE
## Seconds each way on the link: the gate's relay delay, a little jitter's worth more.
const ONE_WAY := 0.12

var _rig: OnlineRig
var _client: NetClient
## Where the controller keeps the body (none: it stands).
var _hold := Vector3.INF


func before_test() -> void:
	_rig = auto_free(OnlineRig.new())
	_rig.delay = ONE_WAY
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_hold = Vector3.INF
	_client = await _rig.join("Ada")
	assert_object(_client).is_not_null()
	_rig.controllers[0].plan = _plan


func test_a_body_held_on_top_while_the_server_stands_below_converges() -> void:
	await _put_both(ON_TOP)
	_hold = ON_TOP
	_rig.server_body(_client).teleport(BELOW)
	var gap := await _gap_after(SECOND)
	var reconciler := _client.reconciler
	prints(
		"ledge, held on top: gap %.4f m after a second," % gap,
		"corrections",
		reconciler.corrections,
		"stuck snaps",
		reconciler.stuck_snaps,
		"corrected %.2f m" % reconciler.corrected
	)
	(
		assert_float(gap)
		. override_failure_message(
			(
				"client %s, server %s"
				% [_client.player.global_position, _rig.server_body(_client).global_position]
			)
		)
		. is_less(0.05)
	)
	# Both below, against the wall the commands walk them into.
	assert_float(_client.player.global_position.y).is_less(0.1)
	assert_int(reconciler.stuck_snaps).is_greater_equal(1)
	assert_int(reconciler.lost).is_equal(0)
	# Taken whole, not fought for: about the 1.7 m error once.
	assert_float(reconciler.corrected).is_less(2.5)


func test_a_body_standing_on_top_takes_the_rest_whole() -> void:
	await _put_both(ON_TOP)
	_rig.server_body(_client).teleport(BELOW)
	var gap := await _gap_after(SECOND)
	assert_float(gap).is_less(0.05)
	assert_int(_client.reconciler.stuck_snaps).is_equal(1)
	assert_float(_client.reconciler.corrected).is_less(2.5)


func test_a_correction_with_nothing_in_the_way_is_taken_in_parts() -> void:
	# The same 1.7 m error on open ground east of the dais.
	await _put_both(Vector3(6.0, 0.0, 6.0))
	_rig.server_body(_client).teleport(Vector3(7.0, 0.0, 7.4))
	var gap := await _gap_after(SECOND)
	assert_float(gap).is_less(0.05)
	assert_int(_client.reconciler.stuck_snaps).is_equal(0)
	assert_int(_client.reconciler.corrections).is_greater(1)


func test_the_overlap_is_deep_inside_the_dais_and_none_on_a_floor() -> void:
	var body := _client.player
	await _put_both(ON_TOP)
	assert_float(BodyOverlap.depth(body)).is_less(BodyOverlap.PUSHED_BACK)
	body.global_position = ON_TOP + Vector3(0.0, -0.25, 0.35)
	assert_float(BodyOverlap.depth(body)).is_greater(BodyOverlap.PUSHED_BACK)
	await _put_both(BELOW)
	assert_bool(BodyOverlap.pushed_back(body)).is_false()


# Both bodies at `spot`, standing, settled; the counters start again.
func _put_both(spot: Vector3) -> void:
	_rig.server_body(_client).teleport(spot)
	_client.player.teleport(spot)
	await _rig.wait(SECOND / 2)
	assert_float(_client.player.global_position.distance_to(spot)).is_less(0.05)
	var reconciler := _client.reconciler
	reconciler.corrections = 0
	reconciler.corrected = 0.0
	reconciler.stuck_snaps = 0


func _gap_after(frames: int) -> float:
	await _rig.wait(frames)
	return _client.player.global_position.distance_to(_rig.server_body(_client).global_position)


# Walks toward `_hold` while more than 0.2 m from it, looking where it goes; stands otherwise.
func _plan(_tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = _client.player.view_yaw
	if _hold == Vector3.INF:
		return command
	var way := _hold - _client.player.global_position
	way.y = 0.0
	if way.length() > 0.2:
		command.set_from_world(way, way)
	return command
