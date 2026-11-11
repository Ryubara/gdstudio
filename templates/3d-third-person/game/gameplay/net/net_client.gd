class_name NetClient
extends Node
## The client of an online game of this template: it joins a `NetServer`, plays the local
## `player` at once (prediction) and hands the other players to `remote_players`.
##
## Each physics step, before the bodies: the link is polled (a WELCOME seats the client and puts
## the body where the server put it; a TICK gives the `Reconciler` the server's point for the last
## command it applied and gives the others' entries to `remote_players`; `joined` and `left` make
## and free puppets); the `StallGuard` judges the step; the body moves by the correction under way;
## the player's controller is sampled, the command numbered, quantized (`CommandCodec`, so the
## body steps with exactly the numbers the server reads) and sent; the body steps once with it
## (`Character.step`, the server's own step) and the point it reached is recorded for that number.
## A ping goes out `NetLimits.PING_RATE` times a second. Nothing cosmetic is sent: the server
## hears commands only.
##
## The player's own `_physics_process` is turned off while this node runs it. Its fall out of the
## map and a teleport go through `Player.teleport()` and reset the reconciler, so a move the
## server did not make is never read as an error. The address is `--connect <url>` or the page's
## `?url=` (`WebSocketLink.server_url`) unless a test hands a link to `join_with`.

## Said when the server seated this client.
signal welcomed(slot: int)
## Said when the server refused the HELLO (`NetWire.Refusal`).
signal refused(reason: int)
## Said when the link closed (the server went, or a goodbye).
signal disconnected

## Ticks a command's number may trail the server tick it is expected to be stepped at before the
## numbering moves on (`first_seq`; a stall, a slow clock).
const SEQ_SLACK := 4

@export_group("Nodes")
## The local body the client predicts.
@export var player: Player
## Where the other players are drawn; empty draws none.
@export var remote_players: RemotePlayers
## The map node (the `World` instance) whose networked parts make the world hash
## (`NetServer.world_hash_of`, paths from this node), the same node the server's
## `NetServer.world_root` names; empty is this node's parent.
@export var world_root: Node

@export_group("Join")
## Joins `--connect` or `?url=` when the scene starts (off: call `join` or `join_with`).
@export var join_on_ready := true
## The name the HELLO carries; `--name` wins.
@export var player_name := "Player"
## The spawn group and seed of the server (`NetServer.spawn_group`, `spawn_seed`): the client
## computes the same spawn so its body starts exactly where the server's does.
@export var spawn_group := &"player"
@export var spawn_seed := 1

## The link to the server (null before `join`).
var link: NetLink
## The slot the server gave, or -1 before the WELCOME.
var slot := -1
var welcome: SnapshotCodec.Welcome
var last_tick: SnapshotCodec.Tick
var reconciler := Reconciler.new()
var stall_guard := StallGuard.new()
## The map's networked parts (doors, platforms, pickups) as the server's records show them; made
## at the WELCOME.
var map_parts := NetWorld.new()
## Seconds for pings and the stall guard: empty is the machine's clock.
var clock := Callable():
	set(value):
		clock = value
		stall_guard.clock = value
## The `seq` of the last command sent.
var seq := 0
## The last round trip a PONG measured, milliseconds (-1 before the first).
var rtt_ms := -1
## Times the numbering of the commands moved on to the server's tick (after a stall).
var renumbered := 0
## TICKs read, and packets the decoders refused.
var ticks_read := 0
var drops := NetDrops.new()
## The microseconds of this node's work in the last physics step (poll, prediction, send), and,
## while `keep_frame_times` is on, of every step.
var last_frame_us := 0
var keep_frame_times := false
var frame_times := PackedInt32Array()

var _steps := 0
var _ping_every := NetLimits.TICK_RATE / NetLimits.PING_RATE
# When the HELLO left (this node's clock, seconds): the WELCOME measures a first round trip.
var _hello_at := 0.0


func _ready() -> void:
	# Before the bodies and the puppets: the TICKs are read first.
	process_physics_priority = -20
	if player != null:
		if player.is_node_ready():
			_take_player()
		else:
			player.ready.connect(_take_player, CONNECT_ONE_SHOT)
	if join_on_ready and not Engine.is_editor_hint():
		var args := NetArgs.new()
		player_name = args.get_string("name", player_name)
		var url := WebSocketLink.server_url()
		if url != "":
			join(url)


func _exit_tree() -> void:
	if link != null:
		link.close()
		link.poll()


## Connects to `url` over a WebSocket and says hello once it opens.
func join(url: String) -> Error:
	var socket := WebSocketLink.new()
	socket.clock = clock
	var failed := socket.connect_to_url(url)
	if failed != OK:
		return failed
	join_with(socket)
	return OK


## Says hello over `with_link` once it opens (a test's `LoopbackLink` or `LinkConditioner`).
func join_with(with_link: NetLink) -> void:
	link = with_link
	link.connected.connect(_on_connected)
	link.packet_received.connect(_on_packet)
	link.closed.connect(_on_closed)
	if link.is_open():
		_on_connected()


func is_seated() -> bool:
	return slot >= 0


func _physics_process(delta: float) -> void:
	if link == null:
		return
	var began := Time.get_ticks_usec()
	link.poll()
	if is_seated() and link.is_open() and player != null:
		_predict(delta)
	_steps += 1
	last_frame_us = Time.get_ticks_usec() - began
	if keep_frame_times:
		frame_times.append(last_frame_us)


