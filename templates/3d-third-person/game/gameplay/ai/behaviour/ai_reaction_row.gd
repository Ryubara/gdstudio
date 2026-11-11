@tool
class_name AiReactionRow
extends Resource
## One row of an `AiBehaviourSet`, the router's table: when `event` happens about a subject in one
## of `bands` (the character's band toward it), while the situation is one of `situations` and the
## play state one of `play_states`, with at least `min_awareness` and the courage in
## `min_courage`..`max_courage`, it answers with a copy of `task` (placed in the task's own layer)
## at `chance`, and may move the situation to `enter`. The first row that matches answers; a row
## whose chance fails passes the event to the rows below it.
##
## Docs: the kit's `docs/engines/godot/third-person/ai-behaviour.md#router`.

## What scales `chance`: nothing, the profile's courage, its fear (1 - courage), its aggression or
## its curiosity.
enum Scale { NONE, COURAGE, FEAR, AGGRESSION, CURIOSITY }
## Where the task's goal comes from: the event's place, the character's home (where it started),
## or its leader (`AiBrain.leader`).
enum Place { EVENT, HOME, LEADER }

## The event it answers (`AiBehaviourSet.EVENTS`).
@export var event := &"noticed"
## The character's band toward the subject (a subject-less event counts as Neutral).
@export_flags("Hostile", "Unfriendly", "Neutral", "Friendly", "Allied") var bands := 31
## The situations it answers in.
@export_flags("Unaware", "Suspicious", "Alert", "Engaged", "Fleeing") var situations := 31
## The play states it answers in.
@export_flags("Aggressive", "Careful", "Safe") var play_states := 7
## For a `heard` row, the kinds of noise it answers (`AiNoise.SHOT`, `FOOTSTEP`...); empty: any
## noise (and any other event).
@export var noises: Array[StringName] = []
## The least awareness of the subject (0 to 1) it needs.
@export_range(0.0, 1.0, 0.01) var min_awareness := 0.0
## The profile's courage it needs, from and to.
@export_range(0.0, 1.0, 0.01) var min_courage := 0.0
@export_range(0.0, 1.0, 0.01) var max_courage := 1.0
## The chance it answers (scaled by `chance_scale`); a failed roll passes to the next row.
@export_range(0.0, 1.0, 0.01) var chance := 1.0
@export var chance_scale := Scale.NONE
## The task it answers with (a template: the character runs a copy, its target the subject and
## its goal the place below).
@export var task: AiTask
## Where the task's goal is.
@export var place := Place.EVENT
## The situation it moves to (requested: rising is at once, calming waits the dwell); `None`
## leaves it.
@export_enum("None", "Unaware", "Suspicious", "Alert", "Engaged", "Fleeing") var enter := 0
## Why the row is there, for the next author.
@export_multiline var note := ""


## True when it is about `event` in this cell (band, situation, play state, awareness, courage),
## and for a heard noise, about its kind (`noise`).
func matches(
	what: StringName,
	band: int,
	situation: int,
	play: int,
	awareness: float,
	courage: float,
	noise := &""
) -> bool:
	return (
		what == event
		and (noises.is_empty() or noises.has(noise))
		and bands & (1 << band)
		and situations & (1 << situation)
		and play_states & (1 << play)
		and awareness >= min_awareness
		and courage >= min_courage
		and courage <= max_courage
	)


## The chance it answers for `profile`.
func chance_for(profile: AiProfile) -> float:
	if profile == null:
		return chance
	match chance_scale:
		Scale.COURAGE:
			return chance * profile.courage
		Scale.FEAR:
			return chance * (1.0 - profile.courage)
		Scale.AGGRESSION:
			return chance * profile.aggression
		Scale.CURIOSITY:
			return chance * profile.curiosity
	return chance


## True when it asks for something: a task or a change of situation.
func asks_for_something() -> bool:
	return task != null or enter > 0


## True when nothing may keep it from answering a matching cell: chance 1, unscaled, any courage.
func is_sure() -> bool:
	return (
		chance >= 1.0
		and noises.is_empty()
		and chance_scale == Scale.NONE
		and min_courage <= 0.0
		and max_courage >= 1.0
		and min_awareness <= 0.0
	)
