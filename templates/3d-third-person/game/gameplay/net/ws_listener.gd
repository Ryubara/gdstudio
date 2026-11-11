class_name WsListener
extends RefCounted
## A game server's WebSocket listener (desktop and headless only: a web export cannot listen), built
## from `TCPServer` and `WebSocketPeer.accept_stream`. Each connection that completes its handshake
## gets an id (1, 2, 3...). Call `poll` once per physics tick; it fires the signals. Binary frames.
##
## What it was built to survive (Deadnight #483 and its hostile-client tests):
## - a client that stops reading: what waits for it may grow to `outbound_buffer`
##   (`NetLimits.BUFFER_SIZE`), then `send` returns false instead of dropping silently, so the game
##   sends a whole state next rather than a change against a packet that never left;
## - a packet bigger than `max_packet_bytes` is never passed on and its sender is hung up on at once
##   (1009, too big); a frame bigger than `INBOUND_BUFFER` (64 KB) the engine refuses itself; the
##   listener serves the others on;
## - a connection that never finishes its handshake is dropped after `HANDSHAKE_SECONDS`;
## - `disconnect_peer` lingers `close_linger` seconds before its close frame, because Godot's
##   `WebSocketPeer` throws away what reaches it in the same `poll` as a close (the last packets
##   before a goodbye, a refusal); a peer that then does not answer the closing handshake is let
##   go after `CLOSE_GRACE`.
## `left_on_purpose(id)` tells a goodbye (1000, 1001) from a network that went.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(peer_id: int, data: PackedByteArray)

## What a peer may have waiting to be read. A game's messages are small; a frame bigger than this is
## a hostile one the engine refuses.
const INBOUND_BUFFER := 1 << 16
## The engine's packet count limit, for both directions.
const MAX_QUEUED := 8192
## Seconds a connection has to finish its WebSocket handshake.
const HANDSHAKE_SECONDS := 3.0
## Seconds a peer has to answer the closing handshake before the listener lets go of it.
const CLOSE_GRACE := 1.0
## Seconds between `disconnect_peer` and the close frame, for the peer to read the last packets.
const CLOSE_LINGER := 0.25
## The largest packet a peer may send: a coarse guard under the protocol's own exact limits, which
## must hold its longest real message (a hello with the longest name or ticket).
const MAX_PACKET_BYTES := 4096
## The close code for a packet that is too big (RFC 6455).
const CLOSE_TOO_BIG := 1009

## Bytes in and out, all peers, for the numbers a run prints.
var bytes_in := 0
var bytes_out := 0
var packets_in := 0
var packets_out := 0
## Sends refused because a peer's buffer was full.
var refused_sends := 0
## Packets over `max_packet_bytes` that were dropped (and their senders hung up on).
var oversize_packets := 0

## Bytes that may wait to be sent to a peer that is not reading (`NetLimits.BUFFER_SIZE`; set it
## before peers come).
var outbound_buffer := NetLimits.BUFFER_SIZE
## Seconds a connection has to finish its handshake (`HANDSHAKE_SECONDS`).
var handshake_seconds := HANDSHAKE_SECONDS
## Seconds between `disconnect_peer` and its close frame (`CLOSE_LINGER`).
var close_linger := CLOSE_LINGER
## The largest packet a peer may send (`MAX_PACKET_BYTES`).
var max_packet_bytes := MAX_PACKET_BYTES
## Seconds from game start, for the handshake and closing deadlines (empty: the real clock).
var clock := Callable()

var _tcp := TCPServer.new()
## Connections still in their handshake, and when each began.
var _handshaking: Array[Dictionary] = []
var _peers: Dictionary[int, WebSocketPeer] = {}
var _next_id := 1
## Peers being hung up on whose close frame waits for its time, and its code.
var _lingering: Dictionary[int, Dictionary] = {}
## Peers whose close frame left, and when: let go after `CLOSE_GRACE`.
var _closing: Dictionary[int, float] = {}
var _close_codes: Dictionary[int, int] = {}


## Listens on `port` (0 picks a free one: read it with `port()`) at `bind_address`.
func listen(at_port: int, bind_address := "*") -> Error:
	return _tcp.listen(at_port, bind_address)


func is_listening() -> bool:
	return _tcp.is_listening()


