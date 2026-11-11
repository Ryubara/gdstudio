# Every copy of a NetLimits number is pinned here: a change in one place that leaves an old number
# in another fails (docs: gamedev/netcode.md#limits).
extends GdUnitTestSuite


func test_the_server_tick_is_the_physics_tick() -> void:
	var ticks: int = ProjectSettings.get_setting("physics/common/physics_ticks_per_second")
	assert_int(ticks).is_equal(NetLimits.TICK_RATE)
	assert_int(NetLimits.TICK_RATE % NetLimits.SNAPSHOT_RATE).is_equal(0)
	assert_int(NetLimits.TICK_RATE % NetLimits.PING_RATE).is_equal(0)


func test_each_number_fits_the_bytes_that_carry_it() -> void:
	# A slot is a byte, and a WELCOME or TICK checks unique slots in a bit mask of an int.
	assert_int(NetLimits.MAX_PLAYERS).is_between(1, 63)
	assert_int(NetLimits.NAME_BYTES).is_between(1, 255)
	assert_int(NetLimits.MAX_EVENTS).is_between(1, 255)
	assert_int(NetLimits.MAX_ENTITIES).is_between(0, 0xFFFF)
	assert_int(NetLimits.MAX_ENTITY_STATE).is_between(0, 255)
	assert_int(NetLimits.TICK_RATE).is_between(1, 255)
	# The position range is what a signed 16-bit count of centimetres holds.
	assert_float(NetLimits.POSITION_RANGE).is_equal(
		CommandCodec.POINT_MAX / NetLimits.POSITION_STEPS_PER_METRE
	)
	# A Vector3 holds float32, so the far edge reads 327.670013.
	var edge := CommandCodec.snap_point(Vector3.ONE * 1000.0).x
	assert_float(edge).is_equal_approx(NetLimits.POSITION_RANGE, 0.0001)


func test_the_sizes_follow_the_limits() -> void:
	assert_int(NetWire.MAX_HELLO).is_equal(NetWire.HELLO_HEADER + NetLimits.NAME_BYTES)
	assert_int(SnapshotCodec.MAX_EVENT_SIZE).is_equal(
		maxi(3 + NetLimits.NAME_BYTES, 8 + NetLimits.MAX_ENTITY_STATE)
	)
	assert_int(PeerLimits.MAX_PACKET).is_equal(maxi(NetWire.MAX_HELLO, NetWire.COMMAND_SHOT_SIZE))
	assert_int(NetWire.MAX_CLIENT_PACKET).is_equal(PeerLimits.MAX_PACKET)


func test_the_command_budget_holds_the_tick_rate_and_a_stall() -> void:
	var rate: Vector2 = PeerLimits.RATES[NetWire.Type.COMMAND]
	assert_float(rate.x).is_greater(NetLimits.TICK_RATE)
	assert_float(rate.x).is_equal(90.0)
	assert_float(rate.y).is_equal(240.0)
	assert_float(rate.y).is_greater_equal(NetLimits.TICK_RATE * 3.0)
	var ping: Vector2 = PeerLimits.RATES[NetWire.Type.PING]
	assert_float(ping.x).is_greater(NetLimits.PING_RATE)


func test_the_socket_buffer_holds_ten_seconds_of_the_longest_ticks() -> void:
	# The longest TICK but its AI block, ten seconds; and five of a full AI snapshot of the
	# desktop population every TICK (a 5 s frozen tab near every character; gdstudio #970).
	var without_ai := SnapshotCodec.MAX_TICK - AiSnapshot.MAX_BLOCK + AiSnapshot.NONE_SIZE
	var director: AiDirector = auto_free(AiDirector.new())
	var full_ai := AiSnapshot.FULL_HEADER + director.desktop_cap * AiSnapshot.ROW_SIZE
	var needed := NetLimits.SNAPSHOT_RATE * (10 * without_ai + 5 * full_ai)
	assert_int(NetLimits.BUFFER_SIZE).is_greater_equal(needed)
	assert_int(NetLimits.BUFFER_SIZE).is_greater_equal(SnapshotCodec.MAX_WELCOME)


func test_the_transport_reads_the_one_socket_buffer_size() -> void:
	# 1 MB since the AI rides the TICK (gdstudio #970); 256 KB was measured in the browser before
	# it: a 5 s frozen tab at 35 KB/s lost nothing (64 KB did).
	assert_int(NetLimits.BUFFER_SIZE).is_equal(1024 * 1024)
	assert_int(WebSocketLink.new().inbound_buffer).is_equal(NetLimits.BUFFER_SIZE)
	assert_int(WsListener.new().outbound_buffer).is_equal(NetLimits.BUFFER_SIZE)
	# No second copy of the size: the transport files hold no buffer-size constant of their own
	# beyond the listener's 64 KB cap on what a peer may send.
	for file in ["web_socket_link.gd", "ws_listener.gd"]:
		var text := FileAccess.get_file_as_string("res://gameplay/net/" + file)
		assert_bool(text.contains("OUTBOUND_BUFFER")).is_false()
		assert_bool(text.contains("const INBOUND_BUFFER := 1 << 20")).is_false()
		assert_bool(text.contains("1 << 18")).is_false()


func test_no_net_file_writes_a_limit_as_a_bare_number() -> void:
	# The players, the name length and the tick rate are named, never typed again as numbers.
	var dir := "res://gameplay/net/"
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd") or file == "net_limits.gd":
			continue
		var text := FileAccess.get_file_as_string(dir + file)
		for pattern in ["MAX_PLAYERS := ", "NAME_BYTES := ", "TICK_RATE := ", "327.67"]:
			(
				assert_bool(text.contains(pattern))
				. override_failure_message("%s repeats %s" % [file, pattern])
				. is_false()
			)