func _predict(delta: float) -> void:
	match stall_guard.check(Engine.get_process_frames()):
		StallGuard.Verdict.SKIP:
			return
		StallGuard.Verdict.RESYNC:
			reconciler.reset()
			reconciler.snap_next = true
	var correction := reconciler.take()
	if correction != Vector3.ZERO:
		player.global_position += correction
	var wanted := player.controller.sample() if player.controller != null else PlayerCommand.new()
	seq += 1
	wanted.seq = seq
	# The map's moving parts where the server will have them when it steps this command.
	map_parts.tick = seq
	map_parts.place(map_parts.tick)
	if last_tick != null:
		wanted.view_tick = last_tick.server_tick
	var packet := CommandCodec.encode(wanted, drops)
	if packet.is_empty():
		packet = CommandCodec.encode(_standing(seq))
	link.send(packet)
	player.step(CommandCodec.decode(packet), delta)
	reconciler.record(seq, player.global_position)
	if _steps % _ping_every == 0:
		link.send(NetWire.ping(int(_now() * 1000.0), rtt_ms))


func _take_player() -> void:
	player.set_physics_process(false)
	if player.fell.is_connected(player.respawn):
		player.fell.disconnect(player.respawn)
	player.fell.connect(_on_fell)
	player.teleported.connect(_on_teleported)


func _on_connected() -> void:
	_hello_at = _now()
	link.send(NetWire.hello(player_name, NetServer.world_hash_of(_map_root())))


func _map_root() -> Node:
	return world_root if world_root != null else get_parent()


func _on_packet(data: PackedByteArray) -> void:
	match NetWire.type_of(data):
		NetWire.Type.WELCOME:
			_on_welcome(SnapshotCodec.read_welcome(data, drops))
		NetWire.Type.REFUSED:
			refused.emit(NetWire.read_refused(data, drops))
		NetWire.Type.TICK:
			_on_tick(SnapshotCodec.read_tick(data, drops))
		NetWire.Type.PONG:
			var pong := NetWire.read_pong(data, drops)
			if pong != null:
				rtt_ms = (int(_now() * 1000.0) - pong.client_ms) & 0xFFFFFFFF
		_:
			drops.count(NetDrops.UNKNOWN_TYPE)


func _on_welcome(read: SnapshotCodec.Welcome) -> void:
	if read == null or is_seated():
		return
	welcome = read
	slot = read.slot
	map_parts = NetWorld.new(_map_root(), NetEntity.Role.CLIENT)
	map_parts.read_table(read.entities, read.server_tick)
	seq = first_seq(read.server_tick, _now() - _hello_at)
	if player != null:
		_put_at_spawn(_entry_of(read.players, slot))
	if remote_players != null:
		remote_players.map_parts = map_parts
		remote_players.on_welcome(read)
	welcomed.emit(slot)


func _on_tick(tick: SnapshotCodec.Tick) -> void:
	if tick == null or not is_seated():
		return
	if last_tick != null and tick.server_tick <= last_tick.server_tick:
		return
	last_tick = tick
	ticks_read += 1
	_keep_numbering(tick)
	for event in tick.events:
		match event.kind:
			NetEvent.Kind.JOINED:
				if remote_players != null:
					remote_players.on_joined(event.slot, event.player_name)
			NetEvent.Kind.LEFT:
				if remote_players != null:
					remote_players.on_left(event.slot)
			NetEvent.Kind.ENTITY:
				map_parts.read_event(event)
			NetEvent.Kind.PICKUP:
				map_parts.read_pickup(event, player if event.slot == slot else null)
	var own := _entry_of(tick.players, slot)
	if own != null and player != null:
		reconciler.answer(tick.ack, own.position)
	if remote_players != null:
		remote_players.on_tick(tick)


func _on_closed() -> void:
	slot = -1
	if remote_players != null:
		remote_players.clear()
	disconnected.emit()


# The body starts where the server put it: the same spawn, computed in this map, when it agrees
# with the WELCOME's centimetres; the WELCOME's point otherwise.
func _put_at_spawn(entry: PlayerEntry) -> void:
	var spot := NetServer.spawn_transform_in(player, spawn_group, spawn_seed, slot)
	var at := spot.origin
	var heading := NetServer.heading_of(spot)
	if entry != null and entry.position.distance_to(at) > Reconciler.SNAP_DISTANCE:
		at = entry.position
		heading = entry.yaw
	player.teleport(at, heading)


func _on_fell() -> void:
	if is_seated():
		_put_at_spawn(null)
	else:
		player.respawn()


func _on_teleported() -> void:
	reconciler.reset()
	reconciler.snap_next = true


## The number of the first command after a WELCOME of server tick `welcome_tick` that came
## `round_trip` seconds after the HELLO: the server tick that command is expected to be stepped at
## (the WELCOME's tick, the round trip, one step), so each command's number is the tick the map's
## moving parts are at for it on both sides (`NetServer.command_tick`). The number before it.
static func first_seq(welcome_tick: int, round_trip: float) -> int:
	return welcome_tick + ceili(maxf(round_trip, 0.0) * NetLimits.TICK_RATE)


# Commands are numbered by the server tick each is expected to be stepped at (`first_seq`): one
# sent now reaches the server a round trip after this TICK left it. A client whose numbers trail
# that (its stall guard skipped steps, its clock runs slow) moves them on; a number may jump, never
# go back.
func _keep_numbering(tick: SnapshotCodec.Tick) -> void:
	if rtt_ms < 0:
		return
	var expected := tick.server_tick + ceili(rtt_ms * NetLimits.TICK_RATE / 1000.0)
	if seq + 1 < expected - SEQ_SLACK:
		seq = expected - 1
		renumbered += 1


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_ticks_usec() / 1000000.0


static func _entry_of(players: Array[PlayerEntry], of_slot: int) -> PlayerEntry:
	for entry in players:
		if entry.slot == of_slot:
			return entry
	return null


static func _standing(at_seq: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.seq = at_seq
	return command
