extends Node
## Spike: what the state of N third-person players costs on a WebSocket, four ways.
##
##   --mode=sync         one MultiplayerSynchronizer per player, five properties (position, yaw, anim
##                       state, aim, pitch), replicated at the net rate
##   --mode=sync_change  as sync, but REPLICATION_MODE_ON_CHANGE
##   --mode=sync_packed  one MultiplayerSynchronizer per player, one PackedByteArray property
##   --mode=rpc_bytes    one @rpc("authority", "unreliable_ordered") call with all players in one buffer
##   --mode=send_bytes   SceneMultiplayer.send_bytes with the same buffer (no RPC header)
##   --mode=send_delta   send_bytes, only the players that changed since the last send
##
## Server: --server --port=N --players=N --moving=N --run-seconds=N. Client: --url=ws://... Each
## client sends a 12-byte input 30 times a second (rpc for the sync and rpc modes, send_bytes for
## the others). The byte counts come from the proxy in tools/run.py.

const NET_HZ := 20.0
const INPUT_HZ := 30.0

var mode := "send_bytes"
var is_server := false
var url := "ws://127.0.0.1:8940"
var port := 8940
var player_count := 8
var moving := 8
var run_seconds := 14.0

var _peer := WebSocketMultiplayerPeer.new()
var _players: Array[Puppet] = []
var _net_accum := 0.0
var _input_accum := 0.0
var _tick := 0
var _seq := 0
var _last_sent: Dictionary = {}
var _received := 0
var _received_bytes := 0
var _inputs_in := 0
var _elapsed := 0.0


class Puppet:
	extends Node3D
	var yaw := 0.0
	var anim := 0
	var aim := false
	var pitch := 0.0
	var packed := PackedByteArray()
	var phase := 0.0
	var walking := true


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"server":
				is_server = true
			"mode":
				mode = value
			"port":
				port = int(value)
			"url":
				url = value
			"players":
				player_count = int(value)
			"moving":
				moving = int(value)
			"run-seconds":
				run_seconds = float(value)
	Engine.max_fps = 60
	_build_players()
	multiplayer.multiplayer_peer = null
	if is_server:
		_peer.create_server(port)
		multiplayer.multiplayer_peer = _peer
		print("server mode=%s players=%d moving=%d" % [mode, player_count, moving])
	else:
		_peer.create_client(url)
		multiplayer.multiplayer_peer = _peer
		multiplayer.connected_to_server.connect(func() -> void: print("client connected"))
	(multiplayer as SceneMultiplayer).peer_packet.connect(_on_peer_packet)


func _build_players() -> void:
	for index in player_count:
		var puppet := Puppet.new()
		puppet.name = "P%d" % (index + 1)
		puppet.phase = index * 0.7
		puppet.walking = index < moving
		$Players.add_child(puppet)
		_players.append(puppet)
		if mode in ["sync", "sync_packed", "sync_change"]:
			_add_synchronizer(puppet)


func _add_synchronizer(puppet: Puppet) -> void:
	var config := SceneReplicationConfig.new()
	var paths: Array[String] = [".:position", ".:yaw", ".:anim", ".:aim", ".:pitch"]
	if mode == "sync_packed":
		paths = [".:packed"]
	for path in paths:
		config.add_property(NodePath(path))
		var how := SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		if mode == "sync_change":
			how = SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
		config.property_set_replication_mode(NodePath(path), how)
		config.property_set_spawn(NodePath(path), false)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.replication_interval = 1.0 / NET_HZ
	sync.delta_interval = 1.0 / NET_HZ
	puppet.add_child(sync)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > run_seconds:
		if is_server:
			print("server done, ticks=%d inputs_in=%d" % [_tick, _inputs_in])
		else:
			print("client done, snapshots=%d snapshot_bytes=%d" % [_received, _received_bytes])
		get_tree().quit()
		return
	if is_server:
		_server_step(delta)
	else:
		_client_step(delta)


func _server_step(delta: float) -> void:
	for puppet in _players:
		if puppet.walking:
			puppet.phase += delta
			puppet.position = Vector3(cos(puppet.phase) * 10.0, 0.0, sin(puppet.phase) * 10.0)
			puppet.yaw = fposmod(puppet.phase + PI / 2.0, TAU)
			puppet.anim = 2 + (int(puppet.phase) % 2)
			puppet.aim = int(puppet.phase) % 5 == 0
			puppet.pitch = sin(puppet.phase) * 0.5
	_net_accum += delta
	if _net_accum < 1.0 / NET_HZ - 0.0001:
		return
	_net_accum -= 1.0 / NET_HZ
	_tick += 1
	if mode == "sync_packed":
		for puppet in _players:
			puppet.packed = _encode(puppet)
		return
	if mode == "rpc_bytes" or mode == "send_bytes" or mode == "send_delta":
		var buf := _snapshot(mode == "send_delta")
		for id in multiplayer.get_peers():
			if mode == "rpc_bytes":
				snapshot.rpc_id(id, buf)
			else:
				(multiplayer as SceneMultiplayer).send_bytes(
					buf, id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
				)


func _client_step(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.get_peers().is_empty():
		return
	_input_accum += delta
	if _input_accum < 1.0 / INPUT_HZ - 0.0001:
		return
	_input_accum -= 1.0 / INPUT_HZ
	_seq += 1
	var buf := PackedByteArray()
	buf.resize(12)
	buf.encode_u32(0, _seq)
	buf.encode_s8(4, 100)
	buf.encode_s8(5, -50)
	buf.encode_u16(6, 1234)
	buf.encode_u16(8, 0x81)
	if mode == "send_bytes" or mode == "send_delta":
		(multiplayer as SceneMultiplayer).send_bytes(buf, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	else:
		input.rpc_id(1, buf)


# 12 bytes: id, x y z as centimetres (s16), yaw (u16), anim (u8), flags (u8), pitch (s8).
func _encode(puppet: Puppet) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(11)
	buf.encode_s16(0, roundi(puppet.position.x * 100.0))
	buf.encode_s16(2, roundi(puppet.position.y * 100.0))
	buf.encode_s16(4, roundi(puppet.position.z * 100.0))
	buf.encode_u16(6, roundi(puppet.yaw / TAU * 65535.0))
	buf.encode_u8(8, puppet.anim)
	buf.encode_u8(9, 1 if puppet.aim else 0)
	buf.encode_s8(10, roundi(puppet.pitch / (PI / 2.0) * 127.0))
	return buf


func _snapshot(changed_only: bool) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.append(1)
	buf.resize(6)
	buf.encode_u32(1, _tick)
	var count := 0
	for index in _players.size():
		var entry := _encode(_players[index])
		if changed_only and _last_sent.get(index) == entry:
			continue
		_last_sent[index] = entry
		buf.append(index + 1)
		buf.append_array(entry)
		count += 1
	buf.encode_u8(5, count)
	return buf


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(buf: PackedByteArray) -> void:
	_received += 1
	_received_bytes += buf.size()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func input(_buf: PackedByteArray) -> void:
	_inputs_in += 1


func _on_peer_packet(_id: int, packet: PackedByteArray) -> void:
	if is_server:
		_inputs_in += 1
	else:
		_received += 1
		_received_bytes += packet.size()
