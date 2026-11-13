class_name NetServer
extends Node
## The game server of an online game of this template: it admits up to `max_players`, gives each
## a body (`character.tscn`, the body alone) stepped by that player's commands, and sends every
## client a TICK `NetLimits.SNAPSHOT_RATE` times a second. The server owns everything: a client
## sends commands (`CommandCodec`), never a position.
##
## Started by `godot --headless --path game -- --server [--port N]` (`MenuScene` opens
## `net_server.tscn`, which holds the map), or added to a scene by a test with `port = 0`.
##
## Each physics step, in order: the listener is polled (a HELLO is answered at once with a WELCOME
## or a REFUSED, a command is queued in its `PeerSlot`, a PING is answered with a PONG); a peer
## silent for `silent_seconds`, or that has not said hello in `hello_seconds`, is hung up on; every
## body steps once for each command its player's slot hands out (`PeerSlot.take`), in slot order;
## then every second step each client gets a TICK with its `ack`, all players, the events since
## its last TICK and its AI block (`AiBroadcast`, `AiSnapshot`: the AI runs here and nowhere
## else). The players are full in every TICK, so a TICK a full socket refused leaves nothing to
## repair: the next is whole, the events wait for it, and the next AI block is full.
##
## Logs one JSON object a line (`listening`, `joined`, `left`, `refused`, `kicked`, and `stats`
## every `STATS_SECONDS`) and says the same through `logged`. The connection rules (rates,
## silences, the hello's deadline) read `clock`: empty is the machine's, and a run faster than real
## time gives the game's (multiplayer.md#room-over-socket).

## Said with every log line: its `event` and its fields.
signal logged(event: String, fields: Dictionary)
## A player was seated (after its WELCOME left) or left (its body is gone).
signal player_joined(slot: int)
signal player_left(slot: int)

## A TICK every this many steps (30 a second at the 60 Hz step).
const SEND_EVERY := NetLimits.TICK_RATE / NetLimits.SNAPSHOT_RATE
## Seconds between the log's `stats` lines.
const STATS_SECONDS := 10.0
## Connections open at once, counting those that have not said hello; the next is hung up on.
const MAX_CONNECTIONS := 2 * NetLimits.MAX_PLAYERS
## The close code for a peer hung up on for breaking the rules (RFC 6455: policy violation).
const CLOSE_POLICY := 1008
## The group of a map's networked parts, whose paths (from the map node, `world_root`) and kinds
## make the world hash (issue #907 adds the parts; the map has none yet).
const PART_GROUP := &"net_part"
## The milliseconds a step may take before it counts as over budget in the stats.
const STEP_BUDGET_MS := 6.0
## How far a command's number may be from the step that applies it and still be the tick the map's
## moving parts are at for it: a client back from a stall of `NetLimits.STALL_SECONDS`, or a second
## ahead (`command_tick`).
const COMMAND_TICKS_BEHIND := NetLimits.TICK_RATE * NetLimits.STALL_SECONDS
const COMMAND_TICKS_AHEAD := NetLimits.TICK_RATE
## The defaults of `command_ticks` and `hold_ticks`: a predicting client steps its own body the
## same way through a stall of its thread (`SilenceWalk`).
const COMMAND_TICKS := 30
const HOLD_TICKS := 4

@export_group("Server")
## The port to listen on; -1 reads `--port`, then `$PORT`, then `WebSocketLink.DEFAULT_PORT`. 0
## takes a free one (read it from `listener.port()`).
@export var port := -1
## The address to listen on (`*` is every one; a test gives `127.0.0.1`).
@export var bind_address := "*"
## Players at once, at most `NetLimits.MAX_PLAYERS`; the next HELLO is `REFUSED(full)`.
@export_range(1, NetLimits.MAX_PLAYERS) var max_players := NetLimits.MAX_PLAYERS
## Holds the frame rate to the tick rate (`Engine.max_fps`): a headless server has no vsync and
## would otherwise spin. The server scene turns it on; a test leaves it off.
@export var cap_frame_rate := false
## Prints the log lines (`logged` is said either way).
@export var print_log := true

## The map node (the `World` instance) whose networked parts make the world hash, the same node a
## client's `NetClient.world_root` names, so the paths match whatever holds the map; empty is this
## node's parent.
@export var world_root: Node

