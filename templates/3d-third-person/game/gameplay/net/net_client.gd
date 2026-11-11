class_name NetClient
extends Node
## The client of an online game of this template: it joins a `NetServer`, plays the local
## `player` at once (prediction) and hands the other players to `remote_players`.
##
## Each physics step, before the bodies: the link is polled (a WELCOME seats the client and puts
## the body where the server put it; a TICK gives the `Reconciler` the server's point for the last
## command it applied and gives the others' entries to `remote_players`; `joined` and `left` make
## and free puppets); the `StallGuard` judges the step (after a stall of this client's thread the
## body first steps as the server stepped its own through the silence: `SilenceWalk`); the body
## moves by the correction under way; the player's controller is sampled, the command numbered,
## quantized (`CommandCodec`, so the body steps with exactly the numbers the server reads) and
## sent; the body steps once with it (`Character.step`, the server's own step) and the point it
## reached is recorded for that number. A ping goes out `NetLimits.PING_RATE` times a second.
## Nothing cosmetic is sent: the server hears commands only. The server's shots, hits and deaths
## are played by `combat` (`ClientCombat`); the player's own shots are cosmetic
## (`Weapon.authoritative` off).
##
## The player's own `_physics_process` is turned off while this node runs it. Its fall out of the
## map and a teleport go through `Player.teleport()` and reset the reconciler, so a move the
## server did not make is never read as an error. The address is `--connect <url>` or the page's
## `?url=` (`WebSocketLink.server_url`) unless a test hands a link to `join_with`.
##
## A server that hangs up before the WELCOME for a hello that came too late
## (`NetServer.CLOSE_POLICY` after `NetServer.hello_seconds`) gets a new socket, up to `rejoins`
## times, before the client says it is gone: a browser that has never drawn the game links every
## shader program in its first frames, which held a page's thread 14 s on a GPU while its socket's
## `open` waited (gdstudio #1137), and a busy machine's second page does the same.

## Said when the server seated this client.
signal welcomed(slot: int)
## Said when the server refused the HELLO (`NetWire.Refusal`).
signal refused(reason: int)
## Said when the link closed (the server went, or a goodbye).
signal disconnected
## Said when the server hung up before the WELCOME for a late hello and a new socket opens to the
## same address (`rejoins`); `attempt` counts from 1.
signal rejoining(attempt: int)

## Ticks a command's number may trail the server tick it is expected to be stepped at before the
## numbering moves on (`first_seq`; a stall, a slow clock).
const SEQ_SLACK := 4
## Round trips the numbering reads the smallest of (`numbering_rtt_ms`): 8 PONGs, 4 s at
## `NetLimits.PING_RATE`. One held behind a stall of the network reads 450 to 590 ms instead of
## about 250, and numbering from it put the commands ahead for good (gdstudio #1116); the network's
## own round trip is the fastest a packet came back lately.
const RTT_WINDOW := 8

## An address chosen for the next client that joins on ready (the main menu's "Play online"):
## wins over `--connect` and `?url=`, and is used once.
static var next_url := ""

@export_group("Nodes")
## The local body the client predicts.
@export var player: Player
## Where the other players are drawn; empty draws none.
@export var remote_players: RemotePlayers
## Where the server's AI characters are drawn (gdstudio #970); empty draws none. The map's own AI
## is taken out when the client joins (`AiAuthority.hand_over`): it runs on the server only.
@export var ai_replica: AiReplica
## The map node (the `World` instance) whose networked parts make the world hash
## (`NetServer.world_hash_of`, paths from this node), the same node the server's
## `NetServer.world_root` names; empty is this node's parent.
@export var world_root: Node

