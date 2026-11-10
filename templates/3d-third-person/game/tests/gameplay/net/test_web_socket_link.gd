# A server and a client in one process over a real socket on 127.0.0.1: packets in order both ways,
# a bad network of 100 ms each way on the game's clock, goodbyes told from dropped sockets, and
# where the client finds its server (the command line, the page's address, never ws:// from https).
extends GdUnitTestSuite

const HANDSHAKE_REQUEST := (
	"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
	+ "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
)

var _rig: SocketRig
var _raw: Array[StreamPeerTCP] = []


func before_test() -> void:
	_rig = SocketRig.new(get_tree())
	assert_bool(_rig.start()).is_true()


func after_test() -> void:
	_rig.stop()
	for tcp in _raw:
		tcp.disconnect_from_host()
	_raw.clear()


func test_a_thousand_packets_arrive_in_order_both_ways() -> void:
	var link := await _rig.connect_link()
	assert_object(link).is_not_null()
	var id := _rig.ids[0]
	var read: Array[PackedByteArray] = []
	link.packet_received.connect(func(data: PackedByteArray) -> void: read.append(data))
	for i in 1000:
		assert_bool(link.send(SocketRig.numbered(i, 24))).is_true()
		assert_bool(_rig.listener.send(id, SocketRig.numbered(i, 24))).is_true()
		if i % 50 == 0:
			_rig.pump()
	var all := await _rig.until(
		func() -> bool: return read.size() >= 1000 and _rig.got[id].size() >= 1000
	)
	assert_bool(all).is_true()
	for i in 1000:
		assert_int(read[i].decode_u32(0)).is_equal(i)
		assert_int((_rig.got[id][i] as PackedByteArray).decode_u32(0)).is_equal(i)
		assert_bool(read[i] == SocketRig.numbered(i, 24)).is_true()
	assert_int(link.packets_in).is_equal(1000)
	assert_int(link.bytes_out).is_equal(24000)
	assert_int(_rig.listener.packets_out).is_equal(1000)


func test_a_conditioner_of_100_ms_each_way_delays_a_round_trip_by_200_ms_and_keeps_order() -> void:
	var link := await _rig.connect_link()
	var id := _rig.ids[0]
	var bad := LinkConditioner.new(link, 0.1, 0.0, 3)
	bad.clock = SocketRig.frame_clock
	# The rig polls the bare link; the conditioner polls it from here on.
	_rig.links.erase(link)
	# The server echoes what it hears.
	_rig.listener.packet_received.connect(
		func(peer: int, data: PackedByteArray) -> void: _rig.listener.send(peer, data)
	)
	var trips: Array[float] = []
	var order: Array[int] = []
	var sent_at: Dictionary[int, float] = {}
	bad.packet_received.connect(
		func(data: PackedByteArray) -> void:
			var index := data.decode_u32(0)
			order.append(index)
			trips.append(SocketRig.frame_clock() - sent_at[index])
	)
	for i in 60:
		sent_at[i] = SocketRig.frame_clock()
		bad.send(SocketRig.numbered(i))
		bad.poll()
		_rig.pump()
		await get_tree().physics_frame
	var back := await _rig.until(
		func() -> bool:
			bad.poll()
			return order.size() >= 60,
		120
	)
	assert_bool(back).is_true()
	assert_array(order).is_equal(range(60))
	trips.sort()
	# 200 ms of the conditioner plus the polls' rounding to the tick (each way).
	assert_float(trips[0]).is_greater_equal(0.2)
	assert_float(trips[-1]).is_less_equal(0.2 + 4.0 / 60.0 + 0.001)
	assert_int(bad.passed).is_equal(120)
	assert_int(id).is_equal(1)


func test_left_on_purpose_is_true_for_close_and_false_for_a_drop() -> void:
	var gone: Array[int] = []
	_rig.listener.peer_disconnected.connect(func(peer: int) -> void: gone.append(peer))
	var leaver := await _rig.connect_link()
	var dropper := await _rig.connect_link()
	var leaver_id := _rig.ids[0]
	var dropper_id := _rig.ids[1]
	leaver.close()
	dropper.drop()
	assert_bool(await _rig.until(func() -> bool: return gone.size() == 2)).is_true()
	assert_bool(_rig.listener.left_on_purpose(leaver_id)).is_true()
	assert_int(_rig.listener.close_code_of(leaver_id)).is_equal(NetLink.CLOSE_NORMAL)
	assert_bool(_rig.listener.left_on_purpose(dropper_id)).is_false()
	assert_int(_rig.listener.close_code_of(dropper_id)).is_equal(WebSocketLink.DROP_CODE)


func test_left_on_purpose_is_false_for_a_socket_cut_without_a_close_frame() -> void:
	var gone: Array[int] = []
	_rig.listener.peer_disconnected.connect(func(peer: int) -> void: gone.append(peer))
	var tcp := StreamPeerTCP.new()
	_raw.append(tcp)
	assert_int(tcp.connect_to_host("127.0.0.1", _rig.listener.port())).is_equal(OK)
	var sent := [false]
	var opened := await _rig.until(
		func() -> bool:
			tcp.poll()
			if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent[0]:
				sent[0] = true
				tcp.put_data(HANDSHAKE_REQUEST.to_utf8_buffer())
			return not _rig.ids.is_empty()
	)
	assert_bool(opened).is_true()
	tcp.disconnect_from_host()
	assert_bool(await _rig.until(func() -> bool: return gone.size() == 1)).is_true()
	assert_bool(_rig.listener.left_on_purpose(_rig.ids[0])).is_false()
	assert_int(_rig.listener.close_code_of(_rig.ids[0])).is_equal(NetLink.CLOSE_NONE)