@export_group("Players")
## The body each player gets: the body alone, with no model, animation or camera.
@export var body_scene: PackedScene = preload("res://gameplay/character/character.tscn")
## Where the bodies go; empty makes a `Players` node under the server.
@export var players_root: Node3D
## The `SpawnPoint` group the bodies start at: slot n takes the n-th point by node path, wrapping
## when there are more players than points.
@export var spawn_group := &"player"
## The seed of the spot inside a spawn point's radius (with the slot).
@export var spawn_seed := 1

@export_group("Rules")
## Steps the last command is stepped again (without its presses) when none came, before the body
## stands still.
@export_range(0, 600, 1, "suffix:steps") var command_ticks := COMMAND_TICKS
## Steps a body waits for a late command, without stepping, before it repeats the last: two
## machines' frames drift, so a client's command lands a step late now and then, and a repeat made
## for it leaves the body a step off where the client predicted it. 0 repeats at once.
@export_range(0, 30, 1, "suffix:steps") var hold_ticks := HOLD_TICKS
## Seconds without a command before a seated player is hung up on (a hidden tab stops its loop).
@export_range(1.0, 120.0, 0.5, "suffix:s") var silent_seconds := 15.0
## Seconds a connection has to say hello.
@export_range(1.0, 60.0, 0.5, "suffix:s") var hello_seconds := 10.0
## Steps between a change of a map part the server decides (a door opened, a platform sent) and
## its start, so a client hears of it before its predicted commands reach it: about the round trip
## and the hold of the slowest client it plays well with, in steps (12: 200 ms at 60 a second).
@export_range(0, 255, 1, "suffix:steps") var entity_lead_ticks := 12:
	set(value):
		entity_lead_ticks = value
		if map_parts != null:
			map_parts.lead_ticks = value

@export_group("AI")
## How often each client hears of each AI character, by distance, and the interest radius.
@export var ai_rates: AiTierRates = preload("res://gameplay/net/ai_tier_rates.tres")
## The section's origin: AI positions on the wire are centimetres from it, up to
## `NetLimits.POSITION_RANGE` each way (the client's `AiReplica.section_origin`).
@export var ai_section_origin := Vector3.ZERO
## An AI character's look on the wire: the index of its profile here (the client's
## `AiReplica.variant_scenes` at the same index).
@export var ai_variants: Array[AiProfile] = [
	preload("res://gameplay/ai/profiles/grunt.tres"),
	preload("res://gameplay/ai/profiles/ally.tres"),
	preload("res://gameplay/ai/profiles/civilian.tres"),
	preload("res://gameplay/ai/profiles/shooter.tres"),
]
## The players' bodies join the group `player` with the faction `player`, so the AI sees them,
## measures its tiers from them and fights them.
@export var ai_sees_players := true

@export_group("Shots")
## Metres a command's shot may start from the body's eye before it is refused (`ServerCombat`).
@export_range(0.5, 20.0, 0.1, "suffix:m") var origin_slack := 4.0
## Seconds a dead body lies before the server gets it up (and says where, in a REVIVED event).
@export_range(0.0, 60.0, 0.1, "suffix:s") var revive_seconds := 3.0
## On: a body gets up at its spawn point; off: where it died.
@export var revive_at_spawn := false
## Seconds of the AI's past a player's shot may be met in (lag compensation, `ShotRewind`): the
## shot meets each AI character where the shooter's screen drew it, up to this far back. 0 meets
## the AI as it is now.
@export_range(0.0, 1.0, 0.05, "suffix:s") var ai_rewind_seconds := 0.6:
	set(value):
		ai_rewind_seconds = value
		ai_history = AiHitHistory.new(maxi(roundi(value * NetLimits.TICK_RATE), 1), SEND_EVERY)
## Seconds of a projectile's flight met with the AI as the shooter drew it; past that it meets
## the AI where it is.
@export_range(0.0, 3.0, 0.05, "suffix:s") var ai_rewind_flight_seconds := 0.5

