# The client's side of the wire: puppets drawn 100 ms behind over a link that holds every packet
# 100 ms each way never run out of snapshots; the server's TICK for eight players is still the
# 107 bytes of the #902 budget; a stall of the client's own thread resyncs and skips the catch-up
# ticks, stalls with no answer between them are judged a stall each, and a PONG that waited out a
# stall is no round trip; the interpolation track blends, holds and warps.
extends GdUnitTestSuite

var _rig: OnlineRig


func after_test() -> void:
	_rig = null


func test_puppets_never_starve_at_100_ms_behind_over_a_100_ms_link() -> void:
	_rig = auto_free(OnlineRig.new())
	_rig.delay = 0.1
	_rig.jitter = 0.01
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	assert_object(ada).is_not_null()
	assert_object(bo).is_not_null()
	_rig.controllers[0].plan = func(tick: int) -> PlayerCommand:
		var command := PlayerCommand.new()
		var heading := tick * 0.02
		command.set_from_world(Vector3(sin(heading), 0.0, cos(heading)))
		return command
	await _rig.wait(60)
	var drawer := bo.remote_players
	drawer.starved = 0
	var drawn := 0
	for _frame in 240:
		await get_tree().physics_frame
		drawn += 1 if drawer.puppet_at(ada.slot) != null else 0
	prints("starved:", drawer.starved, "of", drawn, "steps; round trip", ada.rtt_ms, "ms")
	assert_int(drawn).is_equal(240)
	assert_int(drawer.starved).is_equal(0)
	assert_int(ada.rtt_ms).is_greater_equal(200)


func test_a_tick_for_eight_players_is_108_bytes() -> void:
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	var listener := _rig.server.listener as LoopbackListener
	var links: Array[LoopbackLink] = []
	var sizes: Array[int] = []
	for index in NetLimits.MAX_PLAYERS:
		var link := listener.open_link()
		var hello := NetWire.hello("Player%d" % index, _rig.server.world_hash)
		# Bound to the link's own method: a lambda naming the link would hold it forever.
		link.connected.connect(link.send.bind(hello))
		link.packet_received.connect(
			func(data: PackedByteArray) -> void:
				if NetWire.type_of(data) == NetWire.Type.TICK:
					# Less the rows of the props still settling at the start (gdstudio #1073).
					var read := SnapshotCodec.read_tick(data)
					var rows := 0
					for row in read.parts:
						rows += NetWire.STREAM_ROW_HEADER + row.state.size()
					sizes.append(data.size() - rows)
		)
		links.append(link)
	for _frame in 30:
		for link in links:
			link.poll()
		await get_tree().physics_frame
	assert_int(_rig.server.player_count()).is_equal(NetLimits.MAX_PLAYERS)
	# The last TICK carries no event any more (the joins went out first).
	sizes.clear()
	for _frame in 4:
		for link in links:
			link.poll()
		await get_tree().physics_frame
	assert_array(sizes).is_not_empty()
	prints("tick for 8 players:", sizes.max(), "bytes")
	assert_int(sizes.max()).is_less_equal(108)
	for link in links:
		link.close()


func test_a_stall_resyncs_and_skips_the_catch_up_ticks() -> void:
	var now := [0.0]
	var guard := StallGuard.new()
	guard.clock = func() -> float: return now[0]
	for frame in 10:
		now[0] += 1.0 / 60.0
		assert_int(guard.check(frame)).is_equal(StallGuard.Verdict.STEP)
	# The thread froze half a second inside frame 10; the engine catches up with eight ticks in
	# frame 11, a few microseconds apart: the first steps, the other seven are skipped.
	now[0] += 0.5
	assert_int(guard.check(10)).is_equal(StallGuard.Verdict.RESYNC)
	now[0] += 0.001
	assert_int(guard.check(11)).is_equal(StallGuard.Verdict.STEP)
	for _tick in 7:
		now[0] += 0.0001
		assert_int(guard.check(11)).is_equal(StallGuard.Verdict.SKIP)
	assert_int(guard.resyncs).is_equal(1)
	assert_int(guard.skipped).is_equal(7)
	# Long after, two ticks in one frame (a game drawn at 30 frames a second) both step.
	for frame in range(12, 52):
		now[0] += 1.0 / 60.0
		guard.check(frame)
	now[0] += 1.0 / 30.0
	assert_int(guard.check(52)).is_equal(StallGuard.Verdict.STEP)
	assert_int(guard.check(52)).is_equal(StallGuard.Verdict.STEP)
	assert_int(guard.resyncs).is_equal(1)


func test_a_resync_takes_the_next_answer_whole() -> void:
	var reconciler := Reconciler.new()
	reconciler.record(1, Vector3.ZERO)
	reconciler.snap_next = true
	reconciler.answer(1, Vector3(0.5, 0.0, 0.0))
	assert_vector(reconciler.take()).is_equal(Vector3(0.5, 0.0, 0.0))
	assert_bool(reconciler.snap_next).is_false()


