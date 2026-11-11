class_name HandClient
extends RefCounted
## A client a test drives by hand against a `NetServer` over a real socket: it says hello, sends
## the commands it is given, and keeps what the server answered (the WELCOME, a REFUSED, every
## TICK and the frame it came on, the PONGs). `poll` once a physics frame (`NetServerRig` does).

var link := WebSocketLink.new()
var welcome: SnapshotCodec.Welcome
## The `NetWire.Refusal` the server answered, or -1.
var refusal := -1
var ticks: Array[SnapshotCodec.Tick] = []
## The physics frame each TICK came on.
var tick_frames: Array[int] = []
var events: Array[NetEvent] = []
var pongs := 0
var closed := false
var drops := NetDrops.new()
## The `seq` of the next `send_command`.
var next_seq := 1


func _init(clock: Callable) -> void:
	link.clock = clock
	link.packet_received.connect(_on_packet)
	link.closed.connect(_on_closed)


## Closes the link and lets go of its signals (they hold this client, so the two would never be
## freed).
func release() -> void:
	link.close()
	link.poll()
	link.packet_received.disconnect(_on_packet)
	link.closed.disconnect(_on_closed)


func poll() -> void:
	link.poll()


func say_hello(player_name: String, world_hash: int) -> bool:
	return link.send(NetWire.hello(player_name, world_hash))


## Sends `command` numbered `next_seq` (its own `seq` is overwritten).
func send_command(command: PlayerCommand) -> bool:
	command.seq = next_seq
	next_seq += 1
	return link.send(CommandCodec.encode(command))


func last_tick() -> SnapshotCodec.Tick:
	return ticks[-1] if not ticks.is_empty() else null


## The events of `kind` heard so far.
func heard(kind: NetEvent.Kind) -> Array[NetEvent]:
	return events.filter(func(event: NetEvent) -> bool: return event.kind == kind)


func _on_packet(data: PackedByteArray) -> void:
	match NetWire.type_of(data):
		NetWire.Type.WELCOME:
			welcome = SnapshotCodec.read_welcome(data, drops)
		NetWire.Type.REFUSED:
			refusal = NetWire.read_refused(data, drops)
		NetWire.Type.TICK:
			var tick := SnapshotCodec.read_tick(data, drops)
			if tick != null:
				ticks.append(tick)
				tick_frames.append(Engine.get_physics_frames())
				events.append_array(tick.events)
		NetWire.Type.PONG:
			pongs += 1
		_:
			drops.count(NetDrops.UNKNOWN_TYPE)


func _on_closed() -> void:
	closed = true