## The world hash a client's HELLO must carry (`world_hash_of` the server's map when it starts).
var world_hash := 0
## The map's networked parts (doors, platforms, pickups, props, targets), run by this server.
var map_parts := NetWorld.new()
## Seconds for the connection rules: empty is the machine's clock.
var clock := Callable()
var listener := WsListener.new()
## Steps taken (the server tick a TICK carries).
var server_tick := 0
## The milliseconds of the last step's work, and, while `keep_step_times` is on, of every step.
var last_step_ms := 0.0
var keep_step_times := false
var step_times := PackedFloat32Array()
## On: every slot keeps the `history` of its steps (a test's).
var keep_history := false
## Peers hung up on for breaking `PeerLimits`.
var kicked := 0
## Shots, hits and deaths: the server's judge and their events (gdstudio #906).
var combat := ServerCombat.new()
## The AI characters on the wire (gdstudio #970).
var ai := AiBroadcast.new()
## The volume of each AI character over the last `ai_rewind_seconds`, recorded with each TICK's
## rows (gdstudio #1198).
var ai_history := AiHitHistory.new(roundi(0.6 * NetLimits.TICK_RATE), SEND_EVERY)

var _peers: Dictionary[int, PeerSlot] = {}
var _by_slot: Dictionary[int, PeerSlot] = {}
var _stats_at := 0.0
var _stats_bytes := 0
var _stats_steps := PackedFloat32Array()
var _process := ProcessStats.new()


func _ready() -> void:
	if players_root == null:
		players_root = Node3D.new()
		players_root.name = "Players"
		add_child(players_root)
	if cap_frame_rate:
		Engine.max_fps = NetLimits.TICK_RATE
	world_hash = world_hash_of(_map_root())
	_take_world(_map_root())
	_wire_combat()
	_wire_ai()
	listener.clock = _now
	listener.peer_connected.connect(_on_connected)
	listener.peer_disconnected.connect(_on_disconnected)
	listener.packet_received.connect(_on_packet)
	var at_port := port if port >= 0 else NetArgs.new().port(WebSocketLink.DEFAULT_PORT)
	var failed := listener.listen(at_port, bind_address)
	if failed != OK:
		_log("listen_failed", {"port": at_port, "error": error_string(failed)})
		if cap_frame_rate:
			get_tree().quit(1)
		return
	_stats_at = _now() + STATS_SECONDS
	_log(
		"listening",
		{
			"port": listener.port(),
			"players_max": max_players,
			"tick_hz": Engine.physics_ticks_per_second,
			"version": NetWire.VERSION,
			# The host, since step times differ from one host to the next (kit railway.md#skew).
			"cpu": OS.get_processor_name(),
			"cores": OS.get_processor_count(),
		}
	)


func _exit_tree() -> void:
	listener.close()


func _physics_process(delta: float) -> void:
	if not listener.is_listening():
		return
	var began := Time.get_ticks_usec()
	listener.poll()
	_drop_the_silent()
	map_parts.tick = server_tick + 1
	_step_bodies(delta)
	server_tick += 1
	if server_tick % SEND_EVERY == 0:
		_send_ticks()
	last_step_ms = (Time.get_ticks_usec() - began) / 1000.0
	_stats_steps.append(last_step_ms)
	if keep_step_times:
		step_times.append(last_step_ms)
	_log_stats()


## The world hash of the networked parts under `root`, the map node (`NetWire.world_hash` of their
## paths from `root` and their kinds): a client computes the same from its own map, whatever node
## holds it. The map need not be in the tree (a bot hashes a map it never adds).
static func world_hash_of(root: Node) -> int:
	var parts := PackedStringArray()
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	for node in nodes:
		if node.is_in_group(PART_GROUP):
			parts.append("%s:%s" % [root.get_path_to(node), node.get_meta(&"net_kind", "")])
	return NetWire.world_hash(parts)


func _map_root() -> Node:
	if world_root != null:
		return world_root
	return get_parent() if get_parent() != null else self


## The seated players, by slot.
func player_count() -> int:
	return _by_slot.size()


## The connection of a slot, or null.
func peer_at(slot: int) -> PeerSlot:
	return _by_slot.get(slot)


## The body of a slot, or null.
func body_at(slot: int) -> Character:
	var peer := peer_at(slot)
	return peer.body if peer != null else null


## The lowest slot nobody holds, or -1 when `max_players` are seated.
func free_slot() -> int:
	for slot in max_players:
		if not _by_slot.has(slot):
			return slot
	return -1


## Where slot `slot` starts: the slot's spawn point (by node path, wrapping), a spot inside its
## radius from a generator seeded by `spawn_seed` and the slot; the origin facing -Z when the map
## has none.
func spawn_transform(slot: int) -> Transform3D:
	return spawn_transform_in(players_root, spawn_group, spawn_seed, slot)


