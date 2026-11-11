## The soak of online play: the game server and two predicting clients (autopilots) in one
## process over real sockets on 127.0.0.1 (`OnlineRig`: each side in a view with a world of its
## own), for `--minutes` game minutes (10) at `--fixed-fps 60`, which runs as fast as the machine
## allows (multiplayer.md#room-over-socket). Each client walks circles round its spawn point,
## sprinting every other lap and jumping every three seconds, and stands for the last second of
## every `CHECK_TICKS`; then the checks: both clients still in their seats and the server's two
## bodies theirs, each client's body within `SETTLED_M` of the server's, and every solid thing in
## both worlds at the same place (`WorldParity`). At the end: no `kicked` or `left` line, no answer
## lost, no snap past the join, and the process's memory and node count flat after the first
## minute. It prints a `SOAK` line of JSON (the numbers and every failed check) and exits 1 on a
## failure; the CI job (`.github/workflows/net-soak.yml` in the kit) also fails on an `ERROR` in
## the log.
##
## `<godot> --headless --path game --fixed-fps 60 -s res://tools/net/soak.gd -- [--minutes 10]`
## `--break solid` gives client 0's world a solid thing the server's lacks after the first check
## (Deadnight #748's prize crane) and `--break leak` keeps a node more at every check: the teeth
## check, each of which must fail.
extends SceneTree

## Ticks between two checks (5 s), and the ticks of each that the clients stand before it.
const CHECK_TICKS := 300
const STAND_TICKS := 60
## Metres a client's body may be from the server's once it stood a second (the wire's centimetres
## and a little more, as the bad-network gate's settled check).
const SETTLED_M := 0.05
## The process may grow this much after the first minute: memory (bytes) and nodes.
const MEMORY_GROWTH := 8 * 1024 * 1024
const NODE_GROWTH := 50
## Ticks of the first minute, before memory is taken as the baseline.
const WARM_TICKS := 60 * NetLimits.TICK_RATE
const CLIENTS := 2
## Ticks to wait for a seat.
const JOIN_TICKS := 600
## Metres each server body must have walked between two checks (the autopilot ran).
const WALKED_M := 5.0

var _rig: OnlineRig
var _minutes := 10.0
var _failures: Array[String] = []
var _lines: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _worst_gap := 0.0
var _checks := 0
var _began_usec := 0
var _broken := ""
var _last_at: Array[Vector3] = []
var _walked: Array[float] = []
var _walked_at_check: Array[float] = []


func _initialize() -> void:
	var args := NetArgs.new()
	_minutes = float(args.get_string("minutes", "10"))
	_broken = args.get_string("break", "")
	_began_usec = Time.get_ticks_usec()
	_rig = OnlineRig.new(false)
	root.add_child(_rig)
	_run()


func _run() -> void:
	# The root enters the tree after `_initialize`: the server's `_ready` (it listens there) waits.
	await process_frame
	if not _rig.start():
		_finish(["the server did not listen"])
		return
	_rig.server.keep_history = false
	_rig.server.keep_step_times = true
	_rig.server.logged.connect(_on_logged)
	var slots: Array[int] = []
	for index in CLIENTS:
		var client := await _rig.join("Soak%d" % index, JOIN_TICKS)
		if client == null:
			_finish(["client %d was never seated" % index])
			return
		slots.append(client.slot)
		_last_at.append(client.player.global_position)
		_walked.append(0.0)
		_walked_at_check.append(0.0)
		client.keep_frame_times = false
		_drive(index, client)
	var ticks := roundi(_minutes * 60.0 * NetLimits.TICK_RATE)
	for tick in range(1, ticks + 1):
		await physics_frame
		_track_walks()
		if tick % CHECK_TICKS == 0:
			_check(tick, slots)
	_finish(_failures)


# The path each server body walked (metres along it, not from where it started).
func _track_walks() -> void:
	for index in _rig.clients.size():
		var body := _rig.server_body(_rig.clients[index])
		if body == null:
			continue
		_walked[index] += body.global_position.distance_to(_last_at[index])
		_last_at[index] = body.global_position


# Each client's autopilot: circles round where it starts, standing for the last `STAND_TICKS` of
# every `CHECK_TICKS` (the circle goes on where it left off).
func _drive(index: int, client: NetClient) -> void:
	var circling := CirclingController.new()
	circling.body = client.player
	circling.seconds = INF
	circling.radius = 3.0 + index
	circling.restart(client.player.global_position)
	_rig.add_child(circling)
	var standing := PlayerCommand.new()
	_rig.controllers[index].plan = func(tick: int) -> PlayerCommand:
		if tick % CHECK_TICKS >= CHECK_TICKS - STAND_TICKS:
			standing.clear()
			standing.yaw = client.player.view_yaw
			return standing
		return circling.sample()


