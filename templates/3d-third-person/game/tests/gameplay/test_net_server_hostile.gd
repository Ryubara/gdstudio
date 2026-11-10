# Hostile clients against the game server over real sockets: a flood of commands, packets of the
# wrong size, unknown types, flags no build sets, a command before its hello, commands out of
# order, a name that is not UTF-8 and a packet too big for the listener. Each is struck and hung up
# on (a kick is logged with why), while an honest player beside them is never kicked, its TICKs
# never stop for more than a few frames, and its body walks as its commands say.
extends GdUnitTestSuite

## The most frames between two TICKs the honest client may see (a TICK is due every second one).
const MOST_FRAMES_BETWEEN_TICKS := 4

var _rig: NetServerRig
var _honest: HandClient
var _walk := CommandDriver.walking(Vector3.FORWARD)


func before_test() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_honest = await _rig.join("Honest")
	assert_object(_honest).is_not_null()


# Sends `each_frame` to the hostile client every frame (with the honest client's command) until
# it is hung up on; true when it was within `frames`.
func _until_hung_up(hostile: HandClient, each_frame: Callable, frames := 240) -> bool:
	for _frame in frames:
		_honest.send_command(_walk.clone())
		if not hostile.closed:
			each_frame.call()
		_rig.pump()
		if hostile.closed:
			return true
		await get_tree().physics_frame
	return hostile.closed


func _greeted_hostile() -> HandClient:
	var hostile := await _rig.join("Hostile")
	assert_object(hostile).is_not_null()
	return hostile


# The honest one goes on walking for a second after the hostile one went, then: its TICKs never
# stopped, it was never kicked, the server applied its commands and its body walked.
func _assert_the_honest_one_was_served() -> void:
	for _frame in NetLimits.TICK_RATE:
		_honest.send_command(_walk.clone())
		_rig.pump()
		await get_tree().physics_frame
	var gaps := PackedInt32Array()
	for index in range(1, _honest.tick_frames.size()):
		gaps.append(_honest.tick_frames[index] - _honest.tick_frames[index - 1])
	assert_int(Array(gaps).max()).is_less_equal(MOST_FRAMES_BETWEEN_TICKS)
	assert_bool(_honest.closed).is_false()
	assert_object(_rig.server.peer_at(0)).is_not_null()
	assert_int(_honest.last_tick().ack).is_greater(30)
	var body := _rig.server.body_at(0)
	assert_bool(body.global_position.is_finite()).is_true()
	assert_float(body.global_position.z).is_less(NetServerRig.SPAWNS[0].z - 2.0)
	assert_int(_honest.drops.total()).is_equal(0)


func _assert_kicked_for(reason: StringName) -> void:
	var kicks := _rig.lines_of("kicked")
	assert_int(kicks.size()).is_equal(1)
	assert_str(kicks[0]["drops"]).contains(String(reason))


func test_a_flood_of_commands_is_hung_up_on() -> void:
	var hostile := await _greeted_hostile()
	var flood := func() -> void:
		for _i in 200:
			hostile.send_command(_walk.clone())
	assert_bool(await _until_hung_up(hostile, flood)).is_true()
	_assert_kicked_for(NetDrops.OVER_RATE)
	assert_object(_rig.server.peer_at(1)).is_null()
	await _assert_the_honest_one_was_served()
	assert_int(_honest.heard(NetEvent.Kind.LEFT).size()).is_equal(1)


func test_packets_of_the_wrong_size_and_unknown_types_are_hung_up_on() -> void:
	var hostile := await _greeted_hostile()
	var short_command := CommandCodec.encode(_walk).slice(0, NetWire.COMMAND_SIZE - 1)
	var junk := func() -> void:
		hostile.link.send(short_command)
		hostile.link.send(PackedByteArray([0xEE, 1, 2, 3]))
	assert_bool(await _until_hung_up(hostile, junk)).is_true()
	_assert_kicked_for(NetDrops.WRONG_SIZE)
	_assert_kicked_for(NetDrops.UNKNOWN_TYPE)
	await _assert_the_honest_one_was_served()


func test_flags_no_build_sets_and_commands_out_of_order_are_hung_up_on() -> void:
	var hostile := await _greeted_hostile()
	var unknown_flags := CommandCodec.encode(_walk)
	unknown_flags.encode_u16(11, 0xF800)
	var again := CommandCodec.encode(_walk)
	again.encode_u32(1, 1)
	var lies := func() -> void:
		hostile.link.send(unknown_flags)
		hostile.link.send(again)
	assert_bool(await _until_hung_up(hostile, lies)).is_true()
	_assert_kicked_for(NetDrops.BAD_VALUE)
	_assert_kicked_for(NetDrops.OUT_OF_ORDER)
	await _assert_the_honest_one_was_served()


func test_the_largest_numbers_a_command_can_carry_step_a_finite_body() -> void:
	var hostile := await _greeted_hostile()
	var extreme := PackedByteArray()
	extreme.resize(NetWire.COMMAND_SHOT_SIZE)
	extreme.fill(0x7F)
	extreme[0] = NetWire.Type.COMMAND
	extreme.encode_u32(1, 1)
	extreme.encode_u16(11, CommandCodec.F_SHOT | CommandCodec.F_SPRINT | CommandCodec.F_FIRE)
	hostile.link.send(extreme)
	var peer := _rig.server.peer_at(1)
	assert_bool(await _rig.until(func() -> bool: return peer.ack == 1)).is_true()
	await _rig.wait(30)
	var body := _rig.server.body_at(1)
	assert_bool(body.global_position.is_finite() and body.velocity.is_finite()).is_true()
	assert_bool(is_finite(body.facing) and is_finite(body.view_yaw)).is_true()
	assert_bool(hostile.closed).is_false()


func test_a_command_before_hello_and_a_broken_name_are_hung_up_on() -> void:
	var early := await _rig.connect_client()
	var before_hello := func() -> void: early.link.send(CommandCodec.encode(_walk))
	assert_bool(await _until_hung_up(early, before_hello)).is_true()
	_assert_kicked_for(NetDrops.NO_HELLO)
	var broken := await _rig.connect_client()
	var hello := NetWire.hello("ab", _rig.server.world_hash)
	hello[NetWire.HELLO_HEADER] = 0xC3
	broken.link.send(hello)
	await _rig.wait(10)
	assert_object(broken.welcome).is_null()
	# One bad hello is a strike, and a second hello is another: it never gets a seat.
	var twice := func() -> void: broken.link.send(NetWire.hello("ok", _rig.server.world_hash))
	assert_bool(await _until_hung_up(broken, twice)).is_true()
	assert_object(broken.welcome).is_null()
	assert_int(_rig.server.player_count()).is_equal(1)
	await _assert_the_honest_one_was_served()


func test_a_packet_too_big_for_the_listener_is_hung_up_on() -> void:
	var hostile := await _greeted_hostile()
	var big := PackedByteArray()
	big.resize(WsListener.MAX_PACKET_BYTES + 1)
	hostile.link.send(big)
	assert_bool(await _until_hung_up(hostile, func() -> void: pass)).is_true()
	assert_int(hostile.link.close_code()).is_equal(WsListener.CLOSE_TOO_BIG)
	assert_bool(await _rig.until(func() -> bool: return _rig.server.peer_at(1) == null)).is_true()
	assert_str(_rig.lines_of("left")[0]["reason"]).is_equal("dropped")
	await _assert_the_honest_one_was_served()