## The same for the map `in_world` is in, so a predicting client starts its body exactly where
## the server put it (`NetClient`).
static func spawn_transform_in(
	in_world: Node3D, group: StringName, seed_value: int, slot: int
) -> Transform3D:
	var points: Array[SpawnPoint] = []
	var world := in_world.get_world_3d()
	for node in in_world.get_tree().get_nodes_in_group(StringName("spawn_%s" % group)):
		var point := node as SpawnPoint
		if point != null and point.enabled and point.get_world_3d() == world:
			points.append(point)
	if points.is_empty():
		return Transform3D.IDENTITY
	points.sort_custom(
		func(a: SpawnPoint, b: SpawnPoint) -> bool: return str(a.get_path()) < str(b.get_path())
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, slot])
	return points[slot % points.size()].spawn_transform(rng)


## The heading a spawn transform faces (radians about the up axis), as `Character.teleport` takes
## it.
static func heading_of(spot: Transform3D) -> float:
	return atan2(-spot.basis.z.x, -spot.basis.z.z)


## The state every client is sent of one seated player.
static func entry_of(slot: int, body: Character) -> PlayerEntry:
	var entry := PlayerEntry.new()
	entry.slot = slot
	entry.position = body.global_position
	entry.yaw = body.facing
	entry.state = body.state
	entry.crouch = body.crouching
	entry.aim = body.aiming
	entry.sprint = body.is_sprinting()
	entry.air = not body.is_on_floor()
	entry.rising = entry.air and body.velocity.y > 0.0
	entry.dead = body.is_dead()
	entry.halt = body.goal_speed <= 0.0
	entry.pitch = body.view_pitch
	# The aim layer's turn off the body, which another screen poses its puppet by (kit #1277).
	entry.aim_yaw = body.aim_yaw if body.aiming else 0.0
	return entry


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_ticks_usec() / 1000000.0


# --- Connections ---


func _on_connected(peer_id: int) -> void:
	if _peers.size() >= MAX_CONNECTIONS:
		listener.disconnect_peer(peer_id, CLOSE_POLICY, 0.0)
		return
	var peer := PeerSlot.new(peer_id, _now())
	peer.keep_history = keep_history
	_peers[peer_id] = peer


func _on_disconnected(peer_id: int) -> void:
	var peer: PeerSlot = _peers.get(peer_id)
	if peer == null:
		return
	_peers.erase(peer_id)
	if not peer.leaving:
		var reason := "goodbye" if listener.left_on_purpose(peer_id) else "dropped"
		_unseat(peer, reason)


func _on_packet(peer_id: int, data: PackedByteArray) -> void:
	var peer: PeerSlot = _peers.get(peer_id)
	if peer == null or peer.leaving:
		return
	var now := _now()
	match peer.limits.judge(data, now):
		PeerLimits.Verdict.KICK:
			_kick(peer)
			return
		PeerLimits.Verdict.DROP:
			return
	match data[0]:
		NetWire.Type.HELLO:
			_on_hello(peer, data)
		NetWire.Type.COMMAND:
			_on_command(peer, data, now)
		NetWire.Type.PING:
			var ping := NetWire.read_ping(data, peer.limits.drops)
			if ping != null:
				listener.send(peer_id, NetWire.pong(ping, server_tick))


func _on_hello(peer: PeerSlot, data: PackedByteArray) -> void:
	var version := NetWire.hello_version(data)
	if not NetWire.accepts(version):
		_refuse(peer, NetWire.Refusal.VERSION, {"version": version})
		return
	var why := NetDrops.new()
	var hello := NetWire.read_hello(data, why)
	if hello == null:
		_fault(peer, why.last)
		return
	if hello.world_hash != world_hash:
		_refuse(peer, NetWire.Refusal.WORLD, {"world": hello.world_hash})
		return
	var slot := free_slot()
	if slot < 0:
		_refuse(peer, NetWire.Refusal.FULL, {})
		return
	peer.player_name = hello.player_name
	peer.web = hello.flags & NetWire.F_WEB != 0
	var body := _make_body(slot)
	peer.seat(slot, body, _now())
	_by_slot[slot] = peer
	var players: Array[PlayerEntry] = []
	for seated: int in _sorted_slots():
		var entry := entry_of(seated, _by_slot[seated].body)
		entry.player_name = _by_slot[seated].player_name
		players.append(entry)
	var entities := map_parts.table(server_tick)
	listener.send(
		peer.peer_id, SnapshotCodec.welcome(slot, server_tick, world_hash, entities, players)
	)
	_tell_others(peer, NetEvent.joined(slot, peer.player_name))
	_log("joined", {"slot": slot, "name": peer.player_name, "players": _by_slot.size()})
	_cap_ai()
	player_joined.emit(slot)


