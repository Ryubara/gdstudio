# A client that stops reading for 60 s while it still plays (its downlink stalled, its commands
# still arriving: a client that also stops sending is hung up on after `silent_seconds`, 15 s,
# `test_net_server_silence.gd`). Seven others play beside it, one of them leaving and coming back
# every five seconds, so the stalled client is owed events. Through a `TcpRelay` that stops
# reading the server's side, the server keeps it seated, a send its full buffer refused is counted
# (`peers_stalled` in the stats) and costs nothing that matters (a TICK is whole, so the next one
# replaces it; the events wait), and once the client reads again it has every event once, in
# order, and TICKs of all eight players. Seconds are the frame clock's, so 60 s pass in frames.
extends GdUnitTestSuite

## Frames the client's downlink stalls: 60 s.
const UNREAD_FRAMES := 60 * NetLimits.TICK_RATE
## Frames between the churning player's leaving and coming back.
const CHURN_FRAMES := 5 * NetLimits.TICK_RATE
## Frames the stalled client has after the stall to read what waited.
const CATCH_UP_FRAMES := 10 * NetLimits.TICK_RATE
## Players beside the stalled one that only play (the eighth seat is the churning one's).
const CROWD := NetLimits.MAX_PLAYERS - 2

var _rig: NetServerRig
var _relay: TcpRelay


## A listener whose buffer for one peer is full: every send to it is refused, as `WsListener.send`
## refuses one that would overflow `outbound_buffer`.
class FullListener:
	extends WsListener

	var full_peer := -1

	func send(peer_id: int, data: PackedByteArray) -> bool:
		if peer_id == full_peer:
			refused_sends += 1
			return false
		return super(peer_id, data)


var _walk := CommandDriver.walking(Vector3.FORWARD)


func _start(full_buffer: bool) -> void:
	# The client still sends through the stall, so `silent_seconds` never fires; it is raised only
	# so that a broken relay fails as a missing event, not as a hang-up.
	var configure := func(server: NetServer) -> void:
		server.silent_seconds = 90.0
		if full_buffer:
			server.listener = FullListener.new()
	_rig = auto_free(NetServerRig.new(configure))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_relay = TcpRelay.new()
	assert_int(_relay.start(_rig.server.listener.port())).is_greater(0)


func after_test() -> void:
	_relay.stop()


# With a `FullListener`, makes `peer_id`'s buffer full (-1: none).
func _fill(peer_id: int) -> void:
	var full := _rig.server.listener as FullListener
	if full != null:
		full.full_peer = peer_id


# The stalled client, joined through the relay.
func _join_through_relay() -> HandClient:
	var client := HandClient.new(SocketRig.frame_clock)
	assert_int(client.link.connect_to_url(_relay.url())).is_equal(OK)
	_rig.clients.append(client)
	for _frame in 240:
		_relay.poll()
		_rig.pump()
		if client.link.is_open():
			break
		await get_tree().physics_frame
	client.say_hello("Stalled", _rig.server.world_hash)
	for _frame in 240:
		_relay.poll()
		_rig.pump()
		if client.welcome != null:
			break
		await get_tree().physics_frame
	return client


# Every client sends its command; with `churning` the churning one leaves and comes back every
# `CHURN_FRAMES`. Returns how many times it left.
func _play(
	frames: int, stalled: HandClient, crowd: Array[HandClient], churn: Array, churning := false
) -> int:
	var left := 0
	for frame in frames:
		stalled.send_command(_walk.clone())
		for client in crowd:
			client.send_command(_walk.clone())
		var churner: HandClient = churn[0]
		if churner != null:
			churner.send_command(_walk.clone())
			if churning and frame % CHURN_FRAMES == CHURN_FRAMES - 1:
				churner.link.close()
				churn[0] = null
				left += 1
		elif churning and frame % CHURN_FRAMES == CHURN_FRAMES / 2:
			churn[0] = await _rig.join("Churn")
		_relay.poll()
		_rig.pump()
		await get_tree().physics_frame
	return left


