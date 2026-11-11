## A predicting client that plays against a running game server (`godot --headless --path game --
## --server`) in its own process: the template's map, a `Player` stepped by a `NetClient`, the
## other players drawn by `RemotePlayers`. It walks circles round where it started, sprints every
## other lap and jumps every three seconds; with `--freeze` it stops its own thread (the frozen
## tab of `multiplayer.md#a-client-that-freezes-measured-on-the-live-server`) at the given seconds
## for the given milliseconds. After `--seconds` it stands still two seconds and prints one line of
## JSON that starts with `PREDICT_BOT`: the reconciler's corrections, snaps, losses and worst
## error, the gap to its own entry in the last TICK, the stalls and skipped ticks, the puppets
## drawn and how often they starved, the round trip, what the client costs a physics step, and the
## shots, hits and deaths it played from the server's events (`combat`), and `by_second`: for
## each second after the WELCOME the metres corrected and the snaps, and at its end where the
## body stood, the gap to the last TICK, the commands not yet answered, the round trip, the last
## command's number and the last TICK's `ack` and tick, so a failed gate shows when and where it
## went wrong (`tools/net/bad_network_gate.py`).
##
## `<godot> --headless --path game -s res://tools/net/predict_bot.gd -- --connect
## ws://127.0.0.1:8910 --seconds 30 [--delay-ms 100] [--freeze 8:500,16:2000,24:5000]`; a
## `--delay-ms` holds each packet that long each way inside the client (`LinkConditioner`), or
## put `tools/net/relay.py` between it and the server for a delay on the socket itself.
## `--centre x,z` circles round that point of the map instead of where the body started,
## `--radius r` and `--lap s` set the circle's size (metres) and a lap's seconds, and `--no-sprint`
## runs every lap: the gate keeps the walk on the spawn dais's flat top, off its 1 m edge
## (gdstudio #1110). `--break reconciler` plays with the Deadnight #483 fix
## taken out of the reconciler (the teeth check of `tools/net/bad_network_gate.py`). The plan is
## `CirclingController`'s and the line is `NetPlayReport`'s, the browser probe's own
## (`NetPlayProbe`).
extends SceneTree

const WORLD := "res://world/world.tscn"
const PLAYER := "res://gameplay/player/player.tscn"
## Seconds standing still at the end before the gap is read.
const SETTLE_SECONDS := 2.0


## The reconciler with the Deadnight #483 fix taken out (`--break reconciler`, for the gate's teeth
## check, `tools/net/bad_network_gate.py --break reconciler`): a correction does not move the
## remembered points of the unanswered commands, so each answer counts it again.
class UnshiftedReconciler:
	extends Reconciler

	func _shift(_by: Vector3) -> void:
		pass


var _client: NetClient
var _remote: RemotePlayers
var _ai: AiReplica
var _bot: CirclingController
var _seconds := 30.0
var _freezes: Dictionary[int, int] = {}
var _tick := 0
var _end_tick := 0
var _puppet_us := PackedInt32Array()
var _most_puppets := 0
var _started := false
var _centre := Vector3.INF
var _by_second: Array[Dictionary] = []
var _second_from := {"corrected": 0.0, "snaps": 0}