## The port actually bound (useful after `listen(0)`).
func port() -> int:
	return _tcp.get_local_port()


func peer_count() -> int:
	return _peers.size()


## Connections that have not finished their handshake.
func handshaking_count() -> int:
	return _handshaking.size()


func peer_ids() -> Array[int]:
	return _peers.keys()


func poll() -> void:
	var now := _now()
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = INBOUND_BUFFER
		ws.max_queued_packets = MAX_QUEUED
		ws.outbound_buffer_size = outbound_buffer
		ws.accept_stream(_tcp.take_connection())
		_handshaking.append({"ws": ws, "since": now})
	for entry in _handshaking.duplicate():
		var ws: WebSocketPeer = entry["ws"]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_handshaking.erase(entry)
				var id := _next_id
				_next_id += 1
				_peers[id] = ws
				peer_connected.emit(id)
			WebSocketPeer.STATE_CLOSED:
				_handshaking.erase(entry)
			_:
				if now - float(entry["since"]) > handshake_seconds:
					_handshaking.erase(entry)
					ws.close()
	for id: int in _peers.keys():
		var ws := _peers[id]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var data := ws.get_packet()
			bytes_in += data.size()
			if _lingering.has(id) or _closing.has(id):
				continue
			if data.size() > max_packet_bytes:
				oversize_packets += 1
				disconnect_peer(id, CLOSE_TOO_BIG, 0.0)
				continue
			packets_in += 1
			packet_received.emit(id, data)
		if _lingering.has(id) and now >= float(_lingering[id]["at"]):
			ws.close(int(_lingering[id]["code"]))
			_lingering.erase(id)
			_closing[id] = now
		var gone := ws.get_ready_state() == WebSocketPeer.STATE_CLOSED
		if _closing.has(id) and now - _closing[id] > CLOSE_GRACE:
			gone = true
		if gone:
			_close_codes[id] = ws.get_close_code()
			_peers.erase(id)
			_lingering.erase(id)
			_closing.erase(id)
			peer_disconnected.emit(id)


## The close code the peer's socket ended with (-1 when no close frame came), kept after
## `peer_disconnected`.
func close_code_of(peer_id: int) -> int:
	return _close_codes.get(peer_id, NetLink.CLOSE_NONE)


## Whether the peer said goodbye on purpose (1000, or 1001 when a page closes).
func left_on_purpose(peer_id: int) -> bool:
	return NetLink.is_goodbye(close_code_of(peer_id))


## Sends a packet to a peer; false when it was not sent (no such peer, not open, or its buffer is
## full because it stopped reading: send a whole state next, not a change).
func send(peer_id: int, data: PackedByteArray) -> bool:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if _lingering.has(peer_id) or _closing.has(peer_id):
		return false
	if ws.get_current_outbound_buffered_amount() + data.size() > outbound_buffer:
		refused_sends += 1
		return false
	if ws.send(data, WebSocketPeer.WRITE_MODE_BINARY) != OK:
		refused_sends += 1
		return false
	bytes_out += data.size()
	packets_out += 1
	return true


## Hangs up on a peer (`code` 1000 is a goodbye): nothing more is sent to it or passed on from it,
## the close frame leaves after `linger` seconds (`close_linger` when negative) so the peer reads
## what was sent before, and `peer_disconnected` follows when it answers, or `CLOSE_GRACE` later.
func disconnect_peer(peer_id: int, code := NetLink.CLOSE_NORMAL, linger := -1.0) -> void:
	if not _peers.has(peer_id) or _lingering.has(peer_id) or _closing.has(peer_id):
		return
	var wait := close_linger if linger < 0.0 else linger
	var now := _now()
	if wait <= 0.0:
		_peers[peer_id].close(code)
		_closing[peer_id] = now
	else:
		_lingering[peer_id] = {"at": now + wait, "code": code}


## Stops listening and closes every connection.
func close() -> void:
	for ws: WebSocketPeer in _peers.values():
		ws.close()
	for entry in _handshaking:
		(entry["ws"] as WebSocketPeer).close()
	_peers.clear()
	_handshaking.clear()
	_lingering.clear()
	_closing.clear()
	_tcp.stop()


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_ticks_usec() / 1000000.0