@export_group("Join")
## Joins `--connect` or `?url=` when the scene starts (off: call `join` or `join_with`).
@export var join_on_ready := true
## On: a join on ready waits for the level's warm-up and its frames to settle first (`JoinWait`),
## as a game joins behind its loading screen; a seat taken during the warm-up meets its slow
## frames as stalls (kit #1106, #1142). Off: it joins at once.
@export var join_after_warm_up := true
## The name the HELLO carries; `--name` wins.
@export var player_name := "Player"
## The spawn group and seed of the server (`NetServer.spawn_group`, `spawn_seed`): the client
## computes the same spawn so its body starts exactly where the server's does.
@export var spawn_group := &"player"
@export var spawn_seed := 1
## New sockets the client opens to the same address when the server hangs up on a hello that came
## too late (close `NetServer.CLOSE_POLICY` before the WELCOME), before it says `disconnected`. A
## page whose first frames compile the game's shaders sends its hello late once; a refusal, a
## server that is not there or a seated link that closes is never retried.
@export_range(0, 10) var rejoins := 2

## The link to the server (null before `join`).
var link: NetLink
## The wait before a join on ready (null when it joined at once or was never asked to).
var join_wait: JoinWait
## The slot the server gave, or -1 before the WELCOME.
var slot := -1
var welcome: SnapshotCodec.Welcome
var last_tick: SnapshotCodec.Tick
var reconciler := Reconciler.new()
var stall_guard := StallGuard.new()
## Steps the body through what the server did with it while this client's thread stalled.
var silence_walk := SilenceWalk.new()
## The map's networked parts (doors, platforms, pickups, props, targets) as the server's records
## show them; made at the WELCOME. A moving prop's records ride each TICK (`read_stream`).
var map_parts := NetWorld.new()
## Seconds for pings and the stall guard: empty is the machine's clock.
var clock := Callable():
	set(value):
		clock = value
		stall_guard.clock = value
## The server's shots, hits and deaths played on this screen (gdstudio #906).
var combat := ClientCombat.new(self)
## The `seq` of the last command sent.
var seq := 0
## The last round trip a PONG measured, milliseconds (-1 before the first).
var rtt_ms := -1
## The last `RTT_WINDOW` round trips, oldest first (milliseconds).
var rtt_samples := PackedInt32Array()
## Times the numbering of the commands moved on to the server's tick (after a stall).
var renumbered := 0
## New sockets opened after a late hello (`rejoins`).
var rejoined := 0
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
# The last stall's end (this node's clock, milliseconds as a ping carries them): a PONG for an
# older ping is not a round trip (-1: no stall yet).
var _pings_valid_from := -1
# The address `join` opened (empty for a link handed to `join_with`, which is never reopened).
var _url := ""
# Whether a REFUSED came on this link: the server answered, so its close is not retried.
var _refused := false


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
		var url := next_url if next_url != "" else WebSocketLink.server_url()
		next_url = ""
		if url != "":
			join_when_ready(url)


func _exit_tree() -> void:
	if link != null:
		link.close()
		link.poll()


## Joins `url` once the level is ready (`join_wait`), or at once with `join_after_warm_up` off.
func join_when_ready(url: String) -> void:
	if not join_after_warm_up:
		join(url)
		return
	join_wait = JoinWait.new()
	# A frame counts as settled under the stall guard's stall, not the server's hold (the probe's):
	# a device that draws every frame in 70 ms would otherwise wait out the whole `limit` on Loading,
	# and only a frame past the stall resyncs the client.
	join_wait.settle.longest = StallGuard.STALL_SECONDS
	join_wait.finished.connect(func() -> void: join(url), CONNECT_ONE_SHOT)
	join_wait.run(self)


## True while a join waits for the level to be ready.
func is_waiting_to_join() -> bool:
	return join_wait != null and join_wait.is_waiting()


## Connects to `url` over a WebSocket and says hello once it opens.
func join(url: String) -> Error:
	var socket := WebSocketLink.new()
	socket.clock = clock
	var failed := socket.connect_to_url(url)
	if failed != OK:
		return failed
	join_with(socket)
	_url = url
	return OK


