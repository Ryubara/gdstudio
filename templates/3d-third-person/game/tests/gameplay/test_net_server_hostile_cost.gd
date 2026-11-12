# What hostile clients cost the honest one over real sockets: the game server's step time while a
# stream of hostile clients attacks it (each hung up on, the next one connecting at once) stays
# within 20 % of its step time with two polite players in the seats the hostile ones take (a
# seated hostile client's body is stepped like any other: that is a player's cost, not an
# attack's), at the median, and its 95th
# percentile under `NetServer.STEP_BUDGET_MS`. The attacks: a flood of commands, packets of the
# wrong size and of unknown types, a packet too big for the listener, commands out of order, a
# second hello, and a socket that never reads. Quiet and hostile windows take turns, so a machine
# that slows down for a while slows both. Prints the numbers.
extends GdUnitTestSuite

enum Attack { FLOOD, JUNK, OVERSIZE, OUT_OF_ORDER, HELLO_TWICE, UNREAD }

## Frames of one window, and the windows of each kind (quiet, hostile, quiet, hostile...).
const WINDOW_FRAMES := 300
const ROUNDS := 3
## The hostile median may be this much above the quiet one.
const MOST_SLOWER := 1.2
## Steps of each window left out: the first ones after a change of window.
const SETTLE_FRAMES := 10

var _rig: NetServerRig
var _honest: HandClient
var _walk := CommandDriver.walking(Vector3.FORWARD)
var _hostile: HandClient
var _hostile_kind := 0
var _greeted := false
var _unread: Array[HandClient] = []
var _hung_up := 0
var _polite: Array[HandClient] = []


func before_test() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_rig.server.keep_step_times = true
	_honest = await _rig.join("Honest")
	assert_object(_honest).is_not_null()


func after_test() -> void:
	for client in _unread:
		client.release()
	_unread.clear()


func test_hostile_clients_leave_the_honest_players_step_time_within_20_percent() -> void:
	var quiet := PackedFloat32Array()
	var hostile := PackedFloat32Array()
	await _frames(WINDOW_FRAMES, false)
	for _round in ROUNDS:
		quiet.append_array(await _frames(WINDOW_FRAMES, false))
		hostile.append_array(await _frames(WINDOW_FRAMES, true))
	var quiet_p50 := _percentile(quiet, 0.5)
	var hostile_p50 := _percentile(hostile, 0.5)
	var hostile_p95 := _percentile(hostile, 0.95)
	prints(
		"hostile cost: quiet step p50 %.3f ms p95 %.3f ms," % [quiet_p50, _percentile(quiet, 0.95)],
		"hostile p50 %.3f ms p95 %.3f ms," % [hostile_p50, hostile_p95],
		"mean %.3f against %.3f ms," % [_mean(hostile), _mean(quiet)],
		"%d hostile clients hung up on, %d kicked" % [_hung_up, _rig.server.kicked]
	)
	# Every kind attacked, and each hostile client but the unread ones was hung up on.
	assert_int(_hung_up).is_greater(Attack.size() * ROUNDS)
	assert_float(hostile_p50).is_less_equal(quiet_p50 * MOST_SLOWER)
	assert_float(hostile_p95).is_less(NetServer.STEP_BUDGET_MS)
	# The honest one was served throughout: never hung up on, and its commands were applied.
	assert_bool(_honest.closed).is_false()
	assert_object(_rig.server.peer_at(0)).is_not_null()
	assert_int(_honest.last_tick().ack).is_greater(_honest.next_seq - 1 - NetLimits.TICK_RATE / 6)


# Steps `frames` frames with the honest client walking and, when `attacking`, a hostile client at
# work; the server's step times of the frames after the first `SETTLE_FRAMES`.
func _frames(frames: int, attacking: bool) -> PackedFloat32Array:
	if attacking:
		for client in _polite:
			_let_go(client)
		_polite.clear()
	else:
		if _hostile != null:
			_let_go(_hostile)
		while _polite.size() < 2:
			_polite.append(await _rig.join("Polite%d" % _polite.size()))
	var first := _rig.server.step_times.size()
	for _frame in frames:
		_honest.send_command(_walk.clone())
		if attacking:
			_attack()
		for client in _polite:
			client.send_command(_walk.clone())
		_rig.pump()
		await get_tree().physics_frame
	# The unread socket of a hostile window closes with it, so a quiet window has none.
	for client in _unread:
		client.release()
	_unread.clear()
	return _rig.server.step_times.slice(first + SETTLE_FRAMES)


# One frame of the hostile client's life: connect, say hello, attack until it is hung up on, then
# the next kind connects.
func _attack() -> void:
	if _hostile != null and _hostile.closed:
		_let_go(_hostile)
		_hung_up += 1
	if _hostile == null:
		_hostile = HandClient.new(SocketRig.frame_clock)
		_hostile.link.connect_to_url(_rig.url())
		_rig.clients.append(_hostile)
		_greeted = false
		_hostile_kind = (_hostile_kind + 1) % Attack.size()
		return
	if not _hostile.link.is_open():
		return
	if not _greeted:
		_greeted = true
		_hostile.say_hello("Hostile", _rig.server.world_hash)
		return
	if _hostile.welcome == null:
		return
	match _hostile_kind:
		Attack.FLOOD:
			for _i in 200:
				_hostile.send_command(_walk.clone())
		Attack.JUNK:
			_hostile.link.send(CommandCodec.encode(_walk).slice(0, NetWire.COMMAND_SIZE - 1))
			_hostile.link.send(PackedByteArray([0xEE, 1, 2, 3]))
		Attack.OVERSIZE:
			var big := PackedByteArray()
			big.resize(WsListener.MAX_PACKET_BYTES + 1)
			_hostile.link.send(big)
		Attack.OUT_OF_ORDER:
			var again := CommandCodec.encode(_walk)
			again.encode_u32(1, 1)
			_hostile.link.send(again)
		Attack.HELLO_TWICE:
			_hostile.say_hello("Again", _rig.server.world_hash)
		Attack.UNREAD:
			# Seated, then never polled again for the rest of the window: its TICKs pile up in the
			# sockets; the next kind connects beside it. One a window holds a seat, not eight.
			if not _unread.is_empty():
				_hostile.link.close()
				return
			_rig.clients.erase(_hostile)
			_unread.append(_hostile)
			_hostile = null
			_hung_up += 1


func _let_go(client: HandClient) -> void:
	_rig.clients.erase(client)
	client.release()
	if client == _hostile:
		_hostile = null


static func _percentile(values: PackedFloat32Array, share: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return NetServer.percentile(sorted, share)


static func _mean(values: PackedFloat32Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxi(values.size(), 1)
