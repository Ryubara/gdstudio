## Bots that play against a running game server (`godot --headless --path game -- --server`) over
## real sockets, for a check of a server in its own process (a local run, the Docker image, a
## deployment): each says hello, sends `ServerBench.canned_command` every physics tick and a ping
## twice a second, and reads every TICK. After `--seconds` it prints one line of JSON that starts
## with `SERVER_BOT`: for each bot its slot, the TICKs and players it saw, the last `ack` against
## the last command sent, the round trip, and the bytes each way a second; then it says goodbye
## and quits (exit 1 when a bot was never welcomed, or its connection closed before the end: a
## kick). The line also has `connect_ms` (from the connect to the WELCOME, which includes the TLS
## and WebSocket handshakes on `wss://`) and the round trip's median and 95th percentile over the
## run (`rtt_ms_p50`, `rtt_ms_p95`; each rounded up to the bot's frames, 16.7 ms).
##
## With `--version N` each bot says hello with protocol version N instead of `NetWire.VERSION`
## (`--version old`: `NetWire.MIN_VERSION - 1`, a client older than any this server takes): the
## run then passes (exit 0) only when every bot was refused for its version, the check that a
## server turns away a client of another commit (`server/check.sh` runs it after the bots).
##
## With `--moves` each bot runs the moves course on the template's map instead, steered by its own
## position in the TICKs: the weapon presses (the empty hands, the next weapon, a shot, a reload),
## a slide out of a sprint on its way to the vault course (crouch pressed once its TICKs say it
## runs faster than a slide starts from), then the course itself (three vaults and the mantle, a
## jump pressed in front of each face). Its line then lists the states the server sent for it
## (`states`) and how far it got (`stage`). TICKs carry no weapon state: the server's log says
## whether a press was refused (`kicked`, `drops`), and `test_net_server_moves.gd` what it did.
##
## `<godot> --headless --path game -s res://tools/net/server_bot.gd -- --connect
## ws://127.0.0.1:8910 --bots 2 --seconds 10 [--moves]`. It lives in tools/, which the export
## leaves out.
extends SceneTree

enum Stage { WEAPONS, TO_COURSE, COURSE, DONE }

## The weapon presses of `Stage.WEAPONS`, by the stage's tick: the field pressed for one command.
const WEAPON_PRESSES := {
	5: &"unarmed_pressed",
	65: &"next_weapon_pressed",
	125: &"fire_pressed",
	185: &"reload_pressed",
}
## Ticks of `Stage.WEAPONS` (the reload ends inside it).
const WEAPON_TICKS := 300
## Where the vault course starts on the map (`world/prototype/prototype_level.tscn`,
## `VaultCourse`): the bots run along +X from here at z = -12.
const COURSE_START := Vector3(-21.0, 0.0, -12.0)
## The near faces (x) of the course's walls: `Vault05`, `Vault09`, `Vault12` and `Mantle16`.
const COURSE_FACES: Array[float] = [-18.2, -15.7, -13.25, -11.0]
## How far ahead of a face a bot presses jump (the character's own vault test presses at 0.9 m
## from the capsule's edge, 0.34 m out from its centre).
const JUMP_AT := 1.24
## The course is done once a bot stands this far along x (on the mantle's top).
const COURSE_END_X := -10.5
## Ticks a stage may take before the bot gives up on it.
const STAGE_TICKS := 900
## The ground speed (over the last `SPEED_TICKS` TICKs, each of them `RUN`) a bot waits for on its
## way to the course before it presses crouch, held `SLIDE_TICKS`: above `SlideTuning.min_speed`
## (5 m/s), so the press slides. One TICK to the next is too noisy, and the map drops off a ledge
## west of the spawn points, where a crouch in the air does not slide.
const SLIDE_SPEED := 5.5
const SPEED_TICKS := 10
const SLIDE_TICKS := 40

var _links: Array[WebSocketLink] = []
var _bots: Array[Dictionary] = []
var _tick := 0
var _end_tick := 0
var _closing_until := -1
var _moves := false
## The version a hello carries (`--version`), -1 for this build's.
var _version := -1


func _initialize() -> void:
	var args := NetArgs.new()
	_moves = args.has("moves")
	var version := args.get_string("version")
	_version = args.get_int("version", NetWire.MIN_VERSION - 1 if version == "old" else -1)
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
					"rtts": [],
					"open": false,
					"connect_at": Time.get_ticks_msec(),
					"connect_ms": -1,
					"stage": Stage.WEAPONS,
					"stage_tick": 0,
					"pressed": {},
					"position": Vector3.ZERO,
					"speed": 0.0,
					"trail": [],
					"runs": 0,
					"slide_from": -1,
					"states": {},
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
			var command := _move_command(bot, index)
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
		quit(0 if _passed() else 1)
	return false


