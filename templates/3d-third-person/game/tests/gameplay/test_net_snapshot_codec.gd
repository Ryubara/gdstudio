# TICK and WELCOME: player entries, every event, the size budget, and counts that promise more
# than the packet holds (dropped with a reason, nothing allocated by the claimed count).
extends GdUnitTestSuite


func _player(slot: int) -> PlayerEntry:
	var player := PlayerEntry.new()
	player.slot = slot
	player.position = Vector3(10.0 * slot - 31.27, 0.5 * slot, -300.0 + slot)
	player.yaw = -3.0 + slot * 0.7
	player.state = 3 + slot
	player.crouch = slot % 2 == 0
	player.aim = slot % 3 == 0
	player.sprint = slot % 2 == 1
	player.air = slot == 4
	player.rising = slot == 4
	player.dead = slot == 7
	player.pitch = -0.6 + slot * 0.15
	player.aim_yaw = (-1.2 + slot * 0.4) if player.aim else 0.0
	player.player_name = "P%d" % slot
	return player


func _players(count: int) -> Array[PlayerEntry]:
	var players: Array[PlayerEntry] = []
	for slot in count:
		players.append(_player(slot))
	return players


func _all_events() -> Array[NetEvent]:
	var events: Array[NetEvent] = [
		NetEvent.joined(3, "Rook"),
		NetEvent.left(5),
		NetEvent.shot(2, 9_000, Vector3(1.0, 1.6, -2.25), Vector3(0.0, 0.1, -1.0).normalized()),
		NetEvent.hit(Vector3(4.0, 0.25, -8.5), Vector3.UP, 2, 17),
		NetEvent.died(1, Vector3(3.0, -9.5, 0.0), 1),
		NetEvent.revived(1, Vector3(0.0, 0.0, 5.0)),
		NetEvent.entity(40, 123_456, PackedByteArray([1, 2, 3])),
		NetEvent.pickup(41, 6),
		NetEvent.rejected(77, 3),
		NetEvent.ai(
			300,
			NetEvent.AiCode.FIRED,
			Vector3(2.0, 1.4, -6.0),
			Vector3(0.0, -0.1, 1.0).normalized()
		),
	]
	return events


func _one_player(player: PlayerEntry) -> Array[PlayerEntry]:
	var players: Array[PlayerEntry] = [player]
	return players


func _one_event(event: NetEvent) -> Array[NetEvent]:
	var events: Array[NetEvent] = [event]
	return events


func _assert_player(actual: PlayerEntry, expected: PlayerEntry) -> void:
	var snap := SnapshotCodec.snap_player(expected)
	assert_int(actual.slot).is_equal(expected.slot)
	assert_vector(actual.position).is_equal(snap.position)
	assert_vector(actual.position).is_equal_approx(expected.position, Vector3.ONE * 0.005)
	assert_float(actual.yaw).is_equal(snap.yaw)
	assert_float(actual.pitch).is_equal(snap.pitch)
	assert_float(actual.pitch).is_equal_approx(expected.pitch, 0.0125)
	assert_float(actual.aim_yaw).is_equal(snap.aim_yaw)
	assert_float(actual.aim_yaw).is_equal_approx(expected.aim_yaw, 0.0125)
	assert_int(actual.state).is_equal(expected.state)
	for field in ["crouch", "aim", "sprint", "air", "rising", "dead"]:
		assert_bool(actual.get(field)).override_failure_message(field).is_equal(expected.get(field))


func _assert_event(actual: NetEvent, expected: NetEvent) -> void:
	var label := str(expected.kind)
	assert_int(actual.kind).override_failure_message(label).is_equal(expected.kind)
	assert_int(actual.slot).override_failure_message(label).is_equal(expected.slot)
	assert_int(actual.seq).override_failure_message(label).is_equal(expected.seq)
	assert_int(actual.code).override_failure_message(label).is_equal(expected.code)
	assert_int(actual.id).override_failure_message(label).is_equal(expected.id)
	assert_int(actual.tick).override_failure_message(label).is_equal(expected.tick)
	assert_str(actual.player_name).override_failure_message(label).is_equal(expected.player_name)
	assert_array(actual.state).override_failure_message(label).is_equal(expected.state)
	assert_vector(actual.point).is_equal_approx(expected.point, Vector3.ONE * 0.005)
	if expected.kind in [NetEvent.Kind.SHOT, NetEvent.Kind.HIT]:
		assert_vector(actual.direction).is_equal_approx(expected.direction, Vector3.ONE * 0.001)


