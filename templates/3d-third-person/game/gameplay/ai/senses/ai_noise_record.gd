class_name AiNoiseRecord
extends RefCounted
## One noise on the level's `AiNoise` board: its kind, where, how loud and how far it carries,
## and what made it (a weak reference, with its faction member for the listeners' filter).

## The board's serial of the noise (they only grow).
var serial := 0
## The kind (`AiNoise.FOOTSTEP`, `SHOT`, ...), a key of the board's `radii`.
var kind := &""
## Where it was made.
var position := Vector3.ZERO
## How loud, 1 for the kind's radius.
var loudness := 1.0
## Metres it carries for a listener of the board's reference hearing (radius × loudness).
var radius := 0.0
## The faction member of what made it; null for a noise with no source or one in no faction.
var member: AiFactionMember
## The faction id of its member when it was made (`&""` with no member): the board's index.
var faction := &""
## The physics frame it was made on.
var frame := 0

var _source: WeakRef


## What made it, or null (an explosion, an impact, or a source gone since).
func source() -> Node3D:
	return _source.get_ref() as Node3D if _source != null else null


## Sets what made it (and its faction member).
func set_source(node: Node3D) -> void:
	_source = weakref(node) if node != null else null
	member = AiFactionMember.of(node)
	faction = member.faction_id() if member != null else &""


## True when something made it and is gone since: freed (its `member` is gone with it), or out of
## the tree (a body back in its spawner's pool: nobody to believe in, and no position to read).
func maker_gone() -> bool:
	if _source == null:
		return false
	var maker := _source.get_ref() as Node
	return maker == null or not maker.is_inside_tree()