func test_stalls_with_no_answer_between_them_add_up_and_are_judged_a_stall_each() -> void:
	# The server walks its body on through each silence (gdstudio #1070): three stalls before the
	# answer after them may hold three walk-ons, 7 m is not lost; after one stall it is.
	var reconciler := Reconciler.new()
	for stall in 3:
		reconciler.resync()
		reconciler.record(stall + 1, Vector3.ZERO)
	reconciler.answer(3, Vector3(7.0, 0.0, 0.0))
	assert_vector(reconciler.take()).is_equal(Vector3(7.0, 0.0, 0.0))
	assert_int(reconciler.lost).is_equal(0)
	assert_int(reconciler.most_stacked).is_equal(3)
	assert_int(reconciler.stacked_stalls).is_equal(0)
	assert_float(reconciler.worst_error).is_equal_approx(7.0, 0.0001)
	assert_float(reconciler.worst_stall_error).is_equal_approx(7.0 / 3.0, 0.0001)
	reconciler.resync()
	reconciler.record(4, Vector3.ZERO)
	reconciler.answer(4, Vector3(0.0, 0.0, 7.0))
	assert_int(reconciler.lost).is_equal(1)
	assert_float(reconciler.worst_stall_error).is_equal_approx(7.0, 0.0001)
	# A teleport's snap is no stall: one walk-on at most.
	reconciler.reset()
	reconciler.snap_next = true
	reconciler.record(5, Vector3.ZERO)
	reconciler.answer(5, Vector3(0.0, 0.0, 6.5))
	assert_int(reconciler.lost).is_equal(2)


func test_a_pong_that_waited_out_a_stall_is_not_a_round_trip() -> void:
	# Its ping left before the freeze, so it measures the freeze: 5 s, and the numbering would put
	# the commands 5 s ahead of the server (gdstudio #1070).
	var now := [10.0]
	var client: NetClient = auto_free(NetClient.new())
	client.join_on_ready = false
	client.world_root = auto_free(Node.new())
	client.clock = func() -> float: return now[0]
	var ends := LoopbackLink.pair()
	client.join_with(ends[0])
	var pong := func(sent_at: float) -> void:
		ends[1].send(NetWire.pong(NetWire.read_ping(NetWire.ping(roundi(sent_at * 1000.0))), 1))
		ends[1].poll()
		client._physics_process(1.0 / 60.0)
	now[0] = 10.2
	pong.call(10.0)
	assert_int(client.rtt_ms).is_equal(200)
	now[0] = 15.1
	client.resync()
	now[0] = 15.2
	pong.call(10.1)
	assert_int(client.rtt_ms).is_equal(200)
	now[0] = 15.45
	pong.call(15.2)
	assert_int(client.rtt_ms).is_equal(250)


func test_the_track_blends_holds_and_warps() -> void:
	var track := InterpolationTrack.new()
	track.push(1.0, _entry(Vector3(0.0, 0.0, 0.0), 0.0))
	track.push(1.1, _entry(Vector3(1.0, 0.0, 0.0), 1.0))
	track.push(1.2, _entry(Vector3(9.0, 0.0, 0.0), 1.0))
	var into := PlayerEntry.new()
	var moving := track.sample(1.05, into)
	assert_vector(into.position).is_equal_approx(Vector3(0.5, 0.0, 0.0), Vector3.ONE * 0.0001)
	assert_float(into.yaw).is_equal_approx(0.5, 0.0001)
	assert_vector(moving).is_equal_approx(Vector3(10.0, 0.0, 0.0), Vector3.ONE * 0.001)
	assert_int(track.starved).is_equal(0)
	# 8 m in a tenth of a second is a warp: held at the earlier point, not slid through the map.
	moving = track.sample(1.15, into)
	assert_vector(into.position).is_equal(Vector3(1.0, 0.0, 0.0))
	assert_vector(moving).is_equal(Vector3.ZERO)
	# Past the newest: held there, and counted.
	track.sample(1.3, into)
	assert_vector(into.position).is_equal(Vector3(9.0, 0.0, 0.0))
	assert_int(track.starved).is_equal(1)
	# An old snapshot is ignored, and a second of track is kept.
	track.push(1.15, _entry(Vector3.ZERO, 0.0))
	assert_int(track.size()).is_equal(3)
	for index in 60:
		track.push(1.3 + index * 0.05, _entry(Vector3.ZERO, 0.0))
	assert_float(track.newest_time() - 1.3).is_equal_approx(59 * 0.05, 0.0001)
	assert_int(track.size()).is_less_equal(22)


static func _entry(at: Vector3, yaw: float) -> PlayerEntry:
	var entry := PlayerEntry.new()
	entry.position = at
	entry.yaw = yaw
	return entry
