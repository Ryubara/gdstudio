class_name OnlineRig
extends Node
## A game server and its clients in one process, each in a `SubViewport` with a `World3D` of its
## own, so every side moves its bodies against its own copy of the map as separate machines would:
## the server is `net_server.tscn` (the map and a `NetServer`), each client is
## `tests/fixtures/online_arena.tscn` (the map, a `PlayerRig`, `RemotePlayers` and a `NetClient`)
## with a `ScriptedController` in place of its `PlayerInput`. `loopback` joins every client through
## a `LoopbackListener` (lockstep: a packet is read the tick after it is sent); otherwise over a
## real socket on 127.0.0.1. Every clock is the physics frame count. Free it with `auto_free`.
## In a run that draws, `join` also draws the new screen's reflection probes to the end at once, so
## a capture never films a body dark from a probe still drawing (`ProbeSettle`).

const SERVER_SCENE := "res://gameplay/net/net_server.tscn"
const ARENA_SCENE := "res://tests/fixtures/online_arena.tscn"

var server: NetServer
var server_view: SubViewport
var loopback := true
var clients: Array[NetClient] = []
var views: Array[SubViewport] = []
var controllers: Array[ScriptedController] = []
## Wraps each client's link in a `LinkConditioner` of this many seconds each way (0: none).
var delay := 0.0
var jitter := 0.0
## The size of each client's view (a capture reads it).
var view_size := Vector2i(320, 180)
## Called with the server scene, and with each client's arena, before it enters the tree (a test
## changes the map there).
var prepare_server := Callable()
var prepare_arena := Callable()


func _init(use_loopback := true) -> void:
	loopback = use_loopback


## Adds the server (it listens in its `_ready`); false when it is not listening.
func start() -> bool:
	server_view = _view("ServerView")
	server = (load(SERVER_SCENE) as PackedScene).instantiate() as NetServer
	server.port = 0
	server.bind_address = "127.0.0.1"
	server.cap_frame_rate = false
	server.print_log = false
	server.keep_history = true
	server.clock = SocketRig.frame_clock
	if loopback:
		server.listener = LoopbackListener.new()
	if prepare_server.is_valid():
		prepare_server.call(server)
	server_view.add_child(server)
	return server.listener.is_listening()


## A client in a view of its own, joined as `player_name` (null when it was not welcomed in
## `frames`).
func join(player_name: String, frames := 240) -> NetClient:
	var view := _view("Client%d" % clients.size())
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	_own_cameras(arena, clients.size())
	if prepare_arena.is_valid():
		prepare_arena.call(arena)
	view.add_child(arena)
	var client := arena.get_node("NetClient") as NetClient
	client.player_name = player_name
	client.clock = SocketRig.frame_clock
	controllers.append(ScriptedController.install(client.player))
	clients.append(client)
	views.append(view)
	var link: NetLink
	if loopback:
		link = (server.listener as LoopbackListener).open_link()
	else:
		var socket := WebSocketLink.new()
		socket.clock = SocketRig.frame_clock
		if socket.connect_to_url("ws://127.0.0.1:%d" % server.listener.port()) != OK:
			return null
		link = socket
	if delay > 0.0 or jitter > 0.0:
		var conditioner := LinkConditioner.new(link, delay, jitter, clients.size())
		conditioner.clock = SocketRig.frame_clock
		link = conditioner
	client.join_with(link)
	var welcomed := await until(func() -> bool: return client.is_seated(), frames)
	await settle(view)
	return client if welcomed else null


## Draws the reflection probes of `view`'s world to the end now, within this frame, so no frame
## a capture records shows one half drawn (`ProbeSettle`; nothing to do in a headless run). `join`
## calls it for each client's screen; a capture calls it for `server_view` after giving the
## server's world a camera.
func settle(view: Viewport) -> void:
	if ProbeSettle.draws_nothing():
		return
	# Drawn once first, so its camera has seen its probes.
	await get_tree().process_frame
	ProbeSettle.draw_through(ProbeSettle.probes_to_draw([view]))


## Waits physics frames until `condition` holds; false after `frames`.
func until(condition: Callable, frames := 120) -> bool:
	for _i in frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


## The server's body of `client`'s player.
func server_body(client: NetClient) -> Character:
	return server.body_at(client.slot)


# Phantom Camera's hosts pick from every Phantom Camera in the process, whatever its viewport: give
# each client's host and cameras a host layer of their own, or every client's screen shows the view
# of the last camera added (camera.md#phantom-camera).
static func _own_cameras(arena: Node, index: int) -> void:
	var layer := 1 << (index % 32)
	for node in arena.find_children("*", "", true, false):
		if node is PhantomCameraHost or node is PhantomCamera3D:
			node.set(&"host_layers", layer)


func _view(view_name: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.own_world_3d = true
	view.size = view_size
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	return view