func test_a_player_entry_is_12_bytes() -> void:
	var out := StreamPeerBuffer.new()
	assert_str(SnapshotCodec.write_player(out, _player(4))).is_equal(&"")
	assert_int(out.data_array.size()).is_equal(12)
	assert_int(SnapshotCodec.PLAYER_SIZE).is_less_equal(12)


func test_an_aiming_player_s_entry_carries_one_byte_of_aim_yaw() -> void:
	# The aim's heading off the body (kit #1277): one signed byte, only while aiming.
	var player := _player(4)
	player.aim_yaw = 0.9
	var out := StreamPeerBuffer.new()
	SnapshotCodec.write_player(out, player)
	assert_int(out.data_array.size()).is_equal(12)
	assert_float(SnapshotCodec.snap_player(player).aim_yaw).is_equal(0.0)
	player.aim = true
	out = StreamPeerBuffer.new()
	SnapshotCodec.write_player(out, player)
	assert_int(out.data_array.size()).is_equal(13)
	assert_int(SnapshotCodec.player_size(player)).is_equal(13)
	assert_float(SnapshotCodec.snap_player(player).aim_yaw).is_equal_approx(0.9, 0.0125)
	# A half turn either way, in steps of about 1.4 degrees.
	for turn: float in [PI, -PI, 3.0, -3.0, 0.5 * PI, -0.01]:
		player.aim_yaw = turn
		var back := SnapshotCodec.snap_player(player).aim_yaw
		assert_float(absf(angle_difference(back, turn))).is_less_equal(SnapshotCodec.AIM_YAW_STEP)
	assert_float(rad_to_deg(SnapshotCodec.AIM_YAW_STEP)).is_less(1.5)
	player.aim_yaw = INF
	assert_str(SnapshotCodec.write_player(StreamPeerBuffer.new(), player)).is_equal(
		NetDrops.NOT_FINITE
	)


func test_an_aiming_entry_cut_before_its_aim_byte_is_dropped() -> void:
	var packet := SnapshotCodec.tick(5, 4, [] as Array[NetEvent], _players(1))
	# The one player aims: its 13th byte is the last before the tail; cut it and the tail.
	var cut := packet.slice(0, NetWire.TICK_HEADER + SnapshotCodec.PLAYER_SIZE)
	var drops := NetDrops.new()
	assert_object(SnapshotCodec.read_tick(cut, drops)).is_null()
	assert_int(drops.total()).is_equal(1)


func test_a_tick_with_8_players_is_at_most_109_bytes_and_one_more_for_each_aim() -> void:
	var players := _players(8)
	for player in players:
		player.aim = false
	var packet := SnapshotCodec.tick(10, 9, [] as Array[NetEvent], players)
	# 108 and the AI block's mode byte (gdstudio #970).
	assert_int(packet.size()).is_less_equal(109)
	assert_int(packet.size()).is_equal(
		NetWire.TICK_HEADER + 8 * SnapshotCodec.PLAYER_SIZE + NetWire.TICK_TAIL
	)
	for player in players:
		player.aim = true
	packet = SnapshotCodec.tick(10, 9, [] as Array[NetEvent], players)
	assert_int(packet.size()).is_equal(117)


func test_tick_round_trip_with_every_player_and_every_event() -> void:
	var players := _players(8)
	var events := _all_events()
	var packet := SnapshotCodec.tick(4_000_000_000, 123_457, events, players)
	assert_array(packet).is_not_empty()
	var tick := SnapshotCodec.read_tick(packet)
	assert_object(tick).is_not_null()
	assert_int(tick.server_tick).is_equal(4_000_000_000)
	assert_int(tick.ack).is_equal(123_457)
	assert_int(tick.events.size()).is_equal(events.size())
	for index in events.size():
		_assert_event(tick.events[index], events[index])
	assert_int(tick.players.size()).is_equal(8)
	for index in 8:
		_assert_player(tick.players[index], players[index])


func test_snap_player_and_snap_event_are_idempotent() -> void:
	for slot in 8:
		var once := SnapshotCodec.snap_player(_player(slot))
		var twice := SnapshotCodec.snap_player(once)
		_assert_player(twice, once)
		assert_vector(twice.position).is_equal(once.position)
	for event in _all_events():
		var once := SnapshotCodec.snap_event(event)
		var twice := SnapshotCodec.snap_event(once)
		_assert_event(twice, once)
		assert_vector(twice.point).is_equal(once.point)
		assert_vector(twice.direction).is_equal(once.direction)


