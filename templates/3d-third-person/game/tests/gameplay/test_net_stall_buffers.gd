# A client whose loop froze reads nothing for seconds, and what the server sent meanwhile must all
# be there when it reads again (Deadnight #483: the engine's 64 KB buffers dropped the newest
# ticks); and when a peer's buffer is full, the server's send says so instead of losing the packet.
extends GdUnitTestSuite

## 35 KB a second at 60 ticks (a busy game's ticks), for 5 seconds.
const PER_TICK := 584
const TICKS := 300

var _rig: SocketRig


func before_test() -> void:
	_rig = SocketRig.new(get_tree())
	assert_bool(_rig.start()).is_true()


func after_test() -> void:
	_rig.stop()


## Sends five seconds of ticks (one a physics frame) while the link does not poll, then lets it
## read. How many reached it in order, and how many the listener's send refused.
func _frozen_client_reads(link: WebSocketLink) -> Vector2i:
	var id := _rig.ids[-1]
	var read: Array[PackedByteArray] = []
	link.packet_received.connect(func(data: PackedByteArray) -> void: read.append(data))
	_rig.links.erase(link)
	var sent := 0
	for i in TICKS:
		if _rig.listener.send(id, SocketRig.numbered(sent, PER_TICK)):
			sent += 1
		_rig.listener.poll()
		await get_tree().physics_frame
	_rig.links.append(link)
	await _rig.until(func() -> bool: return read.size() >= sent, 60)
	var in_order := read.size()
	for i in read.size():
		if read[i].decode_u32(0) != i:
			in_order = i
			break
	return Vector2i(in_order, TICKS - sent)


func test_a_client_that_reads_nothing_for_5_s_loses_no_packet_of_35_kb_a_second() -> void:
	var link := await _rig.connect_link()
	var began := Engine.get_physics_frames()
	var result := await _frozen_client_reads(link)
	assert_int(Engine.get_physics_frames() - began).is_greater_equal(TICKS)
	(
		assert_int(result.x)
		. override_failure_message(
			"only %d of %d ticks reached the client in order" % [result.x, TICKS]
		)
		. is_equal(TICKS)
	)
	assert_int(result.y).is_equal(0)


func test_the_buffers_are_the_sizes_that_held_a_frozen_client() -> void:
	# A localhost test cannot show the engine's 64 KB default failing: the kernel's loopback buffers
	# took some 200 KB more before a send was refused (multiplayer.md#template-transport). Deadnight
	# met it on a real network and in the browser (#483, #502), so the sizes are pinned here.
	var link := await _rig.connect_link()
	assert_int(link._ws.inbound_buffer_size).is_equal(1 << 20)
	assert_int(link._ws.max_queued_packets).is_equal(8192)
	var server_side: WebSocketPeer = _rig.listener._peers[_rig.ids[0]]
	assert_int(server_side.outbound_buffer_size).is_equal(1 << 20)
	assert_int(server_side.inbound_buffer_size).is_equal(1 << 16)
	assert_int(server_side.max_queued_packets).is_equal(8192)


func test_the_servers_send_says_no_when_a_peers_buffer_is_full() -> void:
	_rig.listener.outbound_buffer = 16 * 1024
	var link := await _rig.connect_link()
	_rig.links.erase(link)
	var id := _rig.ids[0]
	var taken := 0
	var refused := false
	# Up to 20 MB: more than any kernel buffers, so the refusal is the listener's.
	for i in 20000:
		if _rig.listener.send(id, SocketRig.numbered(i, 1024)):
			taken += 1
		else:
			refused = true
			break
		_rig.listener.poll()
	assert_bool(refused).is_true()
	assert_int(_rig.listener.refused_sends).is_equal(1)
	# The kernel's buffers took some, the listener's 16 KB the rest, and nothing past them.
	print("SEND_FULL taken %d KB before the refusal" % taken)
	assert_int(taken).is_greater(16)
	# Every packet the send took is delivered once the client reads.
	var read := [0]
	link.packet_received.connect(func(_data: PackedByteArray) -> void: read[0] += 1)
	_rig.links.append(link)
	assert_bool(await _rig.until(func() -> bool: return read[0] >= taken, 120)).is_true()
	assert_int(read[0]).is_equal(taken)
