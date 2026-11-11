@tool
class_name AiTasks
extends Node
## The thin node that gives an `AiCharacter` its tasks: a child of the character, set as its
## `task_runner` slot, owning one `AiTaskRunner` (the logic, which needs no scene). On each think
## of the character it steps the runner; the character's death pauses it and a revive resumes it;
## a hit is reported as damage. At the start it assigns `default_task` and `routine`; everything
## else assigns through `runner.assign(task, issuer)` (a reaction, a mission, a squad, the player).
##
## With the character's `debug` on, `label` shows the layer stack above the head (the active
## task marked), written only on a think while on.

@export_group("Tasks")
## What it does when given nothing else (DEFAULT layer: stand, look around); also what runs while
## a failure storm holds orders and routines back.
@export var default_task: AiTask:
	set(value):
		default_task = value
		update_configuration_warnings()
## What it does from the start (ROUTINE layer: a patrol, a job), resumed after every interruption.
@export var routine: AiTask:
	set(value):
		routine = value
		update_configuration_warnings()
## The task assigned against an attacker it could not answer during a task that must complete,
## and run on the action channel beside one that allows firing back; empty sends only the
## runner's `attacker_pending` signal.
@export var attack_task: AiTask:
	set(value):
		attack_task = value
		update_configuration_warnings()
## The table of needs against orders; empty: an order never gives way to a need.
@export var needs: AiNeeds

@export_group("Debug")
## The label that shows the layer stack while the character's `debug` is on.
@export var label: Label3D

## The runner: the tasks, the contract, the decisions.
var runner := AiTaskRunner.new()

var _character: AiCharacter = null
var _shown := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_character = get_parent() as AiCharacter
	if _character != null:
		runner.character = _character
		runner.controller = _character.ai_controller()
		_character.thought.connect(_on_thought)
		_character.died.connect(runner.set_can_think.bind(false))
		_character.revived.connect(runner.set_can_think.bind(true))
		_character.took_hit.connect(_on_took_hit)
	_sync()
	if default_task != null:
		runner.assign(default_task.fresh_copy(), self)
	if routine != null:
		runner.assign(routine.fresh_copy(), self)
	_show()


## Starts the tasks over as at the start (a pooled character spawned again): the runner forgets
## everything, then `default_task` and `routine` are assigned again.
func restart() -> void:
	runner.reset()
	_sync()
	if default_task != null:
		runner.assign(default_task.fresh_copy(), self)
	if routine != null:
		runner.assign(routine.fresh_copy(), self)
	_show()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for task: AiTask in [default_task, routine, attack_task]:
		if task != null:
			warnings.append_array(task.authoring_problems())
	return warnings


## One think of the character, `seconds` after the last: the runner steps with the character's
## profile, the needs table and the attack task as they are now (an edit applies at once).
func think(seconds: float) -> void:
	_sync()
	runner.tick(seconds)
	_show()


func _on_thought(seconds: float) -> void:
	think(seconds)


func _on_took_hit(amount: float, source: Node3D) -> void:
	runner.report_damage(amount, source)


func _sync() -> void:
	if _character != null and _character.profile != null:
		runner.profile = _character.profile
	runner.needs = needs
	runner.attack_task = attack_task


func _show() -> void:
	if label == null:
		return
	var on := _character != null and _character.debug
	label.visible = on
	if not on:
		return
	var text := runner.describe_text()
	if text != _shown:
		_shown = text
		label.text = text