func test_each_event_size_matches_its_layout() -> void:
	var expected := {
		NetEvent.Kind.JOINED: 3 + 4,
		NetEvent.Kind.LEFT: 2,
		NetEvent.Kind.SHOT: 15,
		NetEvent.Kind.HIT: 15,
		NetEvent.Kind.DIED: 9,
		NetEvent.Kind.REVIVED: 8,
		NetEvent.Kind.ENTITY: 8 + 3,
		NetEvent.Kind.PICKUP: 4,
		NetEvent.Kind.REJECTED: 6,
		NetEvent.Kind.AI: 14,
	}
	var lines := PackedStringArray()
	for event in _all_events():
		var size := SnapshotCodec.event_size(event)
		assert_int(size).override_failure_message(str(event.kind)).is_equal(expected[event.kind])
		assert_int(size).is_between(SnapshotCodec.MIN_EVENT_SIZE, SnapshotCodec.MAX_EVENT_SIZE)
		lines.append("%s=%d" % [NetEvent.Kind.find_key(event.kind), size])
	var longest := NetEvent.joined(0, "x".repeat(16))
	assert_int(SnapshotCodec.event_size(longest)).is_less_equal(SnapshotCodec.MAX_EVENT_SIZE)
	var longest_state := PackedByteArray()
	longest_state.resize(NetLimits.MAX_ENTITY_STATE)
	var longest_entity := NetEvent.entity(1, 1, longest_state)
	assert_int(SnapshotCodec.event_size(longest_entity)).is_equal(SnapshotCodec.MAX_EVENT_SIZE)
	print("net sizes: events ", " ".join(lines))


func test_the_message_sizes_against_the_research_estimates() -> void:
	var command := PlayerCommand.new()
	var shot := PlayerCommand.new()
	shot.has_shot = true
	var no_entities: Array[EntityEntry] = []
	var sizes := {
		"hello_8_char_name": NetWire.hello("Player01", 1).size(),
		"welcome_1_player_0_entities":
		SnapshotCodec.welcome(0, 1, 1, no_entities, _players(1)).size(),
		"refused": NetWire.refused(NetWire.Refusal.FULL).size(),
		"command": CommandCodec.encode(command).size(),
		"command_with_shot": CommandCodec.encode(shot).size(),
		"tick_8_players": SnapshotCodec.tick(1, 1, [] as Array[NetEvent], _players(8)).size(),
		"tick_16_players_equivalent": NetWire.TICK_HEADER + 16 * SnapshotCodec.PLAYER_SIZE,
		"ping": NetWire.ping(1).size(),
		"pong": NetWire.pong(NetWire.read_ping(NetWire.ping(1)), 1).size(),
		"max_tick": SnapshotCodec.MAX_TICK,
		"max_welcome": SnapshotCodec.MAX_WELCOME,
	}
	var lines := PackedStringArray()
	for key: String in sizes:
		lines.append("%s=%d" % [key, sizes[key]])
	print("net sizes: ", " ".join(lines))
	assert_int(sizes["command"]).is_equal(15)
	assert_int(sizes["command_with_shot"]).is_equal(27)
	# Three of the eight aim (slots 0, 3 and 6): a byte each (kit #1277).
	assert_int(sizes["tick_8_players"]).is_equal(112)
	assert_int(sizes["refused"]).is_equal(3)
	assert_int(sizes["ping"]).is_equal(7)
	assert_int(sizes["pong"]).is_equal(11)


func test_the_longest_welcome_fits_its_limit_and_round_trips() -> void:
	var entities: Array[EntityEntry] = []
	for id in NetLimits.MAX_ENTITIES:
		var state := PackedByteArray()
		state.resize(NetLimits.MAX_ENTITY_STATE)
		state.fill(id % 256)
		entities.append(EntityEntry.make(id * 3, id % 7, state))
	var players := _players(NetLimits.MAX_PLAYERS)
	for player in players:
		player.player_name = "n".repeat(NetLimits.NAME_BYTES)
		# The longest: every player aims, so every entry carries its aim byte.
		player.aim = true
	var packet := SnapshotCodec.welcome(7, 555, 0xABCDEF01, entities, players)
	assert_int(packet.size()).is_equal(SnapshotCodec.MAX_WELCOME)
	var welcome := SnapshotCodec.read_welcome(packet)
	assert_object(welcome).is_not_null()
	assert_int(welcome.slot).is_equal(7)
	assert_int(welcome.tick_rate).is_equal(NetLimits.TICK_RATE)
	assert_int(welcome.server_tick).is_equal(555)
	assert_int(welcome.world_hash).is_equal(0xABCDEF01)
	assert_int(welcome.entities.size()).is_equal(NetLimits.MAX_ENTITIES)
	assert_int(welcome.entities[5].id).is_equal(15)
	assert_int(welcome.entities[5].kind).is_equal(5)
	assert_array(welcome.entities[5].state).is_equal(entities[5].state)
	assert_int(welcome.players.size()).is_equal(NetLimits.MAX_PLAYERS)
	for index in players.size():
		_assert_player(welcome.players[index], players[index])
		assert_str(welcome.players[index].player_name).is_equal(players[index].player_name)