func _report() -> void:
	var seconds := float(_end_tick) / NetLimits.TICK_RATE
	var lines: Array[Dictionary] = []
	for index in _bots.size():
		var link := _links[index]
		var bot := _bots[index]
		var line := {}
		for key: String in ["slot", "refused", "ticks", "players", "ack", "sent", "rtt_ms"]:
			line[key] = bot[key]
		line["open"] = link.is_open()
		bot["open"] = line["open"]
		line["connect_ms"] = bot["connect_ms"]
		var rtts: Array = (bot["rtts"] as Array).duplicate()
		rtts.sort()
		line["rtt_ms_p50"] = _rank(rtts, 0.5)
		line["rtt_ms_p95"] = _rank(rtts, 0.95)
		line["down_bytes_per_s"] = roundi(link.bytes_in / seconds)
		line["up_bytes_per_s"] = roundi(link.bytes_out / seconds)
		if _moves:
			line["stage"] = str(Stage.find_key(bot["stage"])).to_lower()
			line["states"] = (bot["states"] as Dictionary).keys()
		lines.append(line)
	print("SERVER_BOT ", JSON.stringify({"seconds": seconds, "bots": lines}))


# The value at `share` (0 to 1) of sorted numbers (the nearest rank), -1 for none.
static func _rank(sorted: Array, share: float) -> int:
	if sorted.is_empty():
		return -1
	return sorted[clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)]


# Every bot welcomed and still connected at the end; with `--version`, every bot refused for it.
func _passed() -> bool:
	if _version >= 0:
		return _bots.all(
			func(bot: Dictionary) -> bool: return bot["refused"] == NetWire.Refusal.VERSION
		)
	return _bots.all(func(bot: Dictionary) -> bool: return bot["slot"] >= 0 and bot["open"])


func _on_connected(index: int) -> void:
	var hello := NetWire.hello("Bot%d" % index, NetServer.world_hash_of(root))
	if _version >= 0:
		hello[NetWire.VERSION_AT] = _version
	_links[index].send(hello)


func _on_packet(data: PackedByteArray, index: int) -> void:
	var bot := _bots[index]
	match NetWire.type_of(data):
		NetWire.Type.WELCOME:
			var welcome := SnapshotCodec.read_welcome(data)
			bot["slot"] = welcome.slot if welcome != null else -1
			bot["connect_ms"] = Time.get_ticks_msec() - bot["connect_at"]
		NetWire.Type.REFUSED:
			bot["refused"] = NetWire.read_refused(data)
		NetWire.Type.TICK:
			var tick := SnapshotCodec.read_tick(data)
			if tick != null:
				bot["ticks"] += 1
				bot["ack"] = tick.ack
				bot["players"] = tick.players.size()
				for entry in tick.players:
					if entry.slot == bot["slot"]:
						var trail: Array = bot["trail"]
						trail.append(entry.position)
						if trail.size() > SPEED_TICKS:
							trail.pop_front()
						var moved: Vector3 = trail[-1] - trail[0]
						moved.y = 0.0
						bot["speed"] = (
							moved.length() * NetLimits.SNAPSHOT_RATE / maxi(trail.size() - 1, 1)
						)
						bot["runs"] = bot["runs"] + 1 if entry.state == Character.State.RUN else 0
						bot["position"] = entry.position
						var named: Variant = Character.State.find_key(entry.state)
						bot["states"][str(named) if named != null else str(entry.state)] = true
		NetWire.Type.PONG:
			var pong := NetWire.read_pong(data)
			if pong != null:
				bot["rtt_ms"] = (Time.get_ticks_msec() - pong.client_ms) & 0xFFFFFFFF
				(bot["rtts"] as Array).append(bot["rtt_ms"])


# The command of this tick: `ServerBench.canned_command` (a circle), or with `--moves` the moves
# course's.
func _move_command(bot: Dictionary, index: int) -> PlayerCommand:
	if not _moves or bot["stage"] == Stage.DONE:
		return ServerBench.canned_command(index, _tick)
	var command := PlayerCommand.new()
	command.seq = _tick + 1
	var at: int = _tick - bot["stage_tick"]
	var position: Vector3 = bot["position"]
	match bot["stage"]:
		Stage.WEAPONS:
			if WEAPON_PRESSES.has(at):
				command.set(WEAPON_PRESSES[at], true)
			# Fire held a moment so the arm comes up and the round leaves.
			command.fire = at >= 125 and at < 140
			if at >= WEAPON_TICKS:
				_next_stage(bot)
		Stage.TO_COURSE:
			var way := COURSE_START - position
			way.y = 0.0
			command.set_from_world(way, Vector3.ZERO)
			command.sprint = true
			var running: bool = bot["runs"] >= SPEED_TICKS and bot["speed"] >= SLIDE_SPEED
			if bot["slide_from"] < 0 and running:
				bot["slide_from"] = _tick
			var slid_for: int = _tick - bot["slide_from"]
			command.crouch = bot["slide_from"] >= 0 and slid_for < SLIDE_TICKS
			if way.length() < 0.6 or at >= STAGE_TICKS:
				_next_stage(bot)
		Stage.COURSE:
			# Along +X, pulled back onto the line z = -12.
			var way := Vector3(1.0, 0.0, clampf((COURSE_START.z - position.z) * 0.5, -0.5, 0.5))
			command.set_from_world(way, Vector3.RIGHT)
			var pressed: Dictionary = bot["pressed"]
			for face in COURSE_FACES:
				if not pressed.has(face) and position.x >= face - JUMP_AT and position.x < face:
					pressed[face] = true
					command.jump = true
					command.jump_pressed = true
			if position.x >= COURSE_END_X or at >= STAGE_TICKS:
				_next_stage(bot)
	return command


func _next_stage(bot: Dictionary) -> void:
	bot["stage"] = bot["stage"] + 1
	bot["stage_tick"] = _tick
