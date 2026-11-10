# HELLO, REFUSED, PING and PONG: round trips, the version read before anything else (a packet of
# an older layout answers bad_version), names, and the world hash.
extends GdUnitTestSuite

## The HELLO of the research's draft layout (version 0: type, version, name length, name), kept so
## a server of this build must answer it `bad_version`, not misread it.
const OLD_HELLO := [1, 0, 3, 0x41, 0x6E, 0x6E]


func test_hello_round_trip() -> void:
	var packet := NetWire.hello("Rook", 0xDEADBEEF)
	assert_int(packet.size()).is_equal(NetWire.HELLO_HEADER + 4)
	var hello := NetWire.read_hello(packet)
	assert_object(hello).is_not_null()
	assert_int(hello.version).is_equal(NetWire.VERSION)
	assert_int(hello.world_hash).is_equal(0xDEADBEEF)
	assert_str(hello.player_name).is_equal("Rook")


func test_an_empty_name_and_a_utf8_name_travel() -> void:
	assert_str(NetWire.read_hello(NetWire.hello("", 1)).player_name).is_equal("")
	assert_str(NetWire.read_hello(NetWire.hello("Zoë 森", 1)).player_name).is_equal("Zoë 森")


func test_a_long_name_is_cut_at_a_whole_character() -> void:
	# 15 ASCII bytes then a 3-byte character: the character does not fit in 16 and is left out.
	var packet := NetWire.hello("abcdefghijklmno森", 7)
	assert_int(packet.size()).is_equal(NetWire.HELLO_HEADER + 15)
	assert_str(NetWire.read_hello(packet).player_name).is_equal("abcdefghijklmno")
	assert_int(NetWire.hello("x".repeat(40), 7).size()).is_equal(NetWire.MAX_HELLO)


