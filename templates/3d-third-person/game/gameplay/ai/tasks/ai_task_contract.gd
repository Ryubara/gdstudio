@tool
class_name AiTaskContract
extends Resource
## What an AI task is, for an author: the enums, the fields set in the inspector (the contract
## that says who may take a character off the task and what happens then), the runtime fields a
## task script reads, and the virtual methods it overrides. `AiTask` extends it with the part
## the runner drives (time limits, retries, the watchdog), and every task script extends
## `AiTask`, never this class: it is split off only to keep each file one job.
##
## Docs: the kit's `docs/engines/godot/third-person/ai.md#tasks` (the contract table and every
## edge case).

## The layers, highest first: a higher one preempts a lower one, and a lower one is suspended,
## never dropped.
enum Layer { REACTION, RESPONSE, ORDER, ROUTINE, DEFAULT }
## The parts of the body a task drives (bit flags): `MOVE` is the movement channel, `ACTION` aim
## and trigger, `LOOK` the look direction, `SPEAK` the voice.
enum Channel { MOVE = 1, ACTION = 2, LOOK = 4, SPEAK = 8 }
## Who may take the runner off this task.
enum Interruptible { YES, BY_HIGHER_LAYER, NO, FINISH_THEN_REACT }
## What happens to this task when it is taken off.
enum WhenInterrupted { SUSPEND_RESUME, RESTART, ABORT, SKIP_TO_NEXT }
## What damage does while an uninterruptible task runs; `PROFILE` reads the profile's.
enum UnderAttack { PROFILE, IGNORE, FINISH_THEN_REACT, FIGHT_BACK_WHILE, ABORT_ABOVE }
## What a failure does.
enum OnFail { SKIP, RETRY, FALLBACK, PROPAGATE }
## What an incoming task does to a task of its layer (an equal `id` merges unless `QUEUE`).
enum ReplacePolicy { MERGE, REPLACE, QUEUE, IGNORE }
## Where a task is in its life.
enum State { PENDING, RUNNING, SUSPENDED, SUCCEEDED, FAILED, CANCELLED, TIMED_OUT }
## What `update()` returns. `INVALID` is 0 on purpose: a typed function that hits a script error
## returns 0, so the runner's watchdog reads an error as `INVALID`.
enum Status { INVALID, RUNNING, SUCCEEDED, FAILED }
## What `resume()` returns (`INVALID`, 0, is a script error as above).
enum Resume { INVALID, RESUME, RESTART, SUCCEEDED, FAILED }
## Why a task failed or was cancelled.
enum Reason {
	NONE,
	NO_PATH,
	TARGET_LOST,
	BLOCKED,
	NO_AMMO,
	TIMED_OUT,
	ATTACKED,
	INVALID,
	STALE,
	REFUSED,
	EXPIRED,
	CANCELLED,
	REPLACED,
	REVOKED,
}

## The authority of an order from a squad, a mission and a script (an order with more replaces
## one with less; `authority` takes any number).
const AUTHORITY_SQUAD := 10
const AUTHORITY_MISSION := 20
const AUTHORITY_SCRIPT := 30
## Names for logs and the debug overlay.
const LAYER_NAMES: Array[String] = ["Reaction", "Response", "Order", "Routine", "Default"]
const STATE_NAMES: Array[String] = [
	"Pending", "Running", "Suspended", "Succeeded", "Failed", "Cancelled", "Timed out"
]
const REASON_NAMES: Array[String] = [
	"",
	"no path",
	"target lost",
	"blocked",
	"no ammo",
	"timed out",
	"attacked",
	"invalid",
	"stale",
	"refused",
	"expired",
	"cancelled",
	"replaced",
	"revoked",
]

@export_group("Task")
## What kind of task this is: two tasks with the same id in a layer are one (the second merges
## into the first), and the id is what the network sends of the active task.
@export var id := &""
## The layer it runs in.
@export var layer := Layer.ROUTINE
## The channels it drives; two tasks that run at once never share one.
@export_flags("Move", "Action", "Look", "Speak") var channels := 1

@export_group("Interruption")
## Who may take the runner off it: anything, only a higher layer, nothing (must complete; events
## wait until it ends), or nothing until it finishes and then the reaction.
@export var interruptible := Interruptible.YES
## What happens to it when taken off: suspended and resumed later, restarted later, dropped, or
## dropped so its sequence goes on with the next step.
@export var when_interrupted := WhenInterrupted.SUSPEND_RESUME
## After an interruption longer than this, it is asked `still_valid()` before it resumes, and
## ends `STALE` if not; 0 resumes it whatever the time.
@export_range(0.0, 600.0, 0.1, "suffix:s") var resume_valid_for := 0.0
## What damage does while it runs uninterruptible: nothing, an attack once it ends, fire back on
## the action channel while it finishes, or abort past `abort_damage` in `abort_window`.
@export var under_attack := UnderAttack.PROFILE
## Damage within `abort_window` that aborts it under `ABORT_ABOVE`.
@export_range(0.0, 1000.0, 0.5) var abort_damage := 20.0
## The window `abort_damage` is summed over.
@export_range(0.05, 30.0, 0.05, "suffix:s") var abort_window := 1.0
## Survives `clear()` (a reaction or a response clearing the stack) unless forced.
@export var persistent := false
## Lets a response (an event's task) take over while it runs; off blocks responses, not
## reactions.
@export var reactive := true
## What it does to a task already in its layer: merge into one with the same id (else replace),
## replace it, queue behind it, or drop itself. An order follows its `authority` instead.
@export var replace_policy := ReplacePolicy.MERGE

