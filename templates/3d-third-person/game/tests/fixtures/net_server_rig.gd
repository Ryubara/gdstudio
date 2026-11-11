class_name NetServerRig
extends Node3D
## A `NetServer` on a free port of 127.0.0.1 in a small world of its own (a 60 m floor with its top
## at y = 0 and three player spawn points), and the `HandClient`s a test connects to it. Every
## clock is the physics frame count (`SocketRig.frame_clock`), so at `--fixed-fps 60` its seconds
## pass in frames. Free it with `auto_free`.
##
## Order inside a frame: a test's `await physics_frame` resumes before the nodes' own
## `_physics_process`, so what a test sends after the await is read by the server's step of the
## same frame when the socket has delivered it.

const SPAWN_SCENE := "res://gameplay/spawn_point/spawn_point.tscn"
## The spawn points, in node-path order (`Spawn0`, `Spawn1`, `Spawn2`), facing -Z.
const SPAWNS: Array[Vector3] = [
	Vector3(-6.0, 0.0, 10.0), Vector3(0.0, 0.0, 10.0), Vector3(6.0, 0.0, 10.0)
]

var server: NetServer
var clients: Array[HandClient] = []
## The log lines the server said: `{"event": ..., more fields}`.
var lines: Array[Dictionary] = []


## Builds the world and the server (not yet listening: `add_child` the rig, then `start`).
func _init(configure := Callable()) -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	for index in SPAWNS.size():
		var point := (load(SPAWN_SCENE) as PackedScene).instantiate() as SpawnPoint
		point.name = "Spawn%d" % index
		point.position = SPAWNS[index]
		add_child(point)
	server = NetServer.new()
	server.port = 0
	server.bind_address = "127.0.0.1"
	server.print_log = false
	server.keep_history = true
	server.clock = SocketRig.frame_clock
	server.logged.connect(_on_logged)
	if configure.is_valid():
		configure.call(server)


## Adds the server (it listens in its `_ready`); false when it is not listening.
func start() -> bool:
	add_child(server)
	return server.listener.is_listening()


func url() -> String:
	return "ws://127.0.0.1:%d" % server.listener.port()


## A client connected and open, not yet greeted (null when it did not open in two seconds).
func connect_client() -> HandClient:
	var client := HandClient.new(SocketRig.frame_clock)
	if client.link.connect_to_url(url()) != OK:
		return null
	clients.append(client)
	var opened := await until(func() -> bool: return client.link.is_open())
	return client if opened else null


## A client connected and welcomed as `player_name` (null when it was not).
func join(player_name: String) -> HandClient:
	var client := await connect_client()
	if client == null:
		return null
	client.say_hello(player_name, server.world_hash)
	var welcomed := await until(func() -> bool: return client.welcome != null)
	return client if welcomed else null


## Waits physics frames, polling every client, until `condition` holds; false after `frames`.
func until(condition: Callable, frames := 120) -> bool:
	for _i in frames:
		pump()
		if condition.call():
			return true
		await get_tree().physics_frame
	pump()
	return condition.call()


func wait(frames: int) -> void:
	for _i in frames:
		pump()
		await get_tree().physics_frame


func pump() -> void:
	for client in clients:
		client.poll()


## The lines of one event.
func lines_of(event: String) -> Array[Dictionary]:
	return lines.filter(func(line: Dictionary) -> bool: return line["event"] == event)


func _exit_tree() -> void:
	for client in clients:
		client.release()
	clients.clear()


func _on_logged(event: String, fields: Dictionary) -> void:
	var line := {"event": event}
	line.merge(fields)
	lines.append(line)
