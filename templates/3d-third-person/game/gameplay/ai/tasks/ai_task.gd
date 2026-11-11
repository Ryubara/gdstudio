@tool
class_name AiTask
extends AiTaskContract
## One thing an AI character does (walk a route, wait, investigate a noise, follow an order): the
## data an author sets in the inspector and the script that runs it. An `AiTaskRunner` holds the
## tasks of one character in five layers and runs the head of the highest one; the fields below
## are the contract that says who may take the character off a task and what happens then.
##
## A task script extends this class (or a composite: `AiTaskSequence`, `AiTaskParallel`,
## `AiTaskRepeat`, `AiTaskSelector`) and overrides the virtual methods: `start()`,
## `update(delta) -> Status`, `suspend()`, `resume() -> Resume`, `still_valid()`, `on_timeout()`,
## `cancel()`, `merge(incoming)` and `can_run()`. It drives the body only through the
## `AiController` channels it claims (`controller`), never the command; the runner lets go of a
## channel when the task stops, so a suspended walk does not keep walking.
##
## A task authored in a file or a scene is a template: the runner runs a copy of it, so one
## `.tres` serves every character. A task made in code (`MyTask.new()`) runs as it is the first
## time it is assigned. Runtime fields (`target`, `goal`) carry over into the copy.
##
## Docs: the kit's `docs/engines/godot/third-person/ai.md#tasks` (the contract table and every
## edge case).

## The hard timeout of a task with none of its own and no profile (the profile's default).
const DEFAULT_HARD_TIMEOUT := 30.0

var _owned := false
var _soft_fired := false
var _retries := 0
var _retry_wait := -1.0
var _restart := false
var _running_fallback: AiTask = null
var _runner_ref: WeakRef = null
var _profile: AiProfile = null


## The runner it runs in, or null.
func runner() -> AiTaskRunner:
	return _runner_ref.get_ref() as AiTaskRunner if _runner_ref != null else null


## The profile of the character it runs on (set at each step), or null.
func run_profile() -> AiProfile:
	return _profile


## The runner's world time (`AiTaskRunner.world_time`), or 0 without a runner.
func run_time() -> float:
	var at := runner()
	return at.world_time if at != null else 0.0


## The hard timeout in force: its own, or the profile's for -1.
func hard_limit(profile: AiProfile) -> float:
	if hard_timeout >= 0.0:
		return hard_timeout
	return profile.task_hard_timeout if profile != null else DEFAULT_HARD_TIMEOUT


## The copy the runner runs: itself when made in code and not yet run, else a deep copy with the
## runtime target, goal and issuer carried over.
func copy_for_run() -> AiTask:
	if not _owned and resource_path.is_empty():
		_owned = true
		return self
	var copy := fresh_copy()
	copy._owned = true
	return copy


## A new deep copy of it (children and fallback too) that has not run, with the runtime target,
## goal and issuer carried over: how a runner hands out a task it keeps as a template.
func fresh_copy() -> AiTask:
	var copy := duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as AiTask
	copy.target = target
	copy.goal = goal
	copy.issuer = issuer
	return copy


## Back to before it started (a restart, a repeat), runtime target and goal kept.
func reset() -> void:
	state = State.PENDING
	reason = Reason.NONE
	elapsed = 0.0
	_soft_fired = false
	_retries = 0
	_retry_wait = -1.0
	_restart = false
	_running_fallback = null


## Binds it (and its children) to a runner, a character and a controller before it runs.
func bind(to: AiTaskRunner, body: Node, channels_of: AiController) -> void:
	_runner_ref = weakref(to) if to != null else null
	character = body
	controller = channels_of


## Runs one step under the contract: starts it, counts its time, fires the soft timeout, ends it
## at the hard timeout, catches a script error (`INVALID`) and applies `on_fail`. Returns RUNNING,
## SUCCEEDED or FAILED (`state` says which kind of end). The runner and the composites call it.
func advance(delta: float, profile: AiProfile) -> Status:
	_profile = profile
	if (_retry_wait >= 0.0 or state == State.PENDING) and not _ready_to_step(delta):
		return Status.RUNNING
	if _running_fallback != null:
		return _advance_fallback(delta, profile)
	elapsed += delta
	if timeout > 0.0 and not _soft_fired and elapsed >= timeout:
		_soft_fired = true
		on_timeout()
	var limit := hard_timeout
	if limit < 0.0:
		limit = profile.task_hard_timeout if profile != null else DEFAULT_HARD_TIMEOUT
	if limit > 0.0 and elapsed >= limit:
		return _fail(Reason.TIMED_OUT, State.TIMED_OUT)
	var result: Variant = update(delta)
	if result is int and result == Status.RUNNING:
		return Status.RUNNING
	return _judge(result)


