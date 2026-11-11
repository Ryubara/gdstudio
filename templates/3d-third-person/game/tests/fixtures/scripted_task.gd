class_name ScriptedTask
extends AiTask
## A task for the task suites: it makes progress for `run_for` seconds and then succeeds (or
## fails with `fail_with`), answers `resume()` with `resume_answer`, may write the movement and
## action channels, may hit a script error on purpose, and counts every call the runner makes.
## Its fields are exports so a copy (a fallback, an attack task) keeps them.

## Seconds of progress before it ends; 0 runs until something ends it.
@export var run_for := 1.0
## The reason it fails with when `run_for` is reached; NONE succeeds.
@export var fail_with := Reason.NONE
## What `resume()` answers (and the reason it sets when that is FAILED: `resume_reason`).
@export var resume_answer := Resume.RESUME
@export var resume_reason := Reason.NONE
## What `still_valid()` answers.
@export var valid := true
## Written to the movement channel on each step while not zero.
@export var walk := Vector3.ZERO
## Holds the trigger on each step.
@export var shoots := false
## Hits a script error in `update()`.
@export var breaks := false

var starts := 0
var updates := 0
var suspends := 0
var resumes := 0
var cancels := 0
var timeouts := 0
var merges := 0
## Seconds of progress since the last start (kept while suspended).
var progress := 0.0


## A task named `task_id` in `on_layer` that ends after `seconds` (0: never on its own).
static func make(task_id: StringName, on_layer: Layer, seconds: float) -> ScriptedTask:
	var task := ScriptedTask.new()
	task.id = task_id
	task.layer = on_layer
	task.run_for = seconds
	task.ends_on_condition = seconds <= 0.0
	return task


func start() -> void:
	starts += 1
	progress = 0.0


func update(delta: float) -> Status:
	updates += 1
	if breaks:
		var missing: Object = null
		missing.call(&"no_such_method")
	progress += delta
	if controller != null:
		if walk != Vector3.ZERO:
			controller.walk_direction = walk
		if shoots:
			controller.fire = true
	if run_for > 0.0 and progress >= run_for - 0.0001:
		if fail_with != Reason.NONE:
			reason = fail_with
			return Status.FAILED
		return Status.SUCCEEDED
	return Status.RUNNING


func suspend() -> void:
	suspends += 1


func resume() -> Resume:
	resumes += 1
	if resume_answer == Resume.FAILED:
		reason = resume_reason
	return resume_answer


func still_valid() -> bool:
	return valid


func on_timeout() -> void:
	timeouts += 1


func cancel() -> void:
	cancels += 1


func merge(incoming: AiTaskContract) -> void:
	super(incoming)
	merges += 1
