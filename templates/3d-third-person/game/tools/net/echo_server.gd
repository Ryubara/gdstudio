## A bare game-server stand-in for probes of the transport (`tools/web_smoke/net_link_smoke.py`): a
## `WsListener` that sends every packet back to its sender. With `--stream <bytes>`, a peer that
## sends the one byte `0x01` is from then on sent a numbered packet of that size every physics tick
## (the first four bytes count up from 0), as a busy game's ticks would. It prints
## `LISTENING <port>` once it listens, `LEFT` for each peer that goes, and every few seconds `STATS`
## with its counters; it stops on the one byte `0xFF`, or when killed.
##
## Run it headless from a game made from the template:
## `<godot> --headless --path game -s res://tools/net/echo_server.gd -- --port 0 --stream 584`
## (`--port 0` takes a free port: read it from the first line). On Windows the console build is a
## wrapper that starts the real program, so stop it with `taskkill /T /F /PID <pid>`.
## It lives in tools/, which the export leaves out.
extends SceneTree

const STATS_EVERY := 300

var _listener := WsListener.new()
var _stream_bytes := 0
## Packets streamed to each peer that asked for the stream.
var _streamed: Dictionary[int, int] = {}
var _ticks := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at_port := WebSocketLink.DEFAULT_PORT
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			at_port = int(args[i + 1])
		elif args[i] == "--stream" and i + 1 < args.size():
			_stream_bytes = int(args[i + 1])
	_listener.peer_disconnected.connect(_on_left)
	_listener.packet_received.connect(_on_packet)
	var err := _listener.listen(at_port)
	if err != OK:
		printerr("could not listen on %d: %s" % [at_port, error_string(err)])
		quit(1)
		return
	print("LISTENING %d" % _listener.port())


func _physics_process(_delta: float) -> bool:
	_listener.poll()
	if _stream_bytes > 0:
		for id: int in _streamed.keys():
			if _listener.send(id, _numbered(_streamed[id], _stream_bytes)):
				_streamed[id] += 1
	_ticks += 1
	if _ticks % STATS_EVERY == 0:
		print(
			(
				"STATS peers=%d in=%d out=%d refused=%d"
				% [
					_listener.peer_count(),
					_listener.bytes_in,
					_listener.bytes_out,
					_listener.refused_sends
				]
			)
		)
	return false


func _on_packet(id: int, data: PackedByteArray) -> void:
	if data.size() == 1 and data[0] == 0xFF:
		print("STOP asked by peer %d" % id)
		_listener.close()
		quit(0)
		return
	if data.size() == 1 and data[0] == 0x01:
		_streamed[id] = 0
		return
	_listener.send(id, data)


func _on_left(id: int) -> void:
	print(
		(
			"LEFT %d code=%d on_purpose=%s streamed=%d"
			% [id, _listener.close_code_of(id), _listener.left_on_purpose(id), _streamed.get(id, 0)]
		)
	)
	_streamed.erase(id)


## A packet whose first four bytes are `index`, the rest filler that does not pack.
static func _numbered(index: int, size: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(maxi(size, 4))
	for i in range(4, data.size()):
		data[i] = (index * 31 + i * 7) & 0xFF
	data.encode_u32(0, index)
	return data
