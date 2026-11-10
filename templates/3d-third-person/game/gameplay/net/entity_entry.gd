class_name EntityEntry
extends RefCounted
## One networked world part as a WELCOME lists it: its id, what kind of part it is and the bytes
## of its state (at most `NetLimits.MAX_ENTITY_STATE`). The table is empty until the map's parts
## are networked (issue 7 of the networking research).

## The part's id in this map (two bytes).
var id := 0
## The kind of part (a byte the part's own code defines).
var kind := 0
## The part's state as the part writes it.
var state := PackedByteArray()


static func make(entity_id: int, entity_kind: int, entity_state: PackedByteArray) -> EntityEntry:
	var entry := EntityEntry.new()
	entry.id = entity_id
	entry.kind = entity_kind
	entry.state = entity_state
	return entry