func _run_the_stall() -> Dictionary:
	var stalled := await _join_through_relay()
	assert_object(stalled.welcome).is_not_null()
	var crowd: Array[HandClient] = []
	for index in CROWD:
		crowd.append(await _rig.join("Crowd%d" % index))
	var churn: Array = [await _rig.join("Churn")]
	assert_int(_rig.server.player_count()).is_equal(NetLimits.MAX_PLAYERS)
	await _play(NetLimits.TICK_RATE, stalled, crowd, churn)
	var ticks_before_stall := stalled.ticks.size()
	var events_before_stall := stalled.events.size()
	_relay.hold_down = true
	_fill(_rig.server.peer_at(stalled.welcome.slot).peer_id)
	var refused_before := _rig.server.listener.refused_sends
	var left := await _play(UNREAD_FRAMES, stalled, crowd, churn, true)
	var refused := _rig.server.listener.refused_sends - refused_before
	var ticks_in_stall := stalled.ticks.size() - ticks_before_stall
	_relay.hold_down = false
	_fill(-1)
	# The churning player comes back once its old seat is free, and the stalled client reads what
	# waited.
	await _play(NetLimits.TICK_RATE, stalled, crowd, churn)
	if churn[0] == null:
		churn[0] = await _rig.join("Churn")
	var tick_count := stalled.ticks.size()
	await _play(CATCH_UP_FRAMES, stalled, crowd, churn)
	return {
		"client": stalled,
		"left": left,
		"refused": refused,
		"ticks_in_stall": ticks_in_stall,
		"events_before": events_before_stall,
		"ticks_after": stalled.ticks.size() - tick_count,
		"stalled_lines":
		_rig.lines_of("stats").filter(
			func(line: Dictionary) -> bool: return int(line["peers_stalled"]) > 0
		),
	}


# The stalled client was never hung up on, read every event once in order (a `left` and a
# `joined` for each time the churning player went), and its last TICK has all eight players and
# answers its newest commands.
func _assert_whole(run: Dictionary) -> void:
	var client: HandClient = run["client"]
	assert_bool(client.closed).is_false()
	assert_object(_rig.server.peer_at(client.welcome.slot)).is_not_null()
	var slot := client.welcome.slot
	var its_leaving := _rig.lines_of("left").filter(
		func(line: Dictionary) -> bool: return line["slot"] == slot
	)
	assert_array(its_leaving).is_empty()
	assert_int(client.drops.total()).is_equal(0)
	var heard := client.events.slice(int(run["events_before"]))
	var kinds: Array[int] = []
	for event: NetEvent in heard:
		if event.kind == NetEvent.Kind.LEFT or event.kind == NetEvent.Kind.JOINED:
			kinds.append(event.kind)
	var wanted: Array[int] = []
	for _time in int(run["left"]):
		wanted.append_array([NetEvent.Kind.LEFT, NetEvent.Kind.JOINED])
	assert_array(kinds).is_equal(wanted)
	var server_ticks: Array[int] = []
	for tick in client.ticks:
		server_ticks.append(tick.server_tick)
	var in_order := server_ticks.duplicate()
	in_order.sort()
	assert_array(server_ticks).is_equal(in_order)
	assert_int(int(run["ticks_after"])).is_greater(NetLimits.SNAPSHOT_RATE)
	var last := client.last_tick()
	assert_int(last.players.size()).is_equal(NetLimits.MAX_PLAYERS)
	assert_int(last.ack).is_greater(client.next_seq - 1 - 2 * NetLimits.TICK_RATE / 10)


func test_a_client_unread_for_60_s_stays_seated_and_whole() -> void:
	_start(false)
	var run := await _run_the_stall()
	prints(
		"unread 60 s, the real 256 KB buffer:",
		"relay down %d B," % _relay.bytes_down,
		"refused sends %d," % run["refused"],
		"stats lines with a stalled peer %d," % run["stalled_lines"].size(),
		"churns %d" % run["left"]
	)
	assert_int(int(run["ticks_in_stall"])).is_less(NetLimits.SNAPSHOT_RATE)
	assert_int(int(run["left"])).is_equal(UNREAD_FRAMES / CHURN_FRAMES)
	_assert_whole(run)


func test_a_full_buffer_refuses_ticks_and_the_events_wait() -> void:
	# The sockets of loopback held the minute above (some 230 KB) without a refusal, so the full
	# buffer is the listener's own answer to a send that would overflow it, made for one peer.
	_start(true)
	var run := await _run_the_stall()
	prints(
		"unread 60 s, a full buffer:",
		"refused sends %d," % run["refused"],
		"stats lines with a stalled peer %d" % run["stalled_lines"].size()
	)
	assert_int(int(run["refused"])).is_greater(0)
	assert_array(run["stalled_lines"]).is_not_empty()
	_assert_whole(run)