func _on_command(peer: PeerSlot, data: PackedByteArray, now: float) -> void:
	if not peer.is_seated():
		_fault(peer, NetDrops.NO_HELLO)
		return
	var why := NetDrops.new()
	var command := CommandCodec.decode(data, why)
	if command == null:
		_fault(peer, why.last)
	elif not peer.push(command, now):
		_fault(peer, NetDrops.OUT_OF_ORDER)


func _make_body(slot: int) -> Character:
	var body := body_scene.instantiate() as Character
	body.name = "Player%d" % slot
	body.ragdoll_by_command = false
	if ai_sees_players:
		# The AI sees, fights and measures its tiers from the players' bodies.
		body.add_to_group(Player.GROUP)
		var member := AiFactionMember.new()
		member.name = "AiFactionMember"
		member.faction = &"player"
		body.add_child(member)
	players_root.add_child(body)
	# After `_ready`: the engine turns physics processing on again for a node that becomes ready.
	body.set_physics_process(false)
	_put_at_spawn(body, slot)
	body.fell.connect(_put_at_spawn.bind(body, slot))
	combat.watch(slot, body)
	return body


func _put_at_spawn(body: Character, slot: int) -> void:
	var spot := spawn_transform(slot)
	body.teleport(spot.origin, heading_of(spot))


func _refuse(peer: PeerSlot, reason: NetWire.Refusal, fields: Dictionary) -> void:
	listener.send(peer.peer_id, NetWire.refused(reason))
	peer.leaving = true
	listener.disconnect_peer(peer.peer_id)
	var why: String = NetWire.Refusal.find_key(reason)
	_log("refused", {"reason": why.to_lower(), "peer": peer.peer_id}.merged(fields))


# A packet the decoder or the order refused: a strike, and a kick at the limit.
func _fault(peer: PeerSlot, reason: StringName) -> void:
	if peer.limits.fault(_now(), reason) == PeerLimits.Verdict.KICK:
		_kick(peer)


func _kick(peer: PeerSlot) -> void:
	if peer.leaving:
		return
	kicked += 1
	peer.leaving = true
	listener.disconnect_peer(peer.peer_id, CLOSE_POLICY, 0.0)
	_log("kicked", {"peer": peer.peer_id, "drops": peer.limits.drops.summary()})
	_unseat(peer, "kicked")


func _drop_the_silent() -> void:
	var now := _now()
	for peer: PeerSlot in _peers.values():
		if peer.leaving:
			continue
		if peer.is_seated() and now - peer.last_command_at > silent_seconds:
			peer.leaving = true
			listener.disconnect_peer(peer.peer_id, CLOSE_POLICY)
			_unseat(peer, "silent")
		elif not peer.is_seated() and now - peer.connected_at > hello_seconds:
			peer.leaving = true
			listener.disconnect_peer(peer.peer_id, CLOSE_POLICY)


# Frees the player's body and slot, and tells everyone else.
func _unseat(peer: PeerSlot, reason: String) -> void:
	if not peer.is_seated() or _by_slot.get(peer.slot) != peer:
		return
	var slot := peer.slot
	_by_slot.erase(slot)
	combat.forget(slot)
	if is_instance_valid(peer.body):
		peer.body.queue_free()
	peer.body = null
	_tell_others(peer, NetEvent.left(slot))
	var fields := {"slot": slot, "reason": reason, "players": _by_slot.size()}
	if peer.limits.drops.total() > 0:
		fields["drops"] = peer.limits.drops.summary()
	_log("left", fields)
	_cap_ai()
	player_left.emit(slot)


func _tell_others(peer: PeerSlot, event: NetEvent) -> void:
	for other: PeerSlot in _by_slot.values():
		if other != peer:
			other.add_event(event)


# --- The step ---


