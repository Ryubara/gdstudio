# The in-process link: a packet sent in tick t is read in tick t+1 whichever end polls first, in
# order and copied; a close reaches the other end as a goodbye, a drop as a network that went.
extends GdUnitTestSuite

var _a: LoopbackLink
var _b: LoopbackLink
var _read_a: Array[PackedByteArray] = []
var _read_b: Array[PackedByteArray] = []


func before_test() -> void:
	var ends := LoopbackLink.pair()
	_a = ends[0]
	_b = ends[1]
	_read_a.clear()
	_read_b.clear()
	_a.packet_received.connect(func(data: PackedByteArray) -> void: _read_a.append(data))
	_b.packet_received.connect(func(data: PackedByteArray) -> void: _read_b.append(data))


func test_both_ends_say_connected_on_their_first_poll() -> void:
	var said := [0]
	_a.connected.connect(func() -> void: said[0] += 1)
	_b.connected.connect(func() -> void: said[0] += 1)
	_a.poll()
	_b.poll()
	_a.poll()
	assert_int(said[0]).is_equal(2)
	assert_bool(_a.is_open() and _b.is_open()).is_true()


func test_a_packet_sent_in_one_tick_is_read_in_the_next_whoever_polls_first() -> void:
	# The receiver polls first in the tick of the send.
	_b.poll()
	_a.poll()
	assert_bool(_a.send(PackedByteArray([1]))).is_true()
	assert_int(_read_b.size()).is_equal(0)
	_b.poll()
	_a.poll()
	assert_int(_read_b.size()).is_equal(1)
	# The sender polls first in the tick of the send.
	_a.poll()
	assert_bool(_a.send(PackedByteArray([2]))).is_true()
	_b.poll()
	assert_int(_read_b.size()).is_equal(1)
	_a.poll()
	_b.poll()
	assert_array(_read_b).is_equal([PackedByteArray([1]), PackedByteArray([2])])


func test_a_thousand_packets_arrive_in_order_and_copied() -> void:
	var sent := PackedByteArray([0, 0, 0, 0])
	for i in 1000:
		sent.encode_u32(0, i)
		_a.send(sent)
		_b.send(sent)
		_a.poll()
		_b.poll()
	_a.poll()
	_b.poll()
	assert_int(_read_b.size()).is_equal(1000)
	assert_int(_read_a.size()).is_equal(1000)
	for i in 1000:
		assert_int(_read_b[i].decode_u32(0)).is_equal(i)
	assert_int(_a.packets_out).is_equal(1000)
	assert_int(_b.bytes_in).is_equal(4000)


func test_a_close_reaches_the_other_end_as_a_goodbye_after_the_packets_before_it() -> void:
	var closed_b := [false]
	_b.closed.connect(func() -> void: closed_b[0] = _read_b.size() == 1)
	_a.poll()
	_b.poll()
	_a.send(PackedByteArray([7]))
	_a.close()
	assert_bool(_a.send(PackedByteArray([8]))).is_false()
	_a.poll()
	_b.poll()
	assert_bool(closed_b[0]).is_true()
	assert_bool(_b.is_open()).is_false()
	assert_bool(_b.left_on_purpose()).is_true()
	assert_int(_b.close_code()).is_equal(NetLink.CLOSE_NORMAL)


func test_a_drop_reaches_the_other_end_as_a_network_that_went() -> void:
	_a.poll()
	_b.poll()
	_a.drop()
	_a.poll()
	_b.poll()
	assert_bool(_b.is_open()).is_false()
	assert_bool(_b.left_on_purpose()).is_false()
	assert_int(_b.close_code()).is_equal(NetLink.CLOSE_NONE)


func test_closed_fires_once() -> void:
	var count := [0]
	_b.closed.connect(func() -> void: count[0] += 1)
	_a.close()
	for _i in 5:
		_a.poll()
		_b.poll()
	assert_int(count[0]).is_equal(1)
