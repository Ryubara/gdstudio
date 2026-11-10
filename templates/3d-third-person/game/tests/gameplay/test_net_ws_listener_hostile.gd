# A hostile or broken connection against the listener over a real socket: frames too big for the
# buffer, a connection that never finishes its handshake, a peer that never answers the closing
# handshake. The listener keeps serving an honest client through all of it.
extends GdUnitTestSuite

var _rig: SocketRig
var _raw: Array[WebSocketPeer] = []
var _tcp: Array[StreamPeerTCP] = []
var _now := 0.0


func before_test() -> void:
	_now = 0.0
	_rig = SocketRig.new(get_tree())
	assert_bool(_rig.start()).is_true()


func after_test() -> void:
	_rig.stop()
	for ws in _raw:
		ws.close()
	_raw.clear()
	for tcp in _tcp:
		tcp.disconnect_from_host()
	_tcp.clear()


## A bare socket that sends whatever the test likes.
func _bare_socket() -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.outbound_buffer_size = 4 << 20
	ws.connect_to_url(_rig.url())
	_raw.append(ws)
	var opened := await _rig.until(
		func() -> bool:
			ws.poll()
			return ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	)
	assert_bool(opened).is_true()
	return ws


## The honest client still gets an echo through.
func _still_serves(link: WebSocketLink, id: int) -> bool:
	var heard := [false]
	var listen := func(data: PackedByteArray) -> void: heard[0] = heard[0] or data.size() == 3
	link.packet_received.connect(listen)
	_rig.listener.send(id, PackedByteArray([1, 2, 3]))
	var ok := await _rig.until(func() -> bool: return heard[0])
	link.packet_received.disconnect(listen)
	return ok and _rig.listener.is_listening()


func _flood(size: int, count: int) -> void:
	var honest := await _rig.connect_link()
	var honest_id := _rig.ids[0]
	var flooder := await _bare_socket()
	assert_bool(await _rig.until(func() -> bool: return _rig.ids.size() == 2)).is_true()
	var flooder_id := _rig.ids[1]
	var gone: Array[int] = []
	_rig.listener.peer_disconnected.connect(func(peer: int) -> void: gone.append(peer))
	var big := PackedByteArray()
	big.resize(size)
	for _i in count:
		flooder.send(big, WebSocketPeer.WRITE_MODE_BINARY)
	var cut := await _rig.until(
		func() -> bool:
			flooder.poll()
			return flooder_id in gone,
		300
	)
	(
		assert_bool(cut)
		. override_failure_message("the flooder of %d B frames was not cut off" % size)
		. is_true()
	)
	assert_array(_rig.got[flooder_id]).is_empty()
	assert_bool(await _still_serves(honest, honest_id)).is_true()
	assert_bool(honest_id in gone).is_false()


func test_a_flood_of_64_kb_frames_is_refused_and_the_others_are_served() -> void:
	await _flood(64 * 1024, 40)


func test_a_flood_of_1_mb_frames_is_refused_and_the_others_are_served() -> void:
	await _flood(1 << 20, 3)


func test_a_packet_of_the_largest_size_passes_and_one_byte_more_is_a_hang_up() -> void:
	var link := await _rig.connect_link()
	var id := _rig.ids[0]
	var gone: Array[int] = []
	_rig.listener.peer_disconnected.connect(func(peer: int) -> void: gone.append(peer))
	var largest := PackedByteArray()
	largest.resize(_rig.listener.max_packet_bytes)
	link.send(largest)
	assert_bool(await _rig.until(func() -> bool: return _rig.got[id].size() == 1)).is_true()
	largest.append(0)
	link.send(largest)
	link.send(PackedByteArray([1]))
	assert_bool(await _rig.until(func() -> bool: return gone == [id])).is_true()
	assert_int(_rig.got[id].size()).is_equal(1)
	assert_int(_rig.listener.oversize_packets).is_equal(1)
	assert_int(_rig.listener.close_code_of(id)).is_equal(WsListener.CLOSE_TOO_BIG)
	assert_bool(_rig.listener.left_on_purpose(id)).is_false()


func test_a_connection_that_never_finishes_its_handshake_is_dropped_after_3_s() -> void:
	_rig.listener.clock = func() -> float: return _now
	var tcp := StreamPeerTCP.new()
	_tcp.append(tcp)
	assert_int(tcp.connect_to_host("127.0.0.1", _rig.listener.port())).is_equal(OK)
	var waiting := await _rig.until(
		func() -> bool:
			tcp.poll()
			return _rig.listener.handshaking_count() == 1
	)
	assert_bool(waiting).is_true()
	_now = 2.9
	await _rig.wait(5)
	assert_int(_rig.listener.handshaking_count()).is_equal(1)
	_now = 3.1
	await _rig.wait(5)
	assert_int(_rig.listener.handshaking_count()).is_equal(0)
	var closed := await _rig.until(
		func() -> bool:
			tcp.poll()
			return tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED
	)
	assert_bool(closed).is_true()
	assert_int(_rig.listener.peer_count()).is_equal(0)


func test_a_peer_that_never_answers_the_goodbye_is_let_go_after_the_grace() -> void:
	_rig.listener.clock = func() -> float: return _now
	var link := await _rig.connect_link()
	var id := _rig.ids[0]
	# The client's loop is frozen: it never reads the server's close frame or answers it.
	_rig.links.erase(link)
	var gone: Array[int] = []
	_rig.listener.peer_disconnected.connect(func(peer: int) -> void: gone.append(peer))
	_rig.listener.disconnect_peer(id)
	# The close frame leaves after the linger, and the grace counts from there.
	_now = WsListener.CLOSE_LINGER
	await _rig.wait(2)
	assert_bool(_rig.listener.send(id, PackedByteArray([1]))).is_false()
	_now = WsListener.CLOSE_LINGER + 0.9
	await _rig.wait(5)
	assert_array(gone).is_empty()
	_now = WsListener.CLOSE_LINGER + 1.1
	await _rig.wait(2)
	assert_array(gone).is_equal([id])
	assert_int(_rig.listener.peer_count()).is_equal(0)


func test_ids_are_given_one_per_handshake_and_never_reused() -> void:
	var first := await _rig.connect_link()
	await _rig.connect_link()
	first.close()
	await _rig.until(func() -> bool: return _rig.listener.peer_count() == 1)
	await _rig.connect_link()
	assert_array(_rig.ids).is_equal([1, 2, 3])
	assert_int(_rig.listener.peer_count()).is_equal(2)
