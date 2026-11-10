## Bots that play against a running game server (`godot --headless --path game -- --server`) over
## real sockets, for a check of a server in its own process (a local run, the Docker image, a
## deployment): each says hello, sends `ServerBench.canned_command` every physics tick and a ping
## twice a second, and reads every TICK. After `--seconds` it prints one line of JSON that starts
## with `SERVER_BOT`: for each bot its slot, the TICKs and players it saw, the last `ack` against
## the last command sent, the round trip, and the bytes each way a second; then it says goodbye
## and quits (exit 1 when a bot was never welcomed).
##
## `<godot> --headless --path game -s res://tools/net/server_bot.gd -- --connect
## ws://127.0.0.1:8910 --bots 2 --seconds 10`. It lives in tools/, which the export leaves out.
extends SceneTree

var _links: Array[WebSocketLink] = []
var _bots: Array[Dictionary] = []
var _tick := 0
var _end_tick := 0
var _closing_until := -1


func _initialize() -> void:
	var args := NetArgs.new()
	var url := args.get_string("connect", "ws://127.0.0.1:%d" % WebSocketLink.DEFAULT_PORT)
	var count := clampi(args.get_int("bots", 1), 1, NetLimits.MAX_PLAYERS)
	_end_tick = args.get_int("seconds", 10) * NetLimits.TICK_RATE
	for index in count:
		var link := WebSocketLink.new()
		link.connect_to_url(url)
		link.connected.connect(_on_connected.bind(index))
		link.packet_received.connect(_on_packet.bind(index))
		_links.append(link)
		(
			_bots
			. append(
				{
					"slot": -1,
					"refused": -1,
					"ticks": 0,
					"players": 0,
					"ack": 0,
					"sent": 0,
					"rtt_ms": -1,
				}
			)
		)


func _physics_process(_delta: float) -> bool:
	_tick += 1
	for index in _links.size():
		var link := _links[index]
		link.poll()
		var bot := _bots[index]
		if _closing_until < 0 and link.is_open() and bot["slot"] >= 0:
			var command := ServerBench.canned_command(index, _tick)
			if link.send(CommandCodec.encode(command)):
				bot["sent"] = command.seq
			if _tick % (NetLimits.TICK_RATE / NetLimits.PING_RATE) == 0:
				link.send(NetWire.ping(Time.get_ticks_msec(), bot["rtt_ms"]))
	if _closing_until < 0 and _tick >= _end_tick:
		_report()
		for link in _links:
			link.close()
		_closing_until = _tick + NetLimits.TICK_RATE
	if _closing_until >= 0 and _tick >= _closing_until:
		var welcomed := _bots.all(func(bot: Dictionary) -> bool: return bot["slot"] >= 0)
		quit(0 if welcomed else 1)
	return false


func _report() -> void:
	var seconds := float(_end_tick) / NetLimits.TICK_RATE
	for index in _bots.size():
		var link := _links[index]
		_bots[index]["down_bytes_per_s"] = roundi(link.bytes_in / seconds)
		_bots[index]["up_bytes_per_s"] = roundi(link.bytes_out / seconds)
	print("SERVER_BOT ", JSON.stringify({"seconds": seconds, "bots": _bots}))


func _on_connected(index: int) -> void:
	_links[index].send(NetWire.hello("Bot%d" % index, NetServer.world_hash_of(root)))


func _on_packet(data: PackedByteArray, index: int) -> void:
	var bot := _bots[index]
	match NetWire.type_of(data):
		NetWire.Type.WELCOME:
			var welcome := SnapshotCodec.read_welcome(data)
			bot["slot"] = welcome.slot if welcome != null else -1
		NetWire.Type.REFUSED:
			bot["refused"] = NetWire.read_refused(data)
		NetWire.Type.TICK:
			var tick := SnapshotCodec.read_tick(data)
			if tick != null:
				bot["ticks"] += 1
				bot["ack"] = tick.ack
				bot["players"] = tick.players.size()
		NetWire.Type.PONG:
			var pong := NetWire.read_pong(data)
			if pong != null:
				bot["rtt_ms"] = (Time.get_ticks_msec() - pong.client_ms) & 0xFFFFFFFF
