class_name TriggerZoneNet
extends NetEntity
## Puts the `TriggerZone` it sits under in an online game: the server's copy senses the bodies and
## says each change, a client's copy senses nothing and paints its plate from the server's records
## (`TriggerZone.sensing`, `show_active`), so every player sees the pad pressed by any player and a
## late joiner sees it pressed at once. Offline the zone works as it always did.
##
## Add `trigger_zone_net.tscn` under a zone whose state is a rule of the game (the pressure pad
## that opens a door), never under one that a single screen uses (a `CameraZone`'s, which follows
## that screen's own player). The zone's `activated` and `deactivated` fire only where it senses:
## offline, and on the server, where the rules they drive run.


func _ready() -> void:
	var zone := part() as TriggerZone
	if zone == null:
		push_warning("TriggerZoneNet needs a TriggerZone as its parent.")
		return
	serve(net_write, net_read, net_set_role)
	zone.activated.connect(func(_body: Node3D) -> void: report())
	zone.deactivated.connect(report)


## Who runs the zone (`NetWorld` sets it): a client's copy senses no body.
func net_set_role(as_role: NetEntity.Role) -> void:
	(part() as TriggerZone).sensing = as_role != NetEntity.Role.CLIENT


## The state: u8 1 while something stands in the zone. 1 byte.
func net_write(_at_tick: int) -> PackedByteArray:
	return PackedByteArray([1 if (part() as TriggerZone).is_active() else 0])


## Reads a state (false for one that is not a zone's) and paints the plate with it.
func net_read(state: PackedByteArray, _at_tick: int) -> bool:
	if state.size() != 1:
		return false
	(part() as TriggerZone).show_active(state[0] != 0)
	return true