# Each command is stepped with the map's moving parts where they are at the command's tick
# (`command_tick`), as the client predicted it; then the parts are put at this step's tick.
func _step_bodies(delta: float) -> void:
	for slot: int in _sorted_slots():
		var peer := _by_slot[slot]
		for command in peer.take(PeerSlot.MAX_PER_STEP, command_ticks, hold_ticks):
			map_parts.place(command_tick(command.seq, map_parts.tick))
			combat.judge(slot, peer.body, command)
			var weapon := peer.body.weapon
			if weapon != null:
				weapon.rewind = rewind_for(peer.body, command)
			peer.body.step(command, delta)
			if weapon != null:
				weapon.rewind = null
			combat.stepped(slot, peer.body)
	map_parts.place(map_parts.tick)
	combat.step(delta)


## The AI as the screen of `body`'s player drew it for `command`'s shot (its `view_tick`, less
## each character's glide at the rate this server sends it to that player), or null: no shot
## block, no AI recorded or `ai_rewind_seconds` 0.
func rewind_for(body: Character, command: PlayerCommand) -> ShotRewind:
	if not command.has_shot or ai_rewind_seconds <= 0.0 or ai_history.newest() < 0:
		return null
	var rewind := ShotRewind.new()
	rewind.history = ai_history
	rewind.view_tick = ShotRewind.whole_tick(command.view_tick, server_tick)
	rewind.flight_seconds = ai_rewind_flight_seconds
	var rates := ai.rates
	var viewer := body.global_position
	# The client walks each row over the ticks since the one before: one send at its rate, less
	# the tick of the row it is on.
	rewind.behind = func(character: AiCharacter) -> int:
		var away := viewer.distance_to(character.global_position)
		return rates.interval_ticks(rates.tier_for(away)) - 1
	return rewind


## The tick the map's moving parts are at for the command numbered `seq`, stepped at server tick
## `at_tick`: a client numbers its commands by the server tick it expects each to be stepped at
## (`NetClient`), so its predicted body meets the parts where the server's does; a number far from
## the step (a stall, a hostile client) is held to `COMMAND_TICKS_BEHIND` and `_AHEAD`.
static func command_tick(seq: int, at_tick: int) -> int:
	return clampi(seq, at_tick - COMMAND_TICKS_BEHIND, at_tick + COMMAND_TICKS_AHEAD)


func _take_world(root: Node) -> void:
	map_parts = NetWorld.new(root, NetEntity.Role.SERVER, entity_lead_ticks)
	map_parts.tick = server_tick
	for entity in map_parts.entities:
		entity.changed.connect(_on_entity_changed)
		entity.taken.connect(_on_entity_taken)


func _on_entity_changed(entity: NetEntity) -> void:
	var at := map_parts.tick
	var state: PackedByteArray = entity.write_state.call(at)
	_tell_all(NetEvent.entity(entity.id, at, state))


# A pickup the server's copy of which a body took: who took it, to everyone; taken by a body that
# is no player's (an AI), its new state.
func _on_entity_taken(entity: NetEntity, by: Node3D) -> void:
	for slot: int in _by_slot:
		if _by_slot[slot].body == by:
			_tell_all(NetEvent.pickup(entity.id, slot))
			return
	_on_entity_changed(entity)


func _tell_all(event: NetEvent) -> void:
	for peer: PeerSlot in _by_slot.values():
		peer.add_event(event)


# The combat's events go to the players by slot; its rules are the inspector's.
func _wire_combat() -> void:
	combat.origin_slack = origin_slack
	combat.revive_seconds = revive_seconds
	combat.revive_at_spawn = revive_at_spawn
	combat.spawn_of = spawn_transform
	combat.tell_all = func(event: NetEvent) -> void:
		for peer: PeerSlot in _by_slot.values():
			peer.add_event(event)
	combat.tell_others = func(from_slot: int, event: NetEvent) -> void:
		for slot: int in _by_slot:
			if slot != from_slot:
				_by_slot[slot].add_event(event)
	combat.tell = func(to_slot: int, event: NetEvent) -> void:
		var peer: PeerSlot = _by_slot.get(to_slot)
		if peer != null:
			peer.add_event(event)


# The AI's wire: its weapons' hits are HITs, its events go to the clients that hold it.
func _wire_ai() -> void:
	ai = AiBroadcast.new(_map_root(), ai_rates)
	ai.origin = ai_section_origin
	ai.variants = ai_variants
	ai.hit_made = combat.send_hit
	ai.tell_holders = func(id: int, event: NetEvent) -> void:
		for peer: PeerSlot in _by_slot.values():
			if peer.ai_view.holds(id):
				peer.add_event(event)


