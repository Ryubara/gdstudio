class_name AiBelief
extends RefCounted
## What one AI character believes about one entity: where it was last, how it moved, when, how
## sure it is and how it knows (seen, heard, told by an ally, or touched by a blow), with its
## awareness (0 to 1) and whether it has noticed it yet. `AiSenses` writes it on its think; the
## brain (tasks, decisions) reads it and never the world. A belief that is not `seen_now` is a
## memory: it is searched for at `last_position`, never fired on.

enum Source { SEEN, HEARD, TOLD, TOUCHED }

## The names of the sources, for the debug view and logs.
const SOURCE_NAMES: Array[String] = ["seen", "heard", "told", "touched"]

## The entity's instance id (0: a noise with no known source, "something").
var entity_id := 0
## The entity's faction member, kept for the relationship lookups; null when it has none.
var member: AiFactionMember
## The band of the believer toward the entity (`AiRelations.Band`) when it was last read.
var band := AiRelations.Band.NEUTRAL
## Where the entity was when last perceived (for a noise, where the noise was).
var last_position := Vector3.ZERO
## How it moved when last seen (zero when heard, told or felt).
var velocity := Vector3.ZERO
## The senses' clock (seconds) when it was last perceived.
var time := 0.0
## How sure the believer is of `last_position`, 0 to 1: 1 while seen, falling as the memory ages.
var confidence := 0.0
## How it was last perceived (`Source`).
var source := Source.SEEN
## How aware of it the believer is, 0 to 1: rises while it is seen, falls when it is not.
var awareness := 0.0
## True while it is in sight with a clear line (on the last think that looked at it).
var seen_now := false
## True once awareness reached 1 (or a blow or an ally made it so): the reaction delay runs.
var noticed := false
## True once noticed and the reaction delay has passed: the brain may act on it.
var believed := false
## The senses' clock when it was noticed, and when the reaction delay ends.
var noticed_at := -1.0
var react_at := -1.0
## The senses' clock of the first clear line to it (-1: never seen).
var first_clear_at := -1.0
## True once `AiSenses.suspicious` was said for it (awareness crossed `suspicious_at`).
var said_suspicious := false

var _entity: WeakRef


## The entity, or null when it is gone (or the belief has none).
func entity() -> Node3D:
	return _entity.get_ref() as Node3D if _entity != null else null


## Points the belief at `node` (its instance id and a weak reference).
func set_entity(node: Node3D) -> void:
	_entity = weakref(node) if node != null else null
	entity_id = node.get_instance_id() if node != null else 0


## True when the brain may shoot at it: believed and in sight now. A memory never is.
func can_fire_at() -> bool:
	return believed and seen_now and entity() != null


## The belief in one line, for logs and the determinism test: the entity's name, the source,
## awareness, confidence and the position to the centimetre.
func describe() -> String:
	var node := entity()
	var who := String(node.name) if node != null else "something"
	return (
		"%s %s a=%.3f c=%.3f seen=%s noticed=%s believed=%s at=(%.2f, %.2f, %.2f)"
		% [
			who,
			SOURCE_NAMES[source],
			awareness,
			confidence,
			seen_now,
			noticed,
			believed,
			last_position.x,
			last_position.y,
			last_position.z,
		]
	)
