@tool
class_name AiReactionWaiver
extends Resource
## A written "nothing to do" in an `AiBehaviourSet`: the cells of `event` x `bands` x
## `situations` that no row answers, with the `reason` (the senses never deliver it, the set never
## enters that situation). The coverage test reads rows and waivers together: every cell asks for
## something or says here why not.

## The event it waives (`AiBehaviourSet.EVENTS`).
@export var event := &"noticed"
@export_flags("Hostile", "Unfriendly", "Neutral", "Friendly", "Allied") var bands := 0
@export_flags("Unaware", "Suspicious", "Alert", "Engaged", "Fleeing") var situations := 0
## Why nothing answers these cells; a waiver with no reason is not one.
@export_multiline var reason := ""


## True when it waives the cell.
func covers(what: StringName, band: int, situation: int) -> bool:
	return (
		what == event
		and bands & (1 << band)
		and situations & (1 << situation)
		and not reason.strip_edges().is_empty()
	)