func _initialize() -> void:
	var args := NetArgs.new()
	_seconds = float(args.get_int("seconds", 30))
	for pair in args.get_string("freeze", "").split(",", false):
		var parts := pair.split(":")
		if parts.size() == 2:
			_freezes[roundi(float(parts[0]) * NetLimits.TICK_RATE)] = int(parts[1])
	var holder := Node3D.new()
	holder.name = "Online"
	root.add_child(holder)
	var world := (load(WORLD) as PackedScene).instantiate()
	holder.add_child(world)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	player.start_at_spawn = false
	var input := player.get_node("PlayerInput")
	player.remove_child(input)
	input.free()
	_bot = CirclingController.new()
	_bot.seconds = _seconds
	_bot.radius = float(args.get_string("radius", str(_bot.radius)))
	_bot.lap_seconds = float(args.get_string("lap", str(_bot.lap_seconds)))
	_bot.sprints = not args.has("no-sprint")
	var centre := args.get_string("centre").split(",", false)
	if centre.size() == 2:
		_centre = Vector3(float(centre[0]), 0.0, float(centre[1]))
	_bot.body = player
	player.add_child(_bot)
	player.controller = _bot
	holder.add_child(player)
	_remote = RemotePlayers.new()
	holder.add_child(_remote)
	# The server's AI characters, drawn and timed (gdstudio #970).
	_ai = AiReplica.new()
	_ai.name = "AiReplica"
	_ai.keep_times = true
	holder.add_child(_ai)
	_client = NetClient.new()
	_client.join_on_ready = false
	_client.player = player
	_client.remote_players = _remote
	_client.ai_replica = _ai
	_client.world_root = world
	_client.player_name = args.get_string("name", "Predictor")
	_client.keep_frame_times = true
	if args.get_string("break") == "reconciler":
		_client.reconciler = UnshiftedReconciler.new()
	holder.add_child(_client)
	_client.welcomed.connect(_on_welcomed)
	var socket := WebSocketLink.new()
	var url := args.get_string("connect", "ws://127.0.0.1:%d" % WebSocketLink.DEFAULT_PORT)
	if socket.connect_to_url(url) != OK:
		print("PREDICT_BOT ", JSON.stringify({"error": "cannot connect", "url": url}))
		quit(1)
		return
	var delay := args.get_int("delay-ms", 0) / 1000.0
	_client.join_with(LinkConditioner.new(socket, delay) if delay > 0.0 else socket)
	_end_tick = roundi((_seconds + SETTLE_SECONDS) * NetLimits.TICK_RATE)


func _physics_process(_delta: float) -> bool:
	if not _started:
		if _tick > 10 * NetLimits.TICK_RATE:
			print("PREDICT_BOT ", JSON.stringify({"error": "never welcomed"}))
			quit(1)
		_tick += 1
		return false
	_tick += 1
	_puppet_us.append(_remote.last_frame_us)
	_most_puppets = maxi(_most_puppets, _remote.slots().size())
	if _tick % NetLimits.TICK_RATE == 0:
		_note_second()
	if _freezes.has(_tick):
		OS.delay_msec(_freezes[_tick])
	if _tick >= _end_tick:
		_report()
		_client.link.close()
		quit(0)
	return false


func _on_welcomed(_slot: int) -> void:
	_started = true
	_tick = 0
	_bot.restart(_client.player.global_position if _centre == Vector3.INF else _centre)


func _note_second() -> void:
	var reconciler := _client.reconciler
	var at := _client.player.global_position
	var second := {
		"s": floori(float(_tick) / NetLimits.TICK_RATE),
		"corrected_m": snappedf(reconciler.corrected - _second_from["corrected"], 0.001),
		"snaps": reconciler.snaps - _second_from["snaps"],
		"gap_m": snappedf(NetPlayReport.gap(_client), 0.001),
		"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
		"unanswered": reconciler.unanswered(),
		"rtt_ms": _client.rtt_ms,
		"seq": _client.seq,
		"ack": _client.last_tick.ack if _client.last_tick != null else -1,
		"server_tick": _client.last_tick.server_tick if _client.last_tick != null else -1,
	}
	_by_second.append(second)
	_second_from = {"corrected": reconciler.corrected, "snaps": reconciler.snaps}


func _report() -> void:
	var line := NetPlayReport.of(_client, _remote, _tick, _puppet_us)
	line["seconds"] = _seconds
	line["end_gap_m"] = line["gap_m"]
	line["puppets"] = _most_puppets
	line["by_second"] = _by_second
	# The server's shots, hits and deaths this screen played (gdstudio #906).
	line["combat"] = {
		"shots": _client.combat.shots,
		"hits": _client.combat.hits,
		"deaths": _client.combat.deaths,
		"revives": _client.combat.revives,
		"rejected": _client.combat.rejected,
		"spent_us": _client.combat.spent_us,
		"worst_us": _client.combat.worst_us,
	}
	print("PREDICT_BOT ", JSON.stringify(line))
