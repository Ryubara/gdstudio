# The bad network around a link, on the test's own clock: a delay each way holds every packet that
# long and keeps the order, jitter never reorders, a stall holds everything behind it, and the
# random stalls repeat with the seed. Over a loopback pair, so no socket and no wall time.
extends GdUnitTestSuite

const TICK := 1.0 / 60.0

var _now := 0.0
var _client: LinkConditioner
var _server: LoopbackLink
## Each packet the server read, with the time it read it.
var _server_read: Array[Dictionary] = []
var _client_read: Array[Dictionary] = []


func before_test() -> void:
	_now = 0.0
	_server_read.clear()
	_client_read.clear()
	var ends := LoopbackLink.pair()
	_client = LinkConditioner.new(ends[0], 0.1, 0.0, 5)
	_client.clock = func() -> float: return _now
	_server = ends[1]
	_server.packet_received.connect(
		func(data: PackedByteArray) -> void: _server_read.append({"at": _now, "data": data})
	)
	_client.packet_received.connect(
		func(data: PackedByteArray) -> void: _client_read.append({"at": _now, "data": data})
	)


## One tick of the test's clock: both ends polled.
func _tick() -> void:
	_now += TICK
	_client.poll()
	_server.poll()


func _ticks(count: int) -> void:
	for _i in count:
		_tick()


func test_a_delay_each_way_holds_every_packet_that_long_and_keeps_the_order() -> void:
	_tick()
	var sent_at: Array[float] = []
	for i in 300:
		_client.send(SocketRig.numbered(i))
		_server.send(SocketRig.numbered(i))
		sent_at.append(_now)
		_tick()
	_ticks(30)
	assert_int(_server_read.size()).is_equal(300)
	assert_int(_client_read.size()).is_equal(300)
	for i in 300:
		assert_int(_server_read[i]["data"].decode_u32(0)).is_equal(i)
		assert_int(_client_read[i]["data"].decode_u32(0)).is_equal(i)
		# 100 ms of the conditioner, rounded up to the tick, and the loopback's one tick.
		var late: float = _server_read[i]["at"] - sent_at[i]
		assert_float(late).is_between(0.1, 0.1 + 2.0 * TICK + 0.0001)
		late = _client_read[i]["at"] - sent_at[i]
		assert_float(late).is_between(0.1, 0.1 + 2.0 * TICK + 0.0001)


func test_jitter_never_lets_a_packet_overtake_the_one_before() -> void:
	_client.jitter = 0.08
	_tick()
	for i in 500:
		_server.send(SocketRig.numbered(i))
		_tick()
	_ticks(30)
	assert_int(_client_read.size()).is_equal(500)
	var gaps := {}
	for i in 500:
		assert_int(_client_read[i]["data"].decode_u32(0)).is_equal(i)
		if i > 0:
			gaps[snappedf(_client_read[i]["at"] - _client_read[i - 1]["at"], 0.001)] = true
	# The jitter did something: arrivals are not one tick apart every time.
	assert_int(gaps.size()).is_greater(2)


func test_a_stall_of_300_ms_holds_every_later_packet() -> void:
	_tick()
	for i in 10:
		_server.send(SocketRig.numbered(i))
		_tick()
	_ticks(12)
	assert_int(_client_read.size()).is_equal(10)
	var stalled_at := _now
	_client.stall_for(0.3)
	for i in range(10, 40):
		_server.send(SocketRig.numbered(i))
		_tick()
	_ticks(30)
	assert_int(_client_read.size()).is_equal(40)
	var first_after: float = _client_read[10]["at"]
	assert_float(first_after - stalled_at).is_greater_equal(0.3)
	for i in range(10, 40):
		assert_int(_client_read[i]["data"].decode_u32(0)).is_equal(i)
	# Everything held came out together when the stall ended (the burst after a stall), then the
	# rest a tick apart.
	var together := 0
	for i in range(10, 40):
		if absf(_client_read[i]["at"] - first_after) < 0.0001:
			together += 1
	assert_int(together).is_greater(8)


func test_a_stall_holds_what_the_client_sends_too() -> void:
	_tick()
	var stalled_at := _now
	_client.stall_for(0.3)
	_client.send(SocketRig.numbered(1))
	_ticks(12)
	assert_int(_server_read.size()).is_equal(0)
	_ticks(12)
	assert_int(_server_read.size()).is_equal(1)
	assert_float(_server_read[0]["at"] - stalled_at).is_greater_equal(0.3)


func test_random_stalls_count_and_repeat_with_the_seed() -> void:
	var arrivals := []
	for run in 2:
		before_test()
		_client.stall_chance = 0.05
		_client.stall_seconds = 0.25
		_tick()
		for i in 400:
			_server.send(SocketRig.numbered(i))
			_tick()
		_ticks(60)
		assert_int(_client_read.size()).is_equal(400)
		assert_int(_client.stalled).is_between(5, 40)
		var times: Array[float] = []
		for entry in _client_read:
			times.append(entry["at"])
		arrivals.append(times)
	assert_array(arrivals[0]).is_equal(arrivals[1])


func test_the_close_comes_after_the_held_packets() -> void:
	var read_at_close := [-1]
	_client.closed.connect(func() -> void: read_at_close[0] = _client_read.size())
	_tick()
	for i in 5:
		_server.send(SocketRig.numbered(i))
	_server.close()
	_ticks(30)
	assert_int(read_at_close[0]).is_equal(5)
	assert_bool(_client.left_on_purpose()).is_true()
	assert_bool(_client.send(PackedByteArray([1]))).is_false()


func test_it_passes_connected_and_counts_bytes() -> void:
	var said := [false]
	_client.connected.connect(func() -> void: said[0] = true)
	_tick()
	assert_bool(said[0]).is_true()
	_client.send(PackedByteArray([1, 2, 3]))
	_ticks(12)
	assert_int(_client.bytes_out).is_equal(3)
	assert_int(_client.packets_out).is_equal(1)
	assert_int(_client.waiting()).is_equal(0)
	assert_object(_client.inner()).is_not_null()
