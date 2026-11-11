@tool
class_name AiSituationRule
extends Resource
## What one situation lets through in an `AiBehaviourSet`: the event kinds it blocks (an Engaged
## guard does not turn for a footstep: GTA's "block non-temporary events", our words) and the task
## layers it keeps open (a reaction asking for a task in a closed layer is not placed).

@export_enum("Unaware", "Suspicious", "Alert", "Engaged", "Fleeing") var situation := 0
## The events it ignores while in this situation.
@export var blocks: Array[StringName] = []
## The layers a reaction may place a task in.
@export_flags("Reaction", "Response", "Order", "Routine", "Default") var open_layers := 31
