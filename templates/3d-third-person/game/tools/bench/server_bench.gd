class_name ServerBench
extends Node
## What a game server's step costs: a `NetServer` in the template's map with `bodies` clients on
## real sockets of 127.0.0.1, each sending one canned command a tick (a circle with sprint, a
## jump every three seconds, a crouched stretch, an aimed stretch), for `ticks` steps once every
## client is seated. It times the server's own step (`NetServer.last_step_ms`: the listener, the
## bodies, the TICKs), not the clients beside it, and counts the bytes each way.
##
## Run it headless on the desktop:
## `godot --headless --fixed-fps 60 --path game res://tools/bench/server_bench.tscn -- --bodies=8`
## (`--ticks=N` too). It prints one line of JSON that starts with `SERVER_BENCH` and quits;
## `test_net_server_cost.gd` runs it with 8 bodies and fails above `NetServer.STEP_BUDGET_MS` p95.

## Said once the run is measured, with what it printed.
signal finished(result: Dictionary)

const WORLD := "res://world/world.tscn"

## Clients, each with a body on the server.
@export_range(1, NetLimits.MAX_PLAYERS) var bodies := 8
## Steps measured once all are seated.
@export var ticks := 1200
## Runs in the template's map (off: a bare floor).
@export var in_the_map := true
## Quits when done (a test turns it off and reads `finished`).
@export var quit_when_done := true

var server: NetServer
var result: Dictionary = {}

var _links: Array[WebSocketLink] = []
var _welcomed: Array[bool] = []
var _seq := 0
var _measuring := false
var _measured := 0
var _bytes_at := Vector2i.ZERO


func _ready() -> void:
	var args := NetArgs.new()
	bodies = clampi(args.get_int("bodies", bodies), 1, NetLimits.MAX_PLAYERS)
	ticks = maxi(args.get_int("ticks", ticks), 1)
	if in_the_map:
		add_child((load(WORLD) as PackedScene).instantiate())
	else:
		var floor_body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(200.0, 1.0, 200.0)
		shape.shape = box
		floor_body.add_child(shape)
		floor_body.position = Vector3(0.0, -0.5, 0.0)
		add_child(floor_body)
	server = NetServer.new()
	server.port = 0
	server.bind_address = "127.0.0.1"
	server.print_log = false
	server.clock = _frame_clock
	add_child(server)
	for index in bodies:
		var link := WebSocketLink.new()
		link.clock = _frame_clock
		link.connect_to_url("ws://127.0.0.1:%d" % server.listener.port())
		link.connected.connect(_on_connected.bind(index))
		link.packet_received.connect(_on_packet.bind(index))
		_links.append(link)
		_welcomed.append(false)


func _physics_process(_delta: float) -> void:
	for index in _links.size():
		var link := _links[index]
		link.poll()
		if link.is_open() and _welcomed[index]:
			link.send(CommandCodec.encode(canned_command(index, _seq)))
	_seq += 1
	if not _measuring and server.player_count() == bodies:
		_measuring = true
		server.keep_step_times = true
		server.step_times.clear()
		_bytes_at = Vector2i(server.listener.bytes_in, server.listener.bytes_out)
	elif _measuring and result.is_empty():
		_measured += 1
		if _measured > ticks:
			_report()


func _exit_tree() -> void:
	for link in _links:
		link.close()
		link.poll()
	_links.clear()


func _on_connected(index: int) -> void:
	_links[index].send(NetWire.hello("Bot%d" % index, server.world_hash))


func _on_packet(data: PackedByteArray, index: int) -> void:
	if NetWire.type_of(data) == NetWire.Type.WELCOME:
		_welcomed[index] = true


## The command bot `index` sends on tick `tick` (numbered `tick + 1`): each walks its own circle,
## out of phase (`tools/net/server_bot.gd` sends the same).
static func canned_command(index: int, tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.seq = tick + 1
	var phase := tick + index * 37
	command.yaw = phase * 0.01 + index
	command.move = Vector2(0.2, 1.0).normalized()
	command.sprint = phase % 600 < 300
	command.jump_pressed = phase % 180 == 0
	command.jump = phase % 180 < 20
	command.crouch = phase % 600 >= 450
	command.aim = phase % 600 >= 300 and phase % 600 < 450
	command.pitch = sin(phase * 0.02) * 0.4
	return command


func _report() -> void:
	var sorted := server.step_times.slice(0, ticks)
	sorted.sort()
	var over_budget := 0
	var over_tick := 0
	for ms in sorted:
		over_budget += 1 if ms > NetServer.STEP_BUDGET_MS else 0
		over_tick += 1 if ms > 1000.0 / NetLimits.TICK_RATE else 0
	var seconds := float(ticks) / NetLimits.TICK_RATE
	var bytes_in := server.listener.bytes_in - _bytes_at.x
	var bytes_out := server.listener.bytes_out - _bytes_at.y
	result = {
		"bodies": bodies,
		"ticks": ticks,
		"in_the_map": in_the_map,
		"step_ms_p50": snappedf(NetServer.percentile(sorted, 0.5), 0.001),
		"step_ms_p95": snappedf(NetServer.percentile(sorted, 0.95), 0.001),
		"step_ms_max": snappedf(sorted[-1], 0.001),
		"steps_over_budget": over_budget,
		"steps_over_tick": over_tick,
		"down_bytes_per_s_per_client": roundi(bytes_out / seconds / bodies),
		"up_bytes_per_s_per_client": roundi(bytes_in / seconds / bodies),
		"static_memory_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
	}
	print("SERVER_BENCH ", JSON.stringify(result))
	finished.emit(result)
	if quit_when_done:
		get_tree().quit()


static func _frame_clock() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
