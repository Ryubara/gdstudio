class_name TcpRelay
extends RefCounted
## A TCP relay on 127.0.0.1 between one client and a server, for a test that needs the socket
## itself to misbehave: `poll` it once a frame and it passes the bytes each way; while `hold_down`
## is on it stops reading what the server sends, so the client's downlink stalls (the server's
## socket fills, then its `WsListener` buffer) while the client's commands still reach the server.
## A client that stops polling stops sending too, and the server hangs up on it after
## `NetServer.silent_seconds`: this is the client that stops reading and is still playing.

## While on, nothing from the server is read (what was read already still goes to the client).
var hold_down := false
## Bytes passed each way (WebSocket framing included).
var bytes_up := 0
var bytes_down := 0

var _listener := TCPServer.new()
var _target_port := 0
var _client: StreamPeerTCP
var _server := StreamPeerTCP.new()
var _to_server := PackedByteArray()
var _to_client := PackedByteArray()


## Listens on a free port for one client and joins it to `target_port`; the port, or 0.
func start(target_port: int) -> int:
	_target_port = target_port
	if _listener.listen(0, "127.0.0.1") != OK:
		return 0
	return _listener.get_local_port()


func url() -> String:
	return "ws://127.0.0.1:%d" % _listener.get_local_port()


func poll() -> void:
	if _client == null and _listener.is_connection_available():
		_client = _listener.take_connection()
		_server.connect_to_host("127.0.0.1", _target_port)
	if _client == null:
		return
	_client.poll()
	_server.poll()
	if _server.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var up := _read(_client)
	bytes_up += up.size()
	_to_server.append_array(up)
	_to_server = _write(_server, _to_server)
	if not hold_down:
		var down := _read(_server)
		bytes_down += down.size()
		_to_client.append_array(down)
	_to_client = _write(_client, _to_client)


func stop() -> void:
	if _client != null:
		_client.disconnect_from_host()
	_server.disconnect_from_host()
	_listener.stop()


# Packed arrays are passed by value: the bytes read are returned, not appended to an argument.
static func _read(from: StreamPeerTCP) -> PackedByteArray:
	var available := from.get_available_bytes()
	if available <= 0:
		return PackedByteArray()
	var got: Array = from.get_partial_data(available)
	return got[1] if got[0] == OK else PackedByteArray()


static func _write(to: StreamPeerTCP, pending: PackedByteArray) -> PackedByteArray:
	if pending.is_empty():
		return pending
	var sent: Array = to.put_partial_data(pending)
	if sent[0] != OK:
		return pending
	return pending.slice(int(sent[1]))