## Says hello over `with_link` once it opens (a test's `LoopbackLink` or `LinkConditioner`).
func join_with(with_link: NetLink) -> void:
	# The AI is the server's: this map's own stands down before it processes a frame.
	AiAuthority.hand_over(_map_root())
	link = with_link
	_url = ""
	_refused = false
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
	if is_seated():
		var drawn := remote_players.drawn_time() if remote_players != null else -1.0
		combat.play_due(drawn + delta if drawn >= 0.0 else -1.0)
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
			resync()
			silence_walk.walk(player, silent_steps(stall_guard.last_gap), delta)
	var correction := reconciler.take()
	if correction != Vector3.ZERO:
		player.global_position += correction
		# A part that put the body inside a ledge would be pushed back by the step: the rest whole.
		if reconciler.pending() != Vector3.ZERO and BodyOverlap.pushed_back(player):
			player.global_position += reconciler.take_rest()
	var wanted := player.controller.sample() if player.controller != null else PlayerCommand.new()
	seq += 1
	wanted.seq = seq
	# The map's moving parts where the server will have them when it steps this command.
	map_parts.tick = seq
	map_parts.place(map_parts.tick)
	wanted.view_tick = view_tick()
	var packet := CommandCodec.encode(wanted, drops)
	if packet.is_empty():
		packet = CommandCodec.encode(_standing(seq))
	link.send(packet)
	var stepped := CommandCodec.decode(packet)
	player.step(stepped, delta)
	silence_walk.remember(stepped)
	reconciler.record(seq, player.global_position)
	if _steps % _ping_every == 0:
		link.send(NetWire.ping(_now_ms(), rtt_ms))


## The server tick this screen draws the AI and the other players at (the server meets a shot
## with the AI there, `ShotRewind`): the AI's drawn time, else the newest TICK's tick, else 0.
func view_tick() -> int:
	if ai_replica != null and ai_replica.drawn_time() >= 0.0:
		return roundi(ai_replica.drawn_time() * NetLimits.TICK_RATE)
	return last_tick.server_tick if last_tick != null else 0


## The client's own thread stalled (`StallGuard`): the reconciler forgets its points and takes the
## next answer whole (`Reconciler.resync`), and a PONG for a ping sent before now measures the
## stall, not the network, so it is not a round trip.
func resync() -> void:
	reconciler.resync()
	_pings_valid_from = _now_ms()


## The server steps without a command of this client across a stall of `gap` seconds between two
## of its ticks: every tick of the gap but the one that ends it (`SilenceWalk`).
static func silent_steps(gap: float) -> int:
	return maxi(roundi(gap * NetLimits.TICK_RATE) - 1, 0)


func _take_player() -> void:
	player.set_physics_process(false)
	if player.fell.is_connected(player.respawn):
		player.fell.disconnect(player.respawn)
	player.fell.connect(_on_fell)
	player.teleported.connect(_on_teleported)
	# Its shots are cosmetic: the server's body fires the real ones and its events say what they hit.
	if player.weapon != null:
		player.weapon.authoritative = false
		player.weapon.fired.connect(combat.track)
	# The bag is not on the wire yet: a hotbar use would change health the server owns.
	var hotbar := Hotbar.of(player)
	if hotbar != null:
		hotbar.authoritative = false


func _on_connected() -> void:
	_hello_at = _now()
	var flags := NetWire.F_WEB if OS.has_feature("web") else 0
	link.send(NetWire.hello(player_name, NetServer.world_hash_of(_map_root()), flags))


func _map_root() -> Node:
	return world_root if world_root != null else get_parent()


func _on_packet(data: PackedByteArray) -> void:
	match NetWire.type_of(data):
		NetWire.Type.WELCOME:
			_on_welcome(SnapshotCodec.read_welcome(data, drops))
		NetWire.Type.REFUSED:
			_refused = true
			refused.emit(NetWire.read_refused(data, drops))
		NetWire.Type.TICK:
			_on_tick(SnapshotCodec.read_tick(data, drops))
		NetWire.Type.PONG:
			var pong := NetWire.read_pong(data, drops)
			if pong != null and not _sent_before_stall(pong.client_ms):
				_note_rtt((_now_ms() - pong.client_ms) & 0xFFFFFFFF)
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
	silence_walk.reset()
	if player != null:
		player.set_meta(NetHits.SLOT_META, slot)
		if player.weapon != null:
			player.weapon.seed_base = slot
		_put_at_spawn(_entry_of(read.players, slot))
	if remote_players != null:
		remote_players.map_parts = map_parts
		remote_players.on_welcome(read)
	if ai_replica != null:
		ai_replica.slot_body = combat.body_of
		ai_replica.on_welcome(read.server_tick)
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
				# A target's fall waits for the hit it goes with (`ClientCombat`).
				if remote_players == null or not map_parts.plays_with_puppets(event):
					map_parts.read_event(event)
			NetEvent.Kind.PICKUP:
				map_parts.read_pickup(event, player if event.slot == slot else null)
	map_parts.read_stream(tick.parts, tick.server_tick)
	if ai_replica != null:
		ai_replica.on_tick(tick)
	combat.on_tick(tick)
	var own := _entry_of(tick.players, slot)
	if own != null and player != null:
		reconciler.answer(tick.ack, own.position)
	if remote_players != null:
		remote_players.on_tick(tick)