func test_the_client_hears_the_servers_goodbye_and_reads_what_came_before_it() -> void:
	var link := await _rig.connect_link()
	var id := _rig.ids[0]
	var read := [0]
	var read_at_close := [-1]
	link.packet_received.connect(func(_data: PackedByteArray) -> void: read[0] += 1)
	link.closed.connect(func() -> void: read_at_close[0] = read[0])
	for i in 20:
		_rig.listener.send(id, SocketRig.numbered(i))
	_rig.listener.disconnect_peer(id)
	assert_bool(await _rig.until(func() -> bool: return read_at_close[0] >= 0)).is_true()
	assert_int(read_at_close[0]).is_equal(20)
	assert_bool(link.left_on_purpose()).is_true()
	assert_bool(link.is_open()).is_false()
	assert_bool(link.send(PackedByteArray([1]))).is_false()


func test_the_server_reads_the_clients_last_packets_before_its_goodbye() -> void:
	var link := await _rig.connect_link()
	var id := _rig.ids[0]
	var at_gone := [-1]
	_rig.listener.peer_disconnected.connect(
		func(_peer: int) -> void: at_gone[0] = _rig.got[id].size()
	)
	for i in 5:
		link.send(SocketRig.numbered(i))
	link.close()
	assert_bool(link.is_open()).is_false()
	assert_bool(link.send(PackedByteArray([9]))).is_false()
	assert_bool(await _rig.until(func() -> bool: return at_gone[0] >= 0)).is_true()
	assert_int(at_gone[0]).is_equal(5)
	assert_bool(_rig.listener.left_on_purpose(id)).is_true()


# Why both ends linger before their close frame: Godot's WebSocketPeer throws away what reaches it
# in the same poll as the close. Without the linger the last packets are lost both ways (if this
# starts passing with all packets read, the engine changed and the linger can go).
func test_without_the_linger_the_engine_loses_the_last_packets_both_ways() -> void:
	_rig.listener.close_linger = 0.0
	var link := await _rig.connect_link()
	link.close_linger = 0.0
	var id := _rig.ids[0]
	var read := [0]
	var at_close := [-1]
	link.packet_received.connect(func(_data: PackedByteArray) -> void: read[0] += 1)
	link.closed.connect(func() -> void: at_close[0] = read[0])
	for i in 20:
		_rig.listener.send(id, SocketRig.numbered(i))
	_rig.listener.disconnect_peer(id)
	assert_bool(await _rig.until(func() -> bool: return at_close[0] >= 0)).is_true()
	assert_int(at_close[0]).is_equal(0)
	var other := await _rig.connect_link()
	other.close_linger = 0.0
	var other_id := _rig.ids[1]
	var at_gone := [-1]
	_rig.listener.peer_disconnected.connect(
		func(peer: int) -> void:
			if peer == other_id:
				at_gone[0] = _rig.got[other_id].size()
	)
	for i in 5:
		other.send(SocketRig.numbered(i))
	other.close()
	assert_bool(await _rig.until(func() -> bool: return at_gone[0] >= 0)).is_true()
	assert_int(at_gone[0]).is_equal(0)


func test_a_server_that_goes_away_is_not_a_goodbye() -> void:
	var link := await _rig.connect_link()
	var closed := [false]
	link.closed.connect(func() -> void: closed[0] = true)
	# The listener is freed with its sockets and sends no closing handshake: its process died.
	_rig.listener = WsListener.new()
	var ended := await _rig.until(func() -> bool: return closed[0], 300)
	assert_bool(ended).is_true()
	assert_bool(link.left_on_purpose()).is_false()


func test_the_server_address_comes_from_the_command_line_or_the_page() -> void:
	var args := PackedStringArray(["--connect", "ws://10.0.0.2:8910"])
	assert_str(WebSocketLink.url_from(args, "")).is_equal("ws://10.0.0.2:8910")
	args = PackedStringArray(["--server", "--connect=wss://play.example:443"])
	assert_str(WebSocketLink.url_from(args, "")).is_equal("wss://play.example:443")
	var search := "?probe&url=wss%3A%2F%2Fplay.example%2Fgame&seed=3"
	assert_str(WebSocketLink.url_from(PackedStringArray(), search)).is_equal(
		"wss://play.example/game"
	)
	assert_str(WebSocketLink.url_from(PackedStringArray(), "?connect=ws://h:1")).is_equal(
		"ws://h:1"
	)
	assert_str(WebSocketLink.url_from(PackedStringArray(), "?url=", "ws://x:2")).is_equal(
		"ws://x:2"
	)
	assert_str(WebSocketLink.url_from(PackedStringArray(), "")).is_empty()


func test_an_https_page_never_downgrades_to_ws() -> void:
	assert_str(WebSocketLink.url_problem("ws://h:8910", "https:")).contains("wss://")
	assert_str(WebSocketLink.url_problem("wss://h", "https:")).is_empty()
	assert_str(WebSocketLink.url_problem("ws://h:8910", "http:")).is_empty()
	assert_str(WebSocketLink.url_problem("ws://h:8910", "")).is_empty()
	assert_str(WebSocketLink.url_problem("http://h", "")).contains("not a WebSocket")
	var link := WebSocketLink.new()
	assert_int(link.connect_to_url("tcp://nowhere")).is_equal(ERR_UNAUTHORIZED)
	assert_str(link.refusal).is_not_empty()
	assert_bool(link.is_open()).is_false()


func test_a_link_never_connected_is_quiet() -> void:
	var link := WebSocketLink.new()
	link.poll()
	link.close()
	assert_bool(link.send(PackedByteArray([1]))).is_false()
	assert_int(link.close_code()).is_equal(NetLink.CLOSE_NONE)