func test_the_version_is_read_before_any_other_field() -> void:
	var drops := NetDrops.new()
	assert_object(NetWire.read_hello(PackedByteArray(OLD_HELLO), drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.BAD_VERSION)
	assert_int(NetWire.hello_version(PackedByteArray(OLD_HELLO))).is_equal(0)
	# Two bytes are enough to be told the version is wrong.
	drops = NetDrops.new()
	assert_object(NetWire.read_hello(PackedByteArray([NetWire.Type.HELLO, 200]), drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.BAD_VERSION)
	# A welcome of an older version too.
	var welcome := SnapshotCodec.welcome(
		0, 1, 2, [] as Array[EntityEntry], [] as Array[PlayerEntry]
	)
	welcome[NetWire.VERSION_AT] = 0
	drops = NetDrops.new()
	assert_object(SnapshotCodec.read_welcome(welcome, drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.BAD_VERSION)


func test_hostile_hellos_are_dropped_with_a_reason() -> void:
	var good := NetWire.hello("Rook", 5)
	var long_name := PackedByteArray([NetWire.Type.HELLO, NetWire.VERSION, 0, 0, 0, 0, 17])
	long_name.append_array("a".repeat(17).to_utf8_buffer())
	var lying_length := good.duplicate()
	lying_length[NetWire.HELLO_HEADER - 1] = 9
	var broken_utf8 := PackedByteArray([NetWire.Type.HELLO, NetWire.VERSION, 0, 0, 0, 0, 2])
	broken_utf8.append_array([0xC3, 0x28])
	var control := PackedByteArray([NetWire.Type.HELLO, NetWire.VERSION, 0, 0, 0, 0, 1, 0x07])
	var cases := {
		NetDrops.EMPTY: PackedByteArray(),
		NetDrops.UNKNOWN_TYPE: PackedByteArray([NetWire.Type.PING, NetWire.VERSION]),
		NetDrops.TOO_SHORT: good.slice(0, 5),
		NetDrops.NAME_TOO_LONG: long_name,
		NetDrops.WRONG_SIZE: lying_length,
		NetDrops.BAD_NAME: broken_utf8,
	}
	for reason: StringName in cases:
		var drops := NetDrops.new()
		(
			assert_object(NetWire.read_hello(cases[reason], drops))
			. override_failure_message(reason)
			. is_null()
		)
		assert_int(drops.of(reason)).override_failure_message(reason).is_equal(1)
	var drops := NetDrops.new()
	assert_object(NetWire.read_hello(control, drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.BAD_NAME)


func test_valid_name_refuses_every_malformed_utf8_form() -> void:
	assert_bool(NetWire.valid_name("Zoë 森 🎮".to_utf8_buffer())).is_true()
	for bad in [
		[0x80],  # a continuation byte first
		[0xC0, 0x80],  # an overlong NUL
		[0xE0, 0x80, 0x80],  # an overlong form
		[0xED, 0xA0, 0x80],  # a surrogate
		[0xF4, 0x90, 0x80, 0x80],  # past U+10FFFF
		[0xE6, 0xA3],  # cut short
		[0xFF],
		[0x7F],
	]:
		(
			assert_bool(NetWire.valid_name(PackedByteArray(bad)))
			. override_failure_message(str(bad))
			. is_false()
		)


func test_refused_round_trip() -> void:
	for reason in NetWire.Refusal.values():
		var packet := NetWire.refused(reason)
		assert_int(packet.size()).is_equal(3)
		assert_int(NetWire.read_refused(packet)).is_equal(reason)
		assert_int(packet[2]).is_equal(NetWire.VERSION)
	var drops := NetDrops.new()
	(
		assert_int(NetWire.read_refused(PackedByteArray([NetWire.Type.REFUSED, 77, 1]), drops))
		. is_equal(-1)
	)
	assert_str(drops.last).is_equal(NetDrops.BAD_VALUE)
	assert_int(NetWire.read_refused(PackedByteArray([NetWire.Type.REFUSED, 1]), drops)).is_equal(-1)
	assert_str(drops.last).is_equal(NetDrops.TOO_SHORT)


func test_ping_and_pong_round_trip() -> void:
	var packet := NetWire.ping(123_456_789, 87)
	assert_int(packet.size()).is_equal(7)
	var ping := NetWire.read_ping(packet)
	assert_int(ping.client_ms).is_equal(123_456_789)
	assert_int(ping.rtt).is_equal(87)
	var pong_packet := NetWire.pong(ping, 4_000_000_001)
	assert_int(pong_packet.size()).is_equal(11)
	var pong := NetWire.read_pong(pong_packet)
	assert_int(pong.client_ms).is_equal(123_456_789)
	assert_int(pong.rtt).is_equal(87)
	assert_int(pong.server_tick).is_equal(4_000_000_001)
	assert_int(NetWire.read_ping(NetWire.ping(1)).rtt).is_equal(-1)
	assert_int(NetWire.read_ping(NetWire.ping(1, 999_999)).rtt).is_equal(NetWire.NO_RTT - 1)
	var drops := NetDrops.new()
	var long := packet.duplicate()
	long.append(0)
	assert_object(NetWire.read_ping(long, drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.TOO_LONG)
	assert_object(NetWire.read_pong(packet, drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.UNKNOWN_TYPE)


func test_world_hash_ignores_order_and_sees_any_change() -> void:
	var parts := PackedStringArray(["World/Door:1", "World/Pad:2", "World/Target:3"])
	var shuffled := PackedStringArray(["World/Target:3", "World/Door:1", "World/Pad:2"])
	assert_int(NetWire.world_hash(parts)).is_equal(NetWire.world_hash(shuffled))
	var changed_parts := PackedStringArray(["World/Door:1", "World/Pad:2", "World/Target:4"])
	assert_int(NetWire.world_hash(parts)).is_not_equal(NetWire.world_hash(changed_parts))
	assert_int(NetWire.world_hash(parts)).is_between(0, 0xFFFFFFFF)
	# FNV-1a of nothing is its offset basis: the function is the published one.
	assert_int(NetWire.world_hash(PackedStringArray())).is_equal(0x811C9DC5)
	assert_int(NetWire.world_hash(PackedStringArray(["a"]))).is_equal(0xE40C292C)


func test_a_decoder_with_no_counter_still_counts() -> void:
	var count_before := NetDrops.unowned().of(NetDrops.EMPTY)
	assert_object(NetWire.read_hello(PackedByteArray())).is_null()
	assert_int(NetDrops.unowned().of(NetDrops.EMPTY)).is_equal(count_before + 1)
