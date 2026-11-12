@tool
class_name AiBehaviourSet
extends Resource
## How one kind of AI character answers what happens to it: the router's table (`rows`), the
## cells it answers with nothing on purpose (`waivers`), what each situation blocks
## (`situation_rules`) and the task it falls back on (`default_task`). An `AiBrain` routes each
## event through it; the brain has no branch for any behaviour, so a new behaviour is a task script
## and a row here. Shipped: `sets/hostile_guard.tres`, `friendly_ally.tres`, `civilian.tres`.
##
## Docs: the kit's `docs/engines/godot/third-person/ai-behaviour.md#router`.

## The events an `AiBrain` routes.
const SPAWNED := &"spawned"
const NOTICED := &"noticed"
const SUSPICIOUS := &"suspicious"
const HEARD := &"heard"
const HIT := &"hit"
const LOST_SIGHT := &"lost_sight"
const LOST_TRAIL := &"lost_trail"
const FORGOT := &"forgot"
const HURT := &"hurt"
const NO_AMMO := &"no_ammo"
const LINK := &"link"
const ORDER_GO := &"order_go"
const ORDER_HOLD := &"order_hold"
const ORDER_USE := &"order_use"
const EVENTS: Array[StringName] = [
	SPAWNED,
	NOTICED,
	SUSPICIOUS,
	HEARD,
	HIT,
	LOST_SIGHT,
	LOST_TRAIL,
	FORGOT,
	HURT,
	NO_AMMO,
	LINK,
	ORDER_GO,
	ORDER_HOLD,
	ORDER_USE,
]
## The situations a row may name (Dead routes nothing).
const ROUTED_SITUATIONS := 5
## The bands (`AiRelations.Band`) and the play states (`AiPlayState.State`).
const BANDS := 5
const PLAY_STATES := 3

## The name shown in the debug overlay.
@export var display_name := "Behaviour"
## The table, read top down: the first row that matches answers.
@export var rows: Array[AiReactionRow] = []
## The cells answered with nothing on purpose, each with its reason.
@export var waivers: Array[AiReactionWaiver] = []
## What each situation blocks and keeps open; a situation with no rule blocks nothing.
@export var situation_rules: Array[AiSituationRule] = []
## The task in the DEFAULT layer from the start (stand guard, look around).
@export var default_task: AiTask


## The row that answers `event` in this cell, or null. `roll` is called (with no argument, giving
## 0 to 1) for each row whose chance is under 1. `noise` is the kind of a heard noise.
func pick(
	event: StringName,
	band: int,
	situation: int,
	play: int,
	awareness: float,
	profile: AiProfile,
	roll: Callable,
	noise := &""
) -> AiReactionRow:
	var courage := profile.courage if profile != null else 0.5
	for row in rows:
		if row == null or not row.matches(event, band, situation, play, awareness, courage, noise):
			continue
		var chance := row.chance_for(profile)
		if chance >= 1.0 or (chance > 0.0 and float(roll.call()) < chance):
			return row
	return null


## True when `situation` blocks `event`.
func blocks(situation: int, event: StringName) -> bool:
	var rule := _rule(situation)
	return rule != null and rule.blocks.has(event)


## True when `situation` lets a reaction place a task in `layer` (`AiTask.Layer`).
func layer_open(situation: int, layer: int) -> bool:
	var rule := _rule(situation)
	return rule == null or rule.open_layers & (1 << layer) != 0


## How the cell `event` x `band` x `situation` is covered, over every play state: "" when some
## play state has no row sure to answer (chance 1, unscaled, any courage) and no waiver or block
## says why, else the name of the last row found.
func coverage(event: StringName, band: int, situation: int) -> String:
	if blocks(situation, event):
		return "blocked"
	for waiver in waivers:
		if waiver != null and waiver.covers(event, band, situation):
			return "waived: " + waiver.reason
	var answer := ""
	for play in PLAY_STATES:
		var found := ""
		for row in rows:
			if row == null or not row.asks_for_something() or not row.is_sure():
				continue
			if row.matches(event, band, situation, play, 1.0, 0.5):
				found = row.task.display_label() if row.task != null else "situation"
				break
		if found.is_empty():
			return ""
		answer = found
	return answer


## Every task template the set can hand out (rows, the default, and their children and fallbacks).
func tasks() -> Array[AiTask]:
	var found: Array[AiTask] = []
	if default_task != null:
		_collect(default_task, found)
	for row in rows:
		if row != null and row.task != null:
			_collect(row.task, found)
	return found


func _rule(situation: int) -> AiSituationRule:
	for rule in situation_rules:
		if rule != null and rule.situation == situation:
			return rule
	return null


static func _collect(task: AiTask, into: Array[AiTask]) -> void:
	into.append(task)
	if task.fallback != null:
		_collect(task.fallback, into)
	if task is AiTaskComposite:
		for child in (task as AiTaskComposite).children:
			if child != null:
				_collect(child, into)