func _on_closed() -> void:
	if should_rejoin():
		_rejoin()
		return
	slot = -1
	combat.clear()
	if remote_players != null:
		remote_players.clear()
	if ai_replica != null:
		ai_replica.clear()
	disconnected.emit()


## Whether the link that just closed is one to open again: the server hung up before the WELCOME
## (`NetServer.CLOSE_POLICY`: a hello later than `hello_seconds`), no REFUSED came, the address is
## known and `rejoins` are left.
func should_rejoin() -> bool:
	return (
		not is_seated()
		and not _refused
		and _url != ""
		and rejoined < rejoins
		and link != null
		and link.close_code() == NetServer.CLOSE_POLICY
	)


# Opens a new socket to the same address; the closed link says nothing more.
func _rejoin() -> void:
	link.connected.disconnect(_on_connected)
	link.packet_received.disconnect(_on_packet)
	link.closed.disconnect(_on_closed)
	rejoined += 1
	rejoining.emit(rejoined)
	if join(_url) != OK:
		_url = ""
		_on_closed()


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
	# A ragdoll that falls out of the map waits for the server's REVIVED: the server's rule.
	if is_seated() and player.is_dead():
		return
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


## The round trip the numbering reads: the smallest of the last `RTT_WINDOW` (-1 before the
## first). A PONG held behind a stall of the network measures the stall too; the smallest is the
## network's own.
func numbering_rtt_ms() -> int:
	if rtt_samples.is_empty():
		return -1
	var smallest := rtt_samples[0]
	for sample in rtt_samples:
		smallest = mini(smallest, sample)
	return smallest


func _note_rtt(sample: int) -> void:
	rtt_ms = sample
	rtt_samples.append(sample)
	if rtt_samples.size() > RTT_WINDOW:
		rtt_samples.remove_at(0)


# Commands are numbered by the server tick each is expected to be stepped at (`first_seq`): one
# sent now reaches the server a round trip after this TICK left it (the smallest lately,
# `numbering_rtt_ms`). A client whose numbers trail that (its stall guard skipped steps, its clock
# runs slow) moves them on; a number may jump, never go back, so a jump from a round trip that
# waited out a stall would stay for good (gdstudio #1116).
func _keep_numbering(tick: SnapshotCodec.Tick) -> void:
	var round_trip := numbering_rtt_ms()
	if round_trip < 0:
		return
	var expected := tick.server_tick + ceili(round_trip * NetLimits.TICK_RATE / 1000.0)
	if seq + 1 < expected - SEQ_SLACK:
		seq = expected - 1
		renumbered += 1


# Whether the ping of `client_ms` left before the last stall: its PONG waited out the stall in a
# buffer, so its round trip is the stall's length (5 s after a 5 s freeze), and the numbering
# (`_keep_numbering`) would put the commands that far ahead of the server (gdstudio #1070).
func _sent_before_stall(client_ms: int) -> bool:
	if _pings_valid_from < 0:
		return false
	return ((client_ms - _pings_valid_from) & 0xFFFFFFFF) >= 0x80000000


# The clock in milliseconds as a ping carries them (32 bits).
func _now_ms() -> int:
	return int(_now() * 1000.0) & 0xFFFFFFFF


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