func _check(tick: int, slots: Array[int]) -> void:
	_checks += 1
	var failed := _failures.size()
	if _rig.server.player_count() != CLIENTS:
		_failures.append("tick %d: %d players seated" % [tick, _rig.server.player_count()])
	for index in CLIENTS:
		var client := _rig.clients[index]
		if not client.is_seated() or client.slot != slots[index]:
			_failures.append("tick %d: client %d lost its seat %d" % [tick, index, slots[index]])
			continue
		var body := _rig.server_body(client)
		if body == null:
			_failures.append("tick %d: the server has no body for slot %d" % [tick, client.slot])
			continue
		var walked := _walked[index] - _walked_at_check[index]
		_walked_at_check[index] = _walked[index]
		if walked < WALKED_M:
			_failures.append(
				"tick %d: client %d walked %.2f m since the last check" % [tick, index, walked]
			)
		var gap := client.player.global_position.distance_to(body.global_position)
		_worst_gap = maxf(_worst_gap, gap)
		if gap > SETTLED_M:
			_failures.append("tick %d: client %d is %.3f m from the server" % [tick, index, gap])
		var parity := WorldParity.compare(_rig.views[index], _rig.server_view)
		if not parity.same():
			_failures.append(
				(
					"tick %d: client %d's world differs: only it %s, only the server %s, moved %s"
					% [tick, index, parity.only_ours, parity.only_theirs, parity.moved]
				)
			)
	_break_something(tick)
	(
		_samples
		. append(
			{
				"tick": tick,
				"memory": OS.get_static_memory_usage(),
				"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			}
		)
	)
	if _failures.size() > failed:
		# Twenty failures say enough; the rest of the run would only repeat them.
		_failures = _failures.slice(0, 20)


# The teeth check: what the soak must catch, made on purpose.
func _break_something(tick: int) -> void:
	if _broken == "solid" and tick == CHECK_TICKS:
		var wall := StaticBody3D.new()
		wall.name = "ClientOnlyWall"
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		wall.add_child(shape)
		_rig.clients[0].world_root.add_child(wall)
	elif _broken == "leak":
		var kept := Node.new()
		kept.name = "Leak%d" % tick
		_rig.add_child(kept)
		for _i in 20:
			kept.add_child(Node.new())


func _finish(failures: Array[String]) -> void:
	var result := _result()
	for event in ["kicked", "left"]:
		var found := _lines.filter(func(line: Dictionary) -> bool: return line["event"] == event)
		if not found.is_empty():
			failures.append("the server logged %s: %s" % [event, found.slice(0, 3)])
	for index in _rig.clients.size():
		var reconciler := _rig.clients[index].reconciler
		if reconciler.lost > 0:
			failures.append("client %d lost its body %d times" % [index, reconciler.lost])
		if reconciler.snaps > 1:
			failures.append(
				"client %d snapped %d times (the join is one)" % [index, reconciler.snaps]
			)
	var warm := _samples.filter(
		func(sample: Dictionary) -> bool: return sample["tick"] >= WARM_TICKS
	)
	if warm.size() >= 2:
		var memory_growth: int = warm[-1]["memory"] - warm[0]["memory"]
		var node_growth: int = warm[-1]["nodes"] - warm[0]["nodes"]
		result["memory_growth_bytes"] = memory_growth
		result["node_growth"] = node_growth
		if memory_growth > MEMORY_GROWTH:
			failures.append("memory grew %d KB after the first minute" % (memory_growth / 1024))
		if node_growth > NODE_GROWTH:
			failures.append("%d nodes more after the first minute" % node_growth)
	elif _minutes * 60.0 * NetLimits.TICK_RATE >= WARM_TICKS + 2 * CHECK_TICKS:
		failures.append("no memory samples after the first minute")
	result["failures"] = failures
	result["passed"] = failures.is_empty()
	print("SOAK ", JSON.stringify(result))
	print("SOAK PASSED" if failures.is_empty() else "SOAK FAILED: %d check(s)" % failures.size())
	_rig.queue_free()
	quit(0 if failures.is_empty() else 1)


func _result() -> Dictionary:
	var steps := _rig.server.step_times if _rig.server != null else PackedFloat32Array()
	var sorted := steps.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in steps:
		total += ms
	var clients: Array[Dictionary] = []
	for client in _rig.clients:
		(
			clients
			. append(
				{
					"slot": client.slot,
					"walked_m":
					(
						snappedf(_walked[clients.size()], 0.1)
						if clients.size() < _walked.size()
						else 0.0
					),
					"commands": client.seq,
					"ticks_read": client.ticks_read,
					"corrections": client.reconciler.corrections,
					"corrected_m": snappedf(client.reconciler.corrected, 0.001),
					"worst_error_m": snappedf(client.reconciler.worst_error, 0.001),
					"snaps": client.reconciler.snaps,
					"lost": client.reconciler.lost,
					"drops": client.drops.summary(),
				}
			)
		)
	return {
		"minutes": _minutes,
		"ticks": _rig.server.server_tick if _rig.server != null else 0,
		"wall_s": snappedf((Time.get_ticks_usec() - _began_usec) / 1000000.0, 0.1),
		"checks": _checks,
		"worst_settled_gap_m": snappedf(_worst_gap, 0.0001),
		"server_step_ms_mean": snappedf(total / maxi(steps.size(), 1), 0.001),
		"server_step_ms_p95": snappedf(NetServer.percentile(sorted, 0.95), 0.001),
		"server_step_ms_max": snappedf(sorted[-1] if not sorted.is_empty() else 0.0, 0.001),
		"memory_first_minute": _samples_at(WARM_TICKS, "memory"),
		"memory_end": _samples[-1]["memory"] if not _samples.is_empty() else 0,
		"nodes_end": _samples[-1]["nodes"] if not _samples.is_empty() else 0,
		"clients": clients,
	}


func _samples_at(tick: int, key: String) -> int:
	for sample in _samples:
		if sample["tick"] >= tick:
			return sample[key]
	return 0


func _on_logged(event: String, fields: Dictionary) -> void:
	if event in ["kicked", "left"]:
		var line := {"event": event}
		line.merge(fields)
		_lines.append(line)
