class_name LoopbackListener
extends WsListener
## A `NetServer`'s listener with no socket: each `open_link()` gives a client end of a
## `LoopbackLink` pair, and the server end is a peer of this listener. A packet sent in one tick is
## read in the next, every time, so a server and its clients in one process step in lockstep (a
## test that must not depend on the machine's timing, a game whose server runs inside it). Give it
## to the server before the server enters the tree: `server.listener = LoopbackListener.new()`.

var _listening := false
var _ends: Dictionary[int, LoopbackLink] = {}
var _waiting: Array[int] = []
var _goodbyes: Dictionary[int, bool] = {}


func listen(_at_port: int, _bind_address := "*") -> Error:
	_listening = true
	return OK


func is_listening() -> bool:
	return _listening


func port() -> int:
	return 0


func peer_count() -> int:
	return _ends.size()


func peer_ids() -> Array[int]:
	return _ends.keys()


## The client end of a new connection; the server hears of it on its next poll.
func open_link() -> LoopbackLink:
	var pair := LoopbackLink.pair()
	var id := _next_id
	_next_id += 1
	var server_end := pair[1]
	server_end.packet_received.connect(_on_end_packet.bind(id))
	_ends[id] = server_end
	_waiting.append(id)
	return pair[0]


func poll() -> void:
	for id in _waiting:
		peer_connected.emit(id)
	_waiting.clear()
	for id: int in _ends.keys():
		var end := _ends[id]
		end.poll()
		if not end.is_open():
			_goodbyes[id] = NetLink.is_goodbye(end.close_code())
			_ends.erase(id)
			peer_disconnected.emit(id)


func left_on_purpose(peer_id: int) -> bool:
	return _goodbyes.get(peer_id, false)


func send(peer_id: int, data: PackedByteArray) -> bool:
	var end: LoopbackLink = _ends.get(peer_id)
	if end == null or not end.send(data):
		return false
	bytes_out += data.size()
	packets_out += 1
	return true


func disconnect_peer(peer_id: int, _code := NetLink.CLOSE_NORMAL, _linger := -1.0) -> void:
	var end: LoopbackLink = _ends.get(peer_id)
	if end != null:
		end.close()


func close() -> void:
	for end: LoopbackLink in _ends.values():
		end.close()
	_ends.clear()
	_listening = false


func _on_end_packet(data: PackedByteArray, peer_id: int) -> void:
	bytes_in += data.size()
	packets_in += 1
	packet_received.emit(peer_id, data)