func test_an_empty_welcome_round_trips() -> void:
	var packet := SnapshotCodec.welcome(0, 0, 0, [] as Array[EntityEntry], [] as Array[PlayerEntry])
	var welcome := SnapshotCodec.read_welcome(packet)
	assert_object(welcome).is_not_null()
	assert_int(welcome.entities.size()).is_equal(0)
	assert_int(welcome.players.size()).is_equal(0)


func test_what_cannot_travel_is_not_sent() -> void:
	var drops := NetDrops.new()
	var nan_player := _player(1)
	nan_player.position.x = NAN
	(
		assert_array(
			SnapshotCodec.tick(1, 1, [] as Array[NetEvent], _one_player(nan_player), drops)
		)
		. is_empty()
	)
	assert_str(drops.last).is_equal(NetDrops.NOT_FINITE)
	var inf_event := NetEvent.shot(0, 1, Vector3(INF, 0, 0), Vector3.FORWARD)
	(
		assert_array(
			SnapshotCodec.tick(1, 1, _one_event(inf_event), [] as Array[PlayerEntry], drops)
		)
		. is_empty()
	)
	assert_str(drops.last).is_equal(NetDrops.NOT_FINITE)
	assert_array(SnapshotCodec.tick(1, 1, [] as Array[NetEvent], _players(9), drops)).is_empty()
	assert_str(drops.last).is_equal(NetDrops.TOO_MANY)
	var far_slot := _player(8)
	(
		assert_array(SnapshotCodec.tick(1, 1, [] as Array[NetEvent], _one_player(far_slot), drops))
		. is_empty()
	)
	assert_str(drops.last).is_equal(NetDrops.BAD_VALUE)
	var too_big := PackedByteArray()
	too_big.resize(NetLimits.MAX_ENTITY_STATE + 1)
	var big_state := NetEvent.entity(1, 1, too_big)
	(
		assert_array(
			SnapshotCodec.tick(1, 1, _one_event(big_state), [] as Array[PlayerEntry], drops)
		)
		. is_empty()
	)
	assert_str(drops.last).is_equal(NetDrops.TOO_LONG)


func test_hostile_ticks_are_dropped_with_a_reason() -> void:
	var good := SnapshotCodec.tick(5, 4, _all_events(), _players(3))
	var lying_players := SnapshotCodec.tick(5, 4, [] as Array[NetEvent], _players(1))
	lying_players[NetWire.TICK_HEADER - 1] = 200
	var promise_players := SnapshotCodec.tick(5, 4, [] as Array[NetEvent], _players(1))
	promise_players[NetWire.TICK_HEADER - 1] = 8
	var promise_events := SnapshotCodec.tick(5, 4, [] as Array[NetEvent], _players(1))
	promise_events[9] = 30
	var many_events := promise_events.duplicate()
	many_events[9] = 255
	var unknown_kind := SnapshotCodec.tick(
		5, 4, _one_event(NetEvent.left(1)), [] as Array[PlayerEntry]
	)
	unknown_kind[10] = 99
	var event_slot := SnapshotCodec.tick(
		5, 4, _one_event(NetEvent.left(1)), [] as Array[PlayerEntry]
	)
	event_slot[11] = 8
	var player_slot := SnapshotCodec.tick(5, 4, [] as Array[NetEvent], _players(1))
	player_slot[NetWire.TICK_HEADER] = 9
	var twice := SnapshotCodec.tick(5, 4, [] as Array[NetEvent], _players(2))
	twice[NetWire.TICK_HEADER + SnapshotCodec.player_size(_player(0))] = 0
	var long_name := SnapshotCodec.tick(
		5, 4, _one_event(NetEvent.joined(1, "a")), [] as Array[PlayerEntry]
	)
	long_name[12] = 17
	var trailing := good.duplicate()
	trailing.append(0)
	var too_long := PackedByteArray()
	too_long.resize(SnapshotCodec.MAX_TICK + 1)
	too_long[0] = NetWire.Type.TICK
	var cases := {
		NetDrops.EMPTY: PackedByteArray(),
		NetDrops.UNKNOWN_TYPE: NetWire.ping(1),
		NetDrops.TOO_SHORT: good.slice(0, 10),
		NetDrops.TOO_LONG: trailing,
		NetDrops.TOO_MANY: lying_players,
		NetDrops.COUNT_PAST_END: promise_players,
		NetDrops.BAD_VALUE: unknown_kind,
		NetDrops.NAME_TOO_LONG: long_name,
	}
	for reason: StringName in cases:
		var drops := NetDrops.new()
		(
			assert_object(SnapshotCodec.read_tick(cases[reason], drops))
			. override_failure_message(reason)
			. is_null()
		)
		assert_int(drops.of(reason)).override_failure_message(reason).is_equal(1)
		assert_int(drops.total()).override_failure_message(reason).is_equal(1)
	var expected := {
		"events past the end": [promise_events, NetDrops.COUNT_PAST_END],
		"more events than a tick may hold": [many_events, NetDrops.TOO_MANY],
		"event slot out of range": [event_slot, NetDrops.BAD_VALUE],
		"player slot out of range": [player_slot, NetDrops.BAD_VALUE],
		"one slot twice": [twice, NetDrops.BAD_VALUE],
		"longer than any tick": [too_long, NetDrops.TOO_LONG],
	}
	for label: String in expected:
		var drops := NetDrops.new()
		(
			assert_object(SnapshotCodec.read_tick(expected[label][0], drops))
			. override_failure_message(label)
			. is_null()
		)
		assert_str(drops.last).override_failure_message(label).is_equal(expected[label][1])


