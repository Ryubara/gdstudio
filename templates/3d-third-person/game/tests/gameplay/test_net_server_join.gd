# Who may join the game server and what everyone hears of it, over real sockets: two clients each
# see both players in every TICK, `joined` and `left` reach the other, the ninth is refused as full,
# a client of another version or another map is refused, each refused one is hung up on, and each
# of these is a line of the server's log.
extends GdUnitTestSuite

var _rig: NetServerRig


func before_test() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()


func test_two_clients_see_both_players_and_hear_who_came_and_went() -> void:
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	assert_int(ada.welcome.slot).is_equal(0)
	assert_int(bo.welcome.slot).is_equal(1)
	# The later one is welcomed with both players and both names.
	assert_int(bo.welcome.players.size()).is_equal(2)
	var names := bo.welcome.players.map(
		func(entry: PlayerEntry) -> String: return entry.player_name
	)
	assert_array(names).contains_exactly(["Ada", "Bo"])
	assert_int(bo.welcome.tick_rate).is_equal(NetLimits.TICK_RATE)
	assert_int(bo.welcome.world_hash).is_equal(_rig.server.world_hash)
	# Each TICK carries both players, and the first one heard that the second came.
	var both := func() -> bool:
		return (
			ada.last_tick() != null
			and bo.last_tick() != null
			and ada.last_tick().players.size() == 2
			and bo.last_tick().players.size() == 2
		)
	assert_bool(await _rig.until(both)).is_true()
	var joined := ada.heard(NetEvent.Kind.JOINED)
	assert_int(joined.size()).is_equal(1)
	assert_int(joined[0].slot).is_equal(1)
	assert_str(joined[0].player_name).is_equal("Bo")
	assert_array(bo.heard(NetEvent.Kind.JOINED)).is_empty()
	# A TICK goes out every second step.
	var ticks_before := ada.ticks.size()
	await _rig.wait(60)
	assert_int(ada.ticks.size() - ticks_before).is_between(28, 32)
	# The second one leaves: the first hears it, the slot is free and the body gone.
	bo.link.close()
	var left := await _rig.until(func() -> bool: return ada.heard(NetEvent.Kind.LEFT).size() == 1)
	assert_bool(left).is_true()
	assert_int(ada.heard(NetEvent.Kind.LEFT)[0].slot).is_equal(1)
	(
		assert_bool(await _rig.until(func() -> bool: return ada.last_tick().players.size() == 1))
		. is_true()
	)
	assert_object(_rig.server.peer_at(1)).is_null()
	assert_int(_rig.server.free_slot()).is_equal(1)
	assert_int(_rig.lines_of("joined").size()).is_equal(2)
	var left_lines := _rig.lines_of("left")
	assert_int(left_lines.size()).is_equal(1)
	assert_str(left_lines[0]["reason"]).is_equal("goodbye")
	assert_int(left_lines[0]["slot"]).is_equal(1)


func test_the_ninth_is_refused_as_full_and_hung_up_on() -> void:
	var seated: Array[HandClient] = []
	for index in NetLimits.MAX_PLAYERS:
		var client := await _rig.join("P%d" % index)
		assert_object(client).is_not_null()
		assert_int(client.welcome.slot).is_equal(index)
		seated.append(client)
	var ninth := await _rig.connect_client()
	ninth.say_hello("Late", _rig.server.world_hash)
	assert_bool(await _rig.until(func() -> bool: return ninth.closed)).is_true()
	assert_int(ninth.refusal).is_equal(NetWire.Refusal.FULL)
	assert_object(ninth.welcome).is_null()
	assert_int(_rig.server.player_count()).is_equal(NetLimits.MAX_PLAYERS)
	assert_str(_rig.lines_of("refused")[0]["reason"]).is_equal("full")
	# A seat that comes free is the lowest one, and the next hello gets it.
	seated[3].link.close()
	assert_bool(await _rig.until(func() -> bool: return _rig.server.player_count() == 7)).is_true()
	var next := await _rig.join("Next")
	assert_int(next.welcome.slot).is_equal(3)