@export_group("Time")
## Seconds after which it is asked to wrap up (`on_timeout()`); 0 never asks.
@export_range(0.0, 600.0, 0.1, "suffix:s") var timeout := 0.0
## Seconds after which it ends `TIMED_OUT` whatever it is doing; -1 takes the profile's, 0 never
## (only for a task that ends on a condition: see `ends_on_condition`).
@export_range(-1.0, 3600.0, 0.1, "suffix:s") var hard_timeout := -1.0
## It ends on a condition of its own (guard until relieved), so no hard timeout is fine.
@export var ends_on_condition := false
## A task that has not started this many seconds after it was assigned is dropped (an order
## given while the character was dead); 0 never expires.
@export_range(0.0, 600.0, 0.1, "suffix:s") var expires_after := 0.0

@export_group("Failure")
## What a failure does: the next task takes over, it tries again, a fallback task runs in its
## place, or its parent fails too.
@export var on_fail := OnFail.SKIP
## Tries after the first under `RETRY`.
@export_range(0, 100) var retry_count := 1
## Seconds before a retry.
@export_range(0.0, 60.0, 0.05, "suffix:s") var retry_delay := 0.5
## The task that runs in its place under `FALLBACK`.
@export var fallback: AiTask

@export_group("Order")
## Who may replace it in the ORDER layer: a higher authority replaces, an equal one replaces the
## older, a lower one waits behind it (`AUTHORITY_SQUAD`, `AUTHORITY_MISSION`, `AUTHORITY_SCRIPT`).
@export_range(0, 100) var authority := 0
## The need it serves (a belief such as `&"ammo"`), so `AiNeeds` decides whether an order gives way
## to it; empty for an ordinary task.
@export var need := &""

## Where it is in its life.
var state := State.PENDING
## Why it failed or was cancelled.
var reason := Reason.NONE
## Who asked for it (a node, or a name such as `&"mission"`).
var issuer: Variant = null
## What it is about (a node it follows, attacks or looks at); its instance id is what the network
## sends.
var target: Object = null
## Where it goes, for a task with a place.
var goal := Vector3.ZERO
## Seconds it has run since it started (frozen while suspended).
var elapsed := 0.0
## The character it runs on, and the controller whose channels it writes (null in a bare test).
var character: Node = null
var controller: AiController = null
## Runner times (`AiTaskRunner.world_time`) of its assignment, its start and its last suspension.
var assigned_at := 0.0
var started_at := 0.0
var suspended_at := 0.0


## Starts the task (called once, and again on a restart). Override.
func start() -> void:
	pass


## One step, `delta` seconds after the last: RUNNING, SUCCEEDED or FAILED (set `reason` first).
## Override; the base succeeds at once.
func update(_delta: float) -> Status:
	return Status.SUCCEEDED


## Called when it is taken off and kept to resume. Override.
func suspend() -> void:
	pass


## Called when it comes back: carry on, start over, or the goal was reached or lost meanwhile (a
## movement task asks for its path again here). Override.
func resume() -> Resume:
	return Resume.RESUME


## Whether it still makes sense after a long interruption (`resume_valid_for`). Override.
func still_valid() -> bool:
	return true


## The soft timeout: wrap up. Override.
func on_timeout() -> void:
	pass


## Called when it is dropped before it ended. Override.
func cancel() -> void:
	pass


## A task with the same id arrived in its layer: take what is new from it (a chase gets the new
## goal). Override to take more; the base takes the target, the goal and the issuer.
func merge(incoming: AiTaskContract) -> void:
	target = incoming.target
	goal = incoming.goal
	if incoming.issuer != null:
		issuer = incoming.issuer


## Whether it may run now; the runner passes over a head that may not to the next layer down.
## Override.
func can_run() -> bool:
	return true


## Whether it ends on its own (a count, a condition), so it needs no hard timeout. Composites
## override it.
func has_end_condition() -> bool:
	return ends_on_condition


## The channels it and its children drive. Composites add their children's.
func claimed_channels() -> int:
	return channels


## Its id, or its script's file name when it has none, for logs and warnings.
func display_label() -> String:
	if id != &"":
		return String(id)
	var source := get_script() as Script
	return source.resource_path.get_file().get_basename() if source != null else "AiTask"


## True once it ended (succeeded, failed, cancelled or timed out).
func is_done() -> bool:
	return state >= State.SUCCEEDED


## The instance id of `target`, or 0: what replication sends with the task's id.
func target_id() -> int:
	return target.get_instance_id() if is_instance_valid(target) else 0


## What an author should fix: a task that never ends, a fallback missing, a fight-back that
## claims the action channel. The `AiTasks` node shows them as configuration warnings.
func authoring_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	var label := display_label()
	var forever_ok := layer == Layer.ROUTINE or layer == Layer.DEFAULT
	if hard_timeout == 0.0 and not has_end_condition() and not forever_ok:
		problems.append(
			"%s: no timeout and no end condition: it can hold the layer forever" % label
		)
	if on_fail == OnFail.FALLBACK and fallback == null:
		problems.append("%s: on_fail is FALLBACK but no fallback task is set" % label)
	if under_attack == UnderAttack.FIGHT_BACK_WHILE and claimed_channels() & Channel.ACTION:
		problems.append("%s: FIGHT_BACK_WHILE needs the action channel free" % label)
	return problems
