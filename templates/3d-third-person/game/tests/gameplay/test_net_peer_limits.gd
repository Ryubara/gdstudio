# What one connection may send: an honest client is never struck, a flood is cut off, a stall
# is forgiven, and every malformed packet is counted by reason. Time is stepped by hand (one
# clock: test-speed.md#one-clock-per-test).
extends GdUnitTestSuite

const TICK := 1.0 / NetLimits.TICK_RATE


func _command(seq: int) -> PackedByteArray:
	var command := PlayerCommand.new()
	command.seq = seq
	return CommandCodec.encode(command)


func _hello(limits: PeerLimits) -> void:
	assert_int(limits.judge(NetWire.hello("Rook", 1), 0.0)).is_equal(PeerLimits.Verdict.ACCEPT)


func test_an_honest_client_at_60_a_second_never_gets_a_strike() -> void:
	var limits := PeerLimits.new()
	_hello(limits)
	var seq := 0
	for tick in 60 * 60:
		seq += 1
		var now := tick * TICK
		assert_int(limits.judge(_command(seq), now)).is_equal(PeerLimits.Verdict.ACCEPT)
		if tick % (NetLimits.TICK_RATE / NetLimits.PING_RATE) == 0:
			assert_int(limits.judge(NetWire.ping(tick), now)).is_equal(PeerLimits.Verdict.ACCEPT)
	assert_float(limits.strikes).is_equal(0.0)
	assert_int(limits.drops.total()).is_equal(0)


func test_three_seconds_of_stall_arrive_together_and_are_forgiven() -> void:
	var limits := PeerLimits.new()
	_hello(limits)
	var seq := 0
	var now := 0.0
	for tick in 120:
		seq += 1
		now = tick * TICK
		limits.judge(_command(seq), now)
	# The page froze for 3 s; its 180 commands and 6 pings leave in one go.
	now += 3.0
	for index in 180:
		seq += 1
		assert_int(limits.judge(_command(seq), now)).is_equal(PeerLimits.Verdict.ACCEPT)
	for index in 6:
		assert_int(limits.judge(NetWire.ping(index), now)).is_equal(PeerLimits.Verdict.ACCEPT)
	# Then it goes on at 60 a second, never struck.
	for tick in 600:
		seq += 1
		now += TICK
		assert_int(limits.judge(_command(seq), now)).is_equal(PeerLimits.Verdict.ACCEPT)
	assert_float(limits.strikes).is_equal(0.0)


func test_a_flood_of_commands_is_cut_off_after_about_450_packets() -> void:
	var limits := PeerLimits.new()
	_hello(limits)
	var sent := 0
	var verdict := PeerLimits.Verdict.ACCEPT
	while verdict != PeerLimits.Verdict.KICK and sent < 5000:
		sent += 1
		verdict = limits.judge(_command(sent), 1.0 + sent * 0.0001)
	assert_int(verdict).is_equal(PeerLimits.Verdict.KICK)
	assert_int(sent).is_between(400, 500)
	assert_int(limits.drops.of(NetDrops.OVER_RATE)).is_greater(0)
	print("net limits: a flood at 10000/s was cut off after %d packets" % sent)
	# Once hung up on, every packet is a kick.
	assert_int(limits.judge(_command(sent + 1), 100.0)).is_equal(PeerLimits.Verdict.KICK)


func test_a_flood_of_garbage_is_cut_off_sooner() -> void:
	var limits := PeerLimits.new()
	var sent := 0
	var verdict := PeerLimits.Verdict.DROP
	while verdict != PeerLimits.Verdict.KICK and sent < 1000:
		sent += 1
		verdict = limits.judge(PackedByteArray([99, 1, 2]), 0.0)
	assert_int(sent).is_equal(int(PeerLimits.KICK_AT / PeerLimits.STRIKE_BAD))
	assert_int(limits.drops.of(NetDrops.UNKNOWN_TYPE)).is_equal(sent)


func test_each_malformed_packet_is_dropped_with_its_reason() -> void:
	var shot_size := PackedByteArray()
	shot_size.resize(NetWire.COMMAND_SIZE + 5)
	shot_size[0] = NetWire.Type.COMMAND
	var long_ping := NetWire.ping(1)
	long_ping.append(0)
	var too_long := PackedByteArray()
	too_long.resize(PeerLimits.MAX_PACKET + 1)
	too_long[0] = NetWire.Type.COMMAND
	var cases := {
		NetDrops.EMPTY: PackedByteArray(),
		NetDrops.TOO_LONG: too_long,
		NetDrops.UNKNOWN_TYPE: PackedByteArray([NetWire.Type.TICK, 0, 0, 0, 0]),
		NetDrops.WRONG_SIZE: shot_size,
	}
	for reason: StringName in cases:
		var limits := PeerLimits.new()
		assert_int(limits.judge(cases[reason], 0.0)).override_failure_message(reason).is_equal(
			PeerLimits.Verdict.DROP
		)
		assert_int(limits.drops.of(reason)).override_failure_message(reason).is_equal(1)
	var limits := PeerLimits.new()
	assert_int(limits.judge(long_ping, 0.0)).is_equal(PeerLimits.Verdict.DROP)
	assert_str(limits.drops.last).is_equal(NetDrops.WRONG_SIZE)


func test_a_hello_twice_is_dropped() -> void:
	var limits := PeerLimits.new()
	_hello(limits)
	assert_int(limits.judge(NetWire.hello("Rook", 1), 5.0)).is_equal(PeerLimits.Verdict.DROP)
	assert_int(limits.drops.of(NetDrops.HELLO_TWICE)).is_equal(1)


func test_an_old_clients_hello_passes_so_the_server_can_refuse_its_version() -> void:
	var limits := PeerLimits.new()
	var old := PackedByteArray([NetWire.Type.HELLO, 0, 1, 0x41])
	assert_int(limits.judge(old, 0.0)).is_equal(PeerLimits.Verdict.ACCEPT)
	var drops := NetDrops.new()
	assert_object(NetWire.read_hello(old, drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.BAD_VERSION)
	# But a one-byte hello says no version and is malformed.
	var bare := PeerLimits.new()
	assert_int(bare.judge(PackedByteArray([NetWire.Type.HELLO]), 0.0)).is_equal(
		PeerLimits.Verdict.DROP
	)


func test_a_fault_the_server_finds_costs_a_bad_strike() -> void:
	var limits := PeerLimits.new()
	assert_int(limits.fault(0.0, NetDrops.NOT_FINITE)).is_equal(PeerLimits.Verdict.DROP)
	assert_float(limits.strikes).is_equal(PeerLimits.STRIKE_BAD)
	assert_int(limits.drops.of(NetDrops.NOT_FINITE)).is_equal(1)
	# Strikes wear off with time.
	limits.judge(_command(1), 10.0)
	assert_float(limits.strikes).is_equal(0.0)


func test_a_token_bucket_refills_at_its_rate_up_to_its_burst() -> void:
	var bucket := TokenBucket.new(10.0, 3.0)
	for index in 3:
		assert_bool(bucket.take(0.0)).is_true()
	assert_bool(bucket.take(0.0)).is_false()
	assert_bool(bucket.take(0.05)).is_false()
	assert_bool(bucket.take(0.1)).is_true()
	assert_bool(bucket.take(100.0)).is_true()
	assert_float(bucket.tokens).is_equal(2.0)
	# A clock that goes back refills nothing.
	assert_bool(bucket.take(50.0)).is_true()
	assert_bool(bucket.take(50.0)).is_true()
	assert_bool(bucket.take(50.0)).is_false()