func test_another_version_or_another_map_is_refused() -> void:
	var old := await _rig.connect_client()
	var hello := NetWire.hello("Old", _rig.server.world_hash)
	hello[NetWire.VERSION_AT] = NetWire.VERSION - 1
	old.link.send(hello)
	var newer := await _rig.connect_client()
	var newer_hello := NetWire.hello("New", _rig.server.world_hash)
	newer_hello[NetWire.VERSION_AT] = NetWire.VERSION + 1
	newer.link.send(newer_hello)
	var elsewhere := await _rig.connect_client()
	elsewhere.say_hello("Away", _rig.server.world_hash ^ 0x5A5A)
	var all_closed := func() -> bool: return old.closed and newer.closed and elsewhere.closed
	assert_bool(await _rig.until(all_closed)).is_true()
	# Version 7 (an aiming player's entry carries the aim's heading off the body, #1277) is the
	# oldest this server takes: a version 6 client is refused.
	assert_int(NetWire.VERSION).is_equal(7)
	assert_int(NetWire.MIN_VERSION).is_equal(7)
	assert_int(old.refusal).is_equal(NetWire.Refusal.VERSION)
	assert_int(newer.refusal).is_equal(NetWire.Refusal.VERSION)
	assert_int(elsewhere.refusal).is_equal(NetWire.Refusal.WORLD)
	assert_int(_rig.server.player_count()).is_equal(0)
	var reasons := _rig.lines_of("refused").map(
		func(line: Dictionary) -> String: return line["reason"]
	)
	assert_array(reasons).contains_exactly_in_any_order(["version", "version", "world"])
	# An honest client still gets in.
	assert_object(await _rig.join("Ada")).is_not_null()


func test_the_log_says_listening_and_stats_every_ten_seconds() -> void:
	var listening := _rig.lines_of("listening")
	assert_int(listening.size()).is_equal(1)
	assert_int(listening[0]["port"]).is_equal(_rig.server.listener.port())
	assert_int(listening[0]["tick_hz"]).is_equal(NetLimits.TICK_RATE)
	# The host: step times are read against it.
	assert_int(listening[0]["cores"]).is_greater(0)
	assert_str(listening[0]["cpu"]).is_not_empty()
	var ada := await _rig.join("Ada")
	var walk := CommandDriver.walking(Vector3.FORWARD)
	var stats := func() -> bool: return not _rig.lines_of("stats").is_empty()
	for _frame in int(NetServer.STATS_SECONDS * NetLimits.TICK_RATE) + 30:
		ada.send_command(walk.clone())
		_rig.pump()
		if stats.call():
			break
		await get_tree().physics_frame
	assert_bool(stats.call()).is_true()
	var line: Dictionary = _rig.lines_of("stats")[0]
	for key in [
		"players",
		"tick",
		"out_bytes_per_s",
		"step_ms_p50",
		"step_ms_p95",
		"steps_over_budget",
		"peers_stalled",
		"steps_held",
		"steps_repeated",
	]:
		assert_bool(line.has(key)).override_failure_message("no %s" % key).is_true()
	assert_int(line["players"]).is_equal(1)
	assert_int(line["out_bytes_per_s"]).is_greater(0)
	assert_float(line["step_ms_p95"]).is_greater_equal(line["step_ms_p50"])
	# Every line is one JSON object.
	assert_object(JSON.parse_string(JSON.stringify(line))).is_not_null()


func test_each_slot_starts_at_its_spawn_point_wrapping_past_the_last() -> void:
	# Three points and four players: the fourth starts at the first point again.
	for index in 4:
		var client := await _rig.join("P%d" % index)
		assert_int(client.welcome.slot).is_equal(index)
	for slot in 4:
		var spot := NetServerRig.SPAWNS[slot % NetServerRig.SPAWNS.size()]
		var body := _rig.server.body_at(slot)
		var flat := Vector2(body.global_position.x - spot.x, body.global_position.z - spot.z)
		assert_float(flat.length()).override_failure_message("slot %d" % slot).is_less(0.01)
		assert_vector(_rig.server.spawn_transform(slot).origin).is_equal(spot)
		# The point faces -Z, and so does the body.
		assert_float(angle_difference(body.facing, PI)).is_equal_approx(0.0, 0.001)
	# A body that falls out of the map starts again at its slot's point.
	var body := _rig.server.body_at(1)
	body.global_position = Vector3(20.0, -40.0, 20.0)
	await _rig.wait(3)
	assert_float(body.global_position.distance_to(NetServerRig.SPAWNS[1])).is_less(0.05)