func test_every_cut_of_a_tick_or_welcome_is_a_counted_drop() -> void:
	var tick := SnapshotCodec.tick(5, 4, _all_events(), _players(8))
	for size in tick.size():
		var drops := NetDrops.new()
		assert_object(SnapshotCodec.read_tick(tick.slice(0, size), drops)).is_null()
		assert_int(drops.total()).override_failure_message("tick cut at %d" % size).is_equal(1)
	var entities: Array[EntityEntry] = [EntityEntry.make(1, 2, PackedByteArray([3, 4]))]
	var welcome := SnapshotCodec.welcome(1, 2, 3, entities, _players(3))
	for size in welcome.size():
		var drops := NetDrops.new()
		assert_object(SnapshotCodec.read_welcome(welcome.slice(0, size), drops)).is_null()
		assert_int(drops.total()).override_failure_message("welcome cut at %d" % size).is_equal(1)


func test_random_bytes_never_throw_and_decode_only_finite_numbers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2902
	var decoded := 0
	var valid_tick := SnapshotCodec.tick(5, 4, _all_events(), _players(8))
	var entities: Array[EntityEntry] = [EntityEntry.make(1, 2, PackedByteArray([3, 4]))]
	var valid_welcome := SnapshotCodec.welcome(1, 2, 3, entities, _players(4))
	for index in 400:
		var packet := PackedByteArray()
		if index % 2 == 0:
			# Random bytes behind a type byte.
			packet.resize(rng.randi_range(1, 140))
			for at in packet.size():
				packet[at] = rng.randi_range(0, 255)
			packet[0] = NetWire.Type.TICK if rng.randf() < 0.5 else NetWire.Type.WELCOME
			if packet[0] == NetWire.Type.WELCOME and packet.size() > 1:
				packet[1] = NetWire.VERSION
		else:
			# A real packet with one byte changed (past the type and the version).
			packet = (valid_tick if index % 4 == 1 else valid_welcome).duplicate()
			packet[rng.randi_range(2, packet.size() - 1)] = rng.randi_range(0, 255)
		var drops := NetDrops.new()
		var tick := SnapshotCodec.read_tick(packet, drops)
		var welcome := SnapshotCodec.read_welcome(packet, drops)
		var players: Array[PlayerEntry] = []
		if tick != null:
			players = tick.players
			decoded += 1
		if welcome != null:
			players = welcome.players
			decoded += 1
		for player in players:
			assert_bool(player.all_finite()).is_true()
		(
			assert_int(drops.total() + (1 if tick != null else 0) + (1 if welcome != null else 0))
			. is_equal(2)
		)
	print("net fuzz: %d of 800 random reads decoded" % decoded)


func test_a_huge_claimed_count_costs_nothing() -> void:
	# A welcome that says 65535 entities in 20 bytes is refused before any row is read.
	var packet := SnapshotCodec.welcome(0, 0, 0, [] as Array[EntityEntry], [] as Array[PlayerEntry])
	packet.encode_u16(NetWire.WELCOME_HEADER, 0xFFFF)
	var drops := NetDrops.new()
	assert_object(SnapshotCodec.read_welcome(packet, drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.TOO_MANY)
	packet.encode_u16(NetWire.WELCOME_HEADER, NetLimits.MAX_ENTITIES)
	assert_object(SnapshotCodec.read_welcome(packet, drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.COUNT_PAST_END)
