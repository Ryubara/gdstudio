class_name SocketRig
extends RefCounted
## A server and clients over real sockets on 127.0.0.1 for the network suites: a `WsListener` on a
## free port (`listen(0)`, so suites in parallel never clash), `WebSocketLink`s connected to it, and
## waits counted in physics frames. Every packet a peer sends to the listener is kept in `got`.

var listener := WsListener.new()
var links: Array[WebSocketLink] = []
## The ids the listener gave, in the order the handshakes finished.
var ids: Array[int] = []
## What reached the listener, by peer id.
var got: Dictionary[int, Array] = {}
## Whether the listener's `poll` runs inside `until` (a test sets it false to starve the server).
var poll_listener := true

var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree
	listener.peer_connected.connect(_on_peer)
	listener.packet_received.connect(_on_packet)


## Listens on a free port; false when it could not.
func start() -> bool:
	return listener.listen(0, "127.0.0.1") == OK


func url() -> String:
	return "ws://127.0.0.1:%d" % listener.port()


## A link connected to the listener and open (null when it did not open in two seconds of frames).
func connect_link(inbound_buffer := WebSocketLink.INBOUND_BUFFER) -> WebSocketLink:
	var link := WebSocketLink.new()
	link.inbound_buffer = inbound_buffer
	if link.connect_to_url(url()) != OK:
		return null
	links.append(link)
	var before := ids.size()
	var opened := await until(func() -> bool: return link.is_open() and ids.size() > before)
	return link if opened else null


## Waits physics frames, polling the listener and every link, until `condition` holds; false after
## `frames` frames.
func until(condition: Callable, frames := 120) -> bool:
	for _i in frames:
		pump()
		if condition.call():
			return true
		await _tree.physics_frame
	pump()
	return condition.call()


## Waits `frames` physics frames, polling as `until` does.
func wait(frames: int) -> void:
	for _i in frames:
		pump()
		await _tree.physics_frame


func pump() -> void:
	if poll_listener:
		listener.poll()
	for link in links:
		link.poll()


func stop() -> void:
	for link in links:
		link.close()
	listener.close()


## The physics frame count over the tick rate: the clock the network suites give a link.
static func frame_clock() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


## A packet whose first four bytes are `index`, padded to `size` with bytes that do not pack.
static func numbered(index: int, size := 8) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(maxi(size, 4))
	for i in range(4, data.size()):
		data[i] = (index * 31 + i * 7) & 0xFF
	data.encode_u32(0, index)
	return data


func _on_peer(peer_id: int) -> void:
	ids.append(peer_id)
	got[peer_id] = []


func _on_packet(peer_id: int, data: PackedByteArray) -> void:
	got[peer_id].append(data)