# The match's AI population: a browser among the players caps it for everyone (`web_cap`).
func _cap_ai() -> void:
	var director := ai_director()
	if director == null:
		return
	var browser := false
	for peer: PeerSlot in _by_slot.values():
		browser = browser or peer.web
	director.match_cap = director.web_cap if browser else -1


## The map's `AiDirector`, or null.
func ai_director() -> AiDirector:
	var root := _map_root()
	if root is AiDirector:
		return root
	for node in root.find_children("*", "", true, false):
		if node is AiDirector:
			return node
	return null


func _send_ticks() -> void:
	if _by_slot.is_empty():
		return
	ai.build()
	if ai_rewind_seconds > 0.0:
		ai_history.record(server_tick, ai.characters())
	var players: Array[PlayerEntry] = []
	for slot: int in _sorted_slots():
		players.append(entry_of(slot, _by_slot[slot].body))
	# The moving props, once for all (`stream_rows` marks a prop that fell asleep as said); every
	# prop for a client whose last TICK was refused.
	var parts := map_parts.stream_rows(server_tick)
	var every_part: Array[EntityEntry] = []
	for slot: int in _sorted_slots():
		var peer := _by_slot[slot]
		var events := peer.events_to_send()
		var rows := parts
		if peer.stream_all > 0:
			if every_part.is_empty():
				every_part = map_parts.stream_rows(server_tick, true)
			rows = every_part
		peer.ai_view.viewer = peer.body.global_position - ai.origin
		var ai_block := ai.block_for(peer.ai_view, server_tick)
		var packet := SnapshotCodec.tick(
			server_tick, peer.ack, events, players, peer.limits.drops, rows, ai_block
		)
		if listener.send(peer.peer_id, packet):
			peer.sent_events(events.size())
			peer.stream_all = maxi(peer.stream_all - 1, 0)
		else:
			peer.stalled = true
			peer.stream_all = map_parts.all_ticks()
			# What it holds is no longer known: the next AI block is full.
			peer.ai_view.reset()


func _sorted_slots() -> Array[int]:
	var slots: Array[int] = _by_slot.keys()
	slots.sort()
	return slots


# --- The log ---


func _log_stats() -> void:
	var now := _now()
	if now < _stats_at:
		return
	var sorted := _stats_steps.duplicate()
	sorted.sort()
	var stalled := 0
	var held := 0
	var repeated := 0
	for peer: PeerSlot in _by_slot.values():
		stalled += 1 if peer.stalled else 0
		peer.stalled = false
		held += peer.held
		repeated += peer.repeated
		peer.held = 0
		peer.repeated = 0
	var over := 0
	for ms in sorted:
		over += 1 if ms > STEP_BUDGET_MS else 0
	var seconds := STATS_SECONDS + now - _stats_at
	var fields := {
		"players": _by_slot.size(),
		"tick": server_tick,
		"out_bytes_per_s": roundi((listener.bytes_out - _stats_bytes) / seconds),
		"step_ms_p50": snappedf(percentile(sorted, 0.5), 0.001),
		"step_ms_p95": snappedf(percentile(sorted, 0.95), 0.001),
		"steps_over_budget": over,
		"peers_stalled": stalled,
		"steps_held": held,
		"steps_repeated": repeated,
		"kicked": kicked,
		"shots": combat.shots,
		"hits": combat.hits,
		"shots_rejected": combat.rejected,
		"deaths": combat.deaths,
		"ai": ai.rows().size(),
		"ai_build_us": ai.last_build_us,
		"ai_history_us": ai_history.last_record_us,
		"ai_encode_us_per_tick": roundi(ai.take_encode_us() / (seconds * NetLimits.SNAPSHOT_RATE)),
	}
	# The process's resident memory and processor share (Linux only: the image, Railway).
	fields.merge(_process.sample())
	_log("stats", fields)
	_stats_at = now + STATS_SECONDS
	_stats_bytes = listener.bytes_out
	_stats_steps.clear()


## The value at `share` (0 to 1) of sorted numbers (the nearest rank), 0 for none.
static func percentile(sorted: PackedFloat32Array, share: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)]


func _log(event: String, fields: Dictionary) -> void:
	logged.emit(event, fields)
	if print_log:
		var line := {"event": event, "t": snappedf(_now(), 0.01)}
		line.merge(fields)
		print(JSON.stringify(line))
