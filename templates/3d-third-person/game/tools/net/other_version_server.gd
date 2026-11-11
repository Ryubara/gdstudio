## A game server of another version, for the teeth of the online probe
## (`tools/web_smoke/online.py --other-version`): it answers every HELLO as a server of
## `NetWire.VERSION + 1` would, with `REFUSED(version)`, and seats nobody. It prints the same
## `listening` line as `NetServer`, so a probe reads its port the same way.
##
## `<godot> --headless --path game -s res://tools/net/other_version_server.gd -- --port 0`
extends SceneTree

var _listener := WsListener.new()


func _initialize() -> void:
	var args := NetArgs.new()
	var at_port := args.get_int("port", WebSocketLink.DEFAULT_PORT)
	_listener.packet_received.connect(_on_packet)
	if _listener.listen(at_port) != OK:
		printerr("could not listen on %d" % at_port)
		quit(1)
		return
	print(JSON.stringify({"event": "listening", "port": _listener.port(), "version": _version()}))


func _physics_process(_delta: float) -> bool:
	_listener.poll()
	return false


func _on_packet(peer: int, data: PackedByteArray) -> void:
	if NetWire.type_of(data) != NetWire.Type.HELLO:
		return
	_listener.send(
		peer, PackedByteArray([NetWire.Type.REFUSED, NetWire.Refusal.VERSION, _version()])
	)
	print(JSON.stringify({"event": "refused", "reason": "VERSION", "version": data[1]}))


static func _version() -> int:
	return NetWire.VERSION + 1
