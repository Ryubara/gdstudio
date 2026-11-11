## A predicting client that plays against a running game server (`godot --headless --path game --
## --server`) in its own process: the template's map, a `Player` stepped by a `NetClient`, the
## other players drawn by `RemotePlayers`. It walks circles round where it started, sprints every
## other lap and jumps every three seconds; with `--freeze` it stops its own thread (the frozen
## tab of `multiplayer.md#a-client-that-freezes-measured-on-the-live-server`) at the given seconds
## for the given milliseconds. After `--seconds` it stands still two seconds and prints one line of
## JSON that starts with `PREDICT_BOT`: the reconciler's corrections, snaps, losses and worst
## error, the gap to its own entry in the last TICK, the stalls and skipped ticks, the puppets
## drawn and how often they starved, the round trip, what the client costs a physics step, and the
## shots, hits and deaths it played from the server's events (`combat`).
##
## `<godot> --headless --path game -s res://tools/net/predict_bot.gd -- --connect
## ws://127.0.0.1:8910 --seconds 30 [--delay-ms 100] [--freeze 8:500,16:2000,24:5000]`; a
## `--delay-ms` holds each packet that long each way inside the client (`LinkConditioner`), or
## put `tools/net/relay.py` between it and the server for a delay on the socket itself.
extends SceneTree

const WORLD := "res://world/world.tscn"
const PLAYER := "res://gameplay/player/player.tscn"
## Seconds standing still at the end before the gap is read.
const SETTLE_SECONDS := 2.0
## The circle's radius, metres, and seconds a lap.
const RADIUS := 3.0
const LAP_SECONDS := 6.0
const JUMP_EVERY := 3.0


## Writes the command of each tick from the bot's plan.
class BotController:
	extends CharacterController
	var tick := 0
	var seconds := 30.0
	var start := Vector3.ZERO
	var body: Player

	func sample() -> PlayerCommand:
		var command := _command
		command.clear()
		var at := float(tick) / NetLimits.TICK_RATE
		tick += 1
		if at >= seconds:
			command.yaw = body.view_yaw
			return command
		var angle := TAU * at / LAP_SECONDS
		var target := start + Vector3(cos(angle), 0.0, sin(angle)) * RADIUS
		var way := target - body.global_position
		way.y = 0.0
		var ahead := Vector3(-sin(angle), 0.0, cos(angle))
		command.set_from_world(way + ahead, ahead)
		command.sprint = int(at / LAP_SECONDS) % 2 == 1
		var jump := tick % roundi(JUMP_EVERY * NetLimits.TICK_RATE) == 0
		command.jump = jump
		command.jump_pressed = jump
		return command


var _client: NetClient
var _remote: RemotePlayers
var _bot: BotController
var _seconds := 30.0
var _freezes: Dictionary[int, int] = {}
var _tick := 0
var _end_tick := 0
var _puppet_us := PackedInt32Array()
var _most_puppets := 0
var _started := false


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
	holder.add_child((load(WORLD) as PackedScene).instantiate())
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	player.start_at_spawn = false
	var input := player.get_node("PlayerInput")
	player.remove_child(input)
	input.free()
	_bot = BotController.new()
	_bot.seconds = _seconds
	_bot.body = player
	player.add_child(_bot)
	player.controller = _bot
	holder.add_child(player)
	_remote = RemotePlayers.new()
	holder.add_child(_remote)
	_client = NetClient.new()
	_client.join_on_ready = false
	_client.player = player
	_client.remote_players = _remote
	_client.player_name = args.get_string("name", "Predictor")
	_client.keep_frame_times = true
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
	_bot.start = _client.player.global_position
	_bot.tick = 0


func _report() -> void:
	var reconciler := _client.reconciler
	var own: PlayerEntry = null
	if _client.last_tick != null:
		for entry in _client.last_tick.players:
			if entry.slot == _client.slot:
				own = entry
	var gap := _client.player.global_position.distance_to(own.position) if own != null else -1.0
	var line := {
		"seconds": _seconds,
		"slot": _client.slot,
		"commands": _client.seq,
		"ticks_read": _client.ticks_read,
		"rtt_ms": _client.rtt_ms,
		"corrections": reconciler.corrections,
		"snaps": reconciler.snaps,
		"lost": reconciler.lost,
		"worst_error_m": snappedf(reconciler.worst_error, 0.001),
		"corrected_m": snappedf(reconciler.corrected, 0.001),
		"end_gap_m": snappedf(gap, 0.0001),
		"stalls": _client.stall_guard.resyncs,
		"skipped_ticks": _client.stall_guard.skipped,
		"puppets": _most_puppets,
		"starved_steps": _remote.starved,
		"client_us_p50": _percentile(_client.frame_times, 0.5),
		"client_us_p95": _percentile(_client.frame_times, 0.95),
		"puppets_us_p50": _percentile(_puppet_us, 0.5),
		"puppets_us_p95": _percentile(_puppet_us, 0.95),
		"drops": _client.drops.summary(),
		# The server's shots, hits and deaths this screen played (gdstudio #906).
		"combat":
		{
			"shots": _client.combat.shots,
			"hits": _client.combat.hits,
			"deaths": _client.combat.deaths,
			"revives": _client.combat.revives,
			"rejected": _client.combat.rejected,
		},
	}
	print("PREDICT_BOT ", JSON.stringify(line))


static func _percentile(values: PackedInt32Array, share: float) -> int:
	if values.is_empty():
		return -1
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)]