## Takes it off and keeps it: the contract's `when_interrupted` decides whether it resumes or
## starts again. Called by the runner and by a composite for its running child.
func pause(now: float) -> void:
	if state != State.RUNNING:
		return
	state = State.SUSPENDED
	suspended_at = now
	_restart = when_interrupted == WhenInterrupted.RESTART
	if _running_fallback != null:
		_running_fallback.pause(now)
	suspend()


## Brings it back after `pause()`: RESUME (carry on), RESTART, SUCCEEDED or FAILED (with
## `reason` set), after the validity check of `resume_valid_for`.
func unpause(now: float) -> Resume:
	if state != State.SUSPENDED:
		return Resume.RESUME
	if _restart:
		reset()
		return Resume.RESTART
	if resume_valid_for > 0.0 and now - suspended_at > resume_valid_for and not still_valid():
		reason = Reason.STALE
		state = State.FAILED
		return Resume.FAILED
	var answer: Variant = resume()
	match answer:
		Resume.RESUME:
			state = State.RUNNING
		Resume.RESTART:
			reset()
		Resume.SUCCEEDED:
			state = State.SUCCEEDED
		Resume.FAILED:
			reason = reason if reason != Reason.NONE else Reason.STALE
			state = State.FAILED
		_:
			reason = Reason.INVALID
			state = State.FAILED
			return Resume.FAILED
	if _running_fallback != null and answer == Resume.RESUME:
		_running_fallback.unpause(now)
	return answer


## Drops it before it ended, with `why`; calls `cancel()` once.
func drop(why: Reason) -> void:
	if is_done():
		return
	if _running_fallback != null:
		_running_fallback.drop(why)
	if state == State.RUNNING or state == State.SUSPENDED:
		cancel()
	state = State.CANCELLED
	reason = why


func _begin() -> void:
	state = State.RUNNING
	elapsed = 0.0
	_soft_fired = false
	started_at = run_time()
	start()


func _fail(why: Reason, end_state: State) -> Status:
	reason = why
	var at := runner()
	if at != null and (why == Reason.TIMED_OUT or not _fails_through_children()):
		at.note_failure(self)
	if why != Reason.INVALID and (at == null or not at.in_fallback()):
		if on_fail == OnFail.RETRY and _retries < retry_count:
			_retries += 1
			state = State.PENDING
			_retry_wait = retry_delay if retry_delay > 0.0 else -1.0
			return Status.RUNNING
		if on_fail == OnFail.FALLBACK and fallback != null and _running_fallback == null:
			_running_fallback = fallback.copy_for_run()
			_running_fallback.bind(at, character, controller)
			state = State.RUNNING
			return Status.RUNNING
	state = end_state
	return Status.FAILED


func _advance_fallback(delta: float, profile: AiProfile) -> Status:
	var result := _running_fallback.advance(delta, profile)
	if result == Status.RUNNING:
		return result
	if result == Status.SUCCEEDED:
		state = State.SUCCEEDED
		return result
	reason = _running_fallback.reason
	state = _running_fallback.state
	return Status.FAILED


# Starts it when pending, or counts down a retry's delay; false while the delay runs.
func _ready_to_step(delta: float) -> bool:
	if _retry_wait >= 0.0:
		_retry_wait -= delta
		if _retry_wait > 0.0:
			return false
		_retry_wait = -1.0
		_begin()
	elif state == State.PENDING:
		_begin()
	return true


# What `update()` returned: anything but a status (0 from a typed function that hit a script
# error, null from an untyped one) is the watchdog's `INVALID`.
func _judge(result: Variant) -> Status:
	match result:
		Status.RUNNING:
			return Status.RUNNING
		Status.SUCCEEDED:
			state = State.SUCCEEDED
			return Status.SUCCEEDED
		Status.FAILED:
			return _fail(reason if reason != Reason.NONE else Reason.BLOCKED, State.FAILED)
	return _fail(Reason.INVALID, State.FAILED)


# True for a composite, whose failure is a child's that was already counted (its own time-out
# still counts).
func _fails_through_children() -> bool:
	return false
