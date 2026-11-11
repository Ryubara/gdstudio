@tool
class_name AiRelationEvent
extends Resource
## One kind of act that changes how a faction feels about another (attack a member, kill one,
## help one, trespass), a row of the `AiRelations` event table: what it costs in attitude and who
## has to perceive it for anything to change.

## Who must perceive the act for an attitude to change.
enum Witness {
	## Only factions of the characters that perceived it change (the victim always feels a blow on
	## itself; senses add the rest); an act nobody perceived changes nothing.
	WITNESSED,
	## The victim's faction changes whoever saw it (a mission's script, an alarm).
	ALWAYS,
}

## The name a report gives (`AiFactions.report(&"attack", ...)`).
@export var id := &"attack":
	set(value):
		id = value
		emit_changed()
## How much the witnesses' faction's attitude toward the actor's faction moves (-100 to 100).
@export_range(-200, 200) var delta := -30:
	set(value):
		delta = value
		emit_changed()
## Who must perceive the act.
@export var witness := Witness.WITNESSED:
	set(value):
		witness = value
		emit_changed()
