class_name AiTaskRunner
extends RefCounted
## What one AI character is doing: its tasks (`AiTask`) in five layers, highest first REACTION,
## RESPONSE, ORDER, ROUTINE and DEFAULT, each an ordered queue. The active task is the head of
## the highest layer that may run; a lower one is suspended, never dropped, and resumes when the
## higher one ends. Who may take the character off a task, and what happens to it then, is the
## task's contract (`interruptible`, `when_interrupted`, `under_attack`, `on_fail`, time limits).
##
## Anything assigns through the same calls, whoever it is (a reaction, a mission, a squad, the
## player): `assign(task, issuer)`, `revoke(issuer)`, `clear(layer, force)`, `force_cancel(task)`,
## and the body reports through `report_damage(amount, source)` and `set_can_think(bool)`. Every
## decision goes into `decisions` with the beliefs that produced it, and into the signals below.
##
## It needs no scene: the `AiTasks` node owns one for a character and steps it on each think, and
## a test makes one with `AiTaskRunner.new()`. A step with no task does nothing and allocates
## nothing. The kit's `docs/engines/godot/third-person/ai.md#tasks` is the contract.

## A task started (the first time; a resumed one sends `task_resumed`).
signal task_started(task: AiTask)
## A task ended: succeeded, failed, cancelled or timed out (`task.state`, `task.reason`).
signal task_finished(task: AiTask, state: AiTask.State)
## A task was taken off and kept to resume.
signal task_suspended(task: AiTask)
## A suspended task came back.
signal task_resumed(task: AiTask)
## A task failed or timed out (sent with `task_finished`).
signal task_failed(task: AiTask, reason: AiTask.Reason)
## An assignment was refused (an order below the character's obedience, a need its order holds
## against, a response while a task blocks them) and never placed.
signal task_refused(task: AiTask, reason: AiTask.Reason)
## An attacker the character could not answer during an uninterruptible task, delivered when the
## task ended (`attack_task`, when set, is assigned against it too).
signal attacker_pending(source: Object)

## The decision written when a task ends in each `AiTask.State`.
const END_EVENTS: Array[StringName] = [
	&"pending", &"running", &"suspended", &"succeeded", &"failed", &"cancelled", &"timed_out"
]
## How many layers there are (`AiTask.Layer`).
const LAYERS := 5
## An order is obeyed when its authority is at least `(1 - obeys_orders) * OBEDIENCE_SCALE`: a
## profile with `obeys_orders` 0.5 takes squad orders (10) and up; 1 takes any; 0 only 20 and up.
const OBEDIENCE_SCALE := 20.0

## The profile whose numbers it reads (hard timeout, failure budget, commit time); the `AiTasks`
## node keeps it the character's. Null: the defaults of `AiProfile`.
var profile: AiProfile = AiProfile.new()
## The character, and the controller whose channels the tasks write (null in a bare test).
var character: Node = null
var controller: AiController = null
## The table that says whether an order gives way to a need; null: an order never does.
var needs: AiNeeds = null
## The task assigned against an attacker after an uninterruptible task (`FINISH_THEN_REACT`) and
## run on the action channel beside one (`FIGHT_BACK_WHILE`); null sends only the signal.
var attack_task: AiTask = null
## What it believes (written by its senses and its brain: `&"ammo"` 0 to 1, the last attacker);
## the decisions log a copy, and `AiNeeds` reads the needs here.
var beliefs := {}
## The last decisions with their beliefs.
var decisions := AiDecisionLog.new()
## Seconds of steps since it was made, thinking or not.
var world_time := 0.0
## Seconds of steps while it could think (frozen while dead): the failure budget's clock.
var think_time := 0.0
## The task running now, or null.
var active: AiTask = null
## The task firing back on the action channel beside an uninterruptible one, or null.
var side_task: AiTask = null
## False while the body cannot act (dead, ragdolled): everything waits, timers frozen.
var can_think := true
## Steps that ran a task (a test counts them).
var busy_steps := 0

var _layers: Array[Array] = []
var _deferred: Array[AiTask] = []
var _count := 0
var _failure_times := PackedFloat64Array()
var _fallback_until := -1.0
var _damage := PackedFloat64Array()
var _pending_attacker: Object = null
var _side_owner: AiTask = null
var _last_failure: AiTask = null
var _dirty := true
var _poll := false


func _init() -> void:
	for _index in LAYERS:
		var queue: Array[AiTask] = []
		_layers.append(queue)


## One step, `delta` seconds after the last (the character's think): picks the task, switches
## under the contract, runs it. Returns at once, allocating nothing, when it holds no task.
func tick(delta: float) -> void:
	world_time += delta
	if _count == 0 and _deferred.is_empty() and side_task == null:
		return
	if not can_think:
		return
	think_time += delta
	busy_steps += 1
	# The pick changes only when a task came or went, or a head waits on `can_run` or the fallback.
	if _dirty or _poll or active == null or active.state != AiTask.State.RUNNING:
		var next := _select()
		if next != active:
			_switch(next)
		elif active != null and active.state == AiTask.State.SUSPENDED:
			_bring_back(active)
	if active != null and not active.is_done():
		var result := active.advance(delta, profile)
		if result != AiTask.Status.RUNNING:
			_finish(active)
	if side_task != null:
		_advance_side(delta)


## Places `task` (a copy of it when it comes from a file or already ran) in its layer for
## `issuer` and returns the instance that runs, or null when it was refused, ignored or the
## commit time of a running response kept it out. An equal id in the layer merges into the task
## there (which is returned); an order follows its `authority`; a higher layer arriving during a
## task that must complete waits until that task ends.
func assign(task: AiTask, issuer: Variant = null) -> AiTask:
	if task == null:
		return null
	var placed := task.copy_for_run()
	placed.reset()
	if issuer != null:
		placed.issuer = issuer
	placed.assigned_at = world_time
	placed.bind(self, character, controller)
	var refusal := _refusal(placed)
	if refusal != AiTask.Reason.NONE:
		placed.state = AiTask.State.CANCELLED
		placed.reason = refusal
		_note(&"refused", placed)
		task_refused.emit(placed, refusal)
		return null
	if _defers(placed):
		return _defer(placed)
	return _place(placed)


## Removes every task `issuer` gave (queued, deferred or running) and returns how many; the rest
## resume. A running task that must complete stays unless `force`.
func revoke(issuer: Variant, force := false) -> int:
	var removed := 0
	for task in _all_tasks():
		if not _same(task.issuer, issuer):
			continue
		if not force and task == active and task.interruptible == AiTask.Interruptible.NO:
			continue
		_cancel(task, AiTask.Reason.REVOKED)
		removed += 1
	return removed


## Drops the tasks of `layer` (every layer for -1) and returns how many; a `persistent` task and a
## must-complete one stay unless `force`.
func clear(layer := -1, force := false) -> int:
	var removed := 0
	for task in _all_tasks():
		if layer >= 0 and task.layer != layer:
			continue
		if not force and (task.persistent or task.interruptible == AiTask.Interruptible.NO):
			continue
		_cancel(task, AiTask.Reason.CANCELLED)
		removed += 1
	return removed


## Ends `task` at once whatever its contract (a script that must, a deletion).
func force_cancel(task: AiTask) -> void:
	if task != null and not task.is_done():
		_cancel(task, AiTask.Reason.CANCELLED)


## The body took `amount` damage from `source`: remembered as a belief, and under a task that
## must complete its `under_attack` policy decides (ignore, answer once it ends, fire back on the
## action channel, or abort past a threshold). An interruptible task leaves the answer to the
## brain's reactions.
func report_damage(amount: float, source: Object) -> void:
	beliefs[&"attacker"] = source
	beliefs[&"attacked_at"] = world_time
	if active == null or active.is_done() or not can_think:
		return
	if active.interruptible == AiTask.Interruptible.YES:
		return
	if active.interruptible == AiTask.Interruptible.BY_HIGHER_LAYER:
		return
	match _attack_policy(active):
		AiTask.UnderAttack.IGNORE:
			_note(&"hit_ignored", active)
		AiTask.UnderAttack.FIGHT_BACK_WHILE:
			_fight_back(source)
		AiTask.UnderAttack.ABORT_ABOVE:
			_abort_above(amount, source)
		_:
			_pending_attacker = source
			_note(&"hit_deferred", active)


## Pauses (false) or resumes (true) the runner: dead, ragdolled or frozen, the active task is
## suspended with its timers frozen, nothing fails or times out, and assignments wait; on true the
## tasks come back under the resume rules.
func set_can_think(value: bool) -> void:
	if value == can_think:
		return
	can_think = value
	_dirty = true
	if value:
		_note(&"woke", active)
		return
	_end_side()
	if active != null and active.state == AiTask.State.RUNNING:
		_release(active)
		active.pause(world_time)
		task_suspended.emit(active)
	_note(&"paused", active)


## Called by a task for each failure (retried ones too): past the profile's `failure_budget` in
## `failure_window` seconds, or at once on a script error, ORDER and ROUTINE stop for
## `fallback_seconds` and DEFAULT runs, so a failing task cannot loop.
func note_failure(task: AiTask) -> void:
	_last_failure = task
	if task.reason == AiTask.Reason.INVALID:
		push_warning(
			(
				"AI task %s hit a script error; it ends FAILED(INVALID)\n%s"
				% [task.display_label(), decisions.dump()]
			)
		)
		_start_fallback(task)
		return
	_failure_times.append(think_time)
	var window := profile.failure_window
	while not _failure_times.is_empty() and think_time - _failure_times[0] > window:
		_failure_times.remove_at(0)
	if _failure_times.size() >= profile.failure_budget and not in_fallback():
		_start_fallback(task)


## True while a failure storm holds ORDER and ROUTINE back.
func in_fallback() -> bool:
	return think_time < _fallback_until


## How many tasks wait or run in the layers (deferred ones not counted).
func count() -> int:
	return _count


## The tasks of `layer`, head first (a copy).
func queued(layer: int) -> Array[AiTask]:
	var copy: Array[AiTask] = []
	copy.assign(_layers[layer])
	return copy


## The tasks held back until a must-complete task ends (a copy).
func deferred() -> Array[AiTask]:
	return _deferred.duplicate()


## The active task's id, the one thing about tasks replication sends (with `active_target_id`).
func active_kind() -> StringName:
	return active.id if active != null else &""


## The instance id of the active task's target, or 0.
func active_target_id() -> int:
	return active.target_id() if active != null else 0


## Everything an overlay or a test shows: the active task, its layer, state, time and channels,
## the stack of every layer, what waits, the fallback and the last failure.
func describe() -> Dictionary:
	var stack := {}
	for index in LAYERS:
		var queue: Array = _layers[index]
		if queue.is_empty():
			continue
		var labels := PackedStringArray()
		for task: AiTask in queue:
			labels.append("%s (%s)" % [task.display_label(), AiTask.STATE_NAMES[task.state]])
		stack[AiTask.LAYER_NAMES[index]] = labels
	var info := {
		&"active": active.display_label() if active != null else "",
		&"layer": AiTask.LAYER_NAMES[active.layer] if active != null else "",
		&"state": AiTask.STATE_NAMES[active.state] if active != null else "",
		&"elapsed": active.elapsed if active != null else 0.0,
		&"time_left": _time_left(),
		&"channels": active.claimed_channels() if active != null else 0,
		&"stack": stack,
		&"deferred": _deferred.size(),
		&"can_think": can_think,
		&"fallback_left": maxf(0.0, _fallback_until - think_time),
		&"last_failure": _failure_text(),
	}
	return info


## `describe()` as lines for a `Label3D`: one per layer that holds a task, the active one marked.
func describe_text() -> String:
	var lines := PackedStringArray()
	for index in LAYERS:
		var queue: Array = _layers[index]
		if queue.is_empty():
			continue
		var head: AiTask = queue[0]
		var mark := "> " if head == active else "  "
		var line := "%s%s: %s" % [mark, AiTask.LAYER_NAMES[index], head.display_label()]
		var inner := head.detail()
		if not inner.is_empty():
			line += " / " + inner
		if head != active:
			line += " (%s)" % AiTask.STATE_NAMES[head.state].to_lower()
		if queue.size() > 1:
			line += " +%d" % (queue.size() - 1)
		lines.append(line)
	if not can_think:
		lines.append("(paused)")
	elif in_fallback():
		lines.append("(fallback)")
	return "\n".join(lines)


func _select() -> AiTask:
	_dirty = false
	_poll = in_fallback()
	for index in LAYERS:
		var queue: Array = _layers[index]
		if queue.is_empty() or (_poll and _blocked(index)):
			continue
		while not queue.is_empty() and _expired(queue[0]):
			_cancel(queue[0], AiTask.Reason.EXPIRED)
		if queue.is_empty():
			continue
		var head: AiTask = queue[0]
		if head != active and not head.can_run():
			_poll = true
			continue
		return _keep_or(head)
	return _keep_or(null)


# The active task stays when its contract keeps `best` from taking over.
func _keep_or(best: AiTask) -> AiTask:
	if active == null or best == active or active.is_done():
		return best
	match active.interruptible:
		AiTask.Interruptible.YES:
			return best
		AiTask.Interruptible.BY_HIGHER_LAYER:
			return best if best != null and best.layer < active.layer else active
	return active


func _switch(next: AiTask) -> void:
	if active != null and active.state == AiTask.State.RUNNING:
		_take_off(active)
	active = next
	if next == null:
		return
	if next.state == AiTask.State.SUSPENDED:
		_bring_back(next)
	elif next.state == AiTask.State.PENDING:
		_note(&"started", next)
		if next.hard_limit(profile) == 0.0:
			_note(&"no_time_limit", next)
		task_started.emit(next)


func _take_off(task: AiTask) -> void:
	_release(task)
	_end_side()
	match task.when_interrupted:
		AiTask.WhenInterrupted.ABORT, AiTask.WhenInterrupted.SKIP_TO_NEXT:
			_cancel(task, AiTask.Reason.CANCELLED)
		_:
			task.pause(world_time)
			_note(&"suspended", task)
			task_suspended.emit(task)


func _bring_back(task: AiTask) -> void:
	var answer := task.unpause(world_time)
	match answer:
		AiTask.Resume.RESUME:
			_note(&"resumed", task)
			task_resumed.emit(task)
		AiTask.Resume.RESTART:
			_note(&"restarted", task)
			task_resumed.emit(task)
		_:
			if task.state == AiTask.State.FAILED:
				note_failure(task)
			_finish(task)


# A task ended by itself (or on resume): out of its layer, its channels let go.
func _finish(task: AiTask) -> void:
	_remove(task)
	_release(task)
	var was_active := task == active
	if was_active:
		active = null
	_ended(task, was_active)


func _cancel(task: AiTask, why: AiTask.Reason) -> void:
	var deferred_at := _deferred.find(task)
	if deferred_at >= 0:
		_deferred.remove_at(deferred_at)
	_remove(task)
	var was_active := task == active
	if was_active:
		_release(task)
		active = null
	task.drop(why)
	_ended(task, was_active)


func _ended(task: AiTask, was_active: bool) -> void:
	_note(END_EVENTS[task.state], task)
	task_finished.emit(task, task.state)
	if task.state == AiTask.State.FAILED or task.state == AiTask.State.TIMED_OUT:
		task_failed.emit(task, task.reason)
	if not was_active:
		return
	_end_side()
	if _pending_attacker != null:
		_deliver_attacker()
	if not _deferred.is_empty():
		_deliver_deferred()


func _refusal(task: AiTask) -> AiTask.Reason:
	if task.layer == AiTask.Layer.ORDER:
		var needed := (1.0 - profile.obeys_orders) * OBEDIENCE_SCALE
		if float(task.authority) < needed:
			return AiTask.Reason.REFUSED
	if task.need != &"":
		var order := _order_in_force()
		if order != null:
			var urgency := float(beliefs.get(task.need, 0.0))
			if needs == null or not needs.gives_way(order.id, task.need, urgency):
				return AiTask.Reason.REFUSED
	var blocking := active != null and not active.is_done() and not active.reactive
	if blocking and task.layer == AiTask.Layer.RESPONSE and active.layer >= task.layer:
		return AiTask.Reason.REFUSED
	return AiTask.Reason.NONE


func _defers(task: AiTask) -> bool:
	if active == null or active.state != AiTask.State.RUNNING:
		return false
	var must_finish := (
		active.interruptible == AiTask.Interruptible.NO
		or active.interruptible == AiTask.Interruptible.FINISH_THEN_REACT
	)
	return must_finish and task.layer < active.layer


func _defer(task: AiTask) -> AiTask:
	if task.id != &"" and task.replace_policy != AiTask.ReplacePolicy.QUEUE:
		for waiting in _deferred:
			if waiting.id == task.id and waiting.layer == task.layer:
				waiting.merge(task)
				_note(&"merged", waiting)
				return waiting
	_deferred.append(task)
	_note(&"deferred", task)
	return task


func _place(task: AiTask) -> AiTask:
	var queue: Array = _layers[task.layer]
	if task.id != &"" and task.replace_policy != AiTask.ReplacePolicy.QUEUE:
		for existing: AiTask in queue:
			if existing.id != task.id:
				continue
			if task.replace_policy == AiTask.ReplacePolicy.IGNORE:
				_note(&"ignored", task)
				return null
			existing.merge(task)
			_note(&"merged", existing)
			return existing
	if queue.is_empty():
		_insert(task, 0)
	elif task.layer == AiTask.Layer.ORDER:
		_place_order(task)
	else:
		match task.replace_policy:
			AiTask.ReplacePolicy.QUEUE:
				_insert(task, queue.size())
			AiTask.ReplacePolicy.IGNORE:
				_note(&"ignored", task)
				return null
			_:
				if not _replace_head(task):
					return null
	_note(&"assigned", task)
	return task


# REPLACE (and MERGE with no equal id): the new task takes the head's place, unless the head is
# running a response inside its commit time (the new one is dropped) or may not be taken off by
# its own layer (the new one goes next).
func _replace_head(task: AiTask) -> bool:
	var head: AiTask = _layers[task.layer][0]
	if head == active and task.layer == AiTask.Layer.RESPONSE:
		if world_time - head.started_at < profile.commit_seconds:
			_note(&"committed", task)
			return false
	if head == active and head.interruptible != AiTask.Interruptible.YES:
		_insert(task, 1)
		return true
	_insert(task, 0)
	_cancel(head, AiTask.Reason.REPLACED)
	return true


# An order replaces the head when its authority is at least the head's (the newer of two equal
# ones wins), unless the head must complete; a lower one waits behind every higher one.
func _place_order(task: AiTask) -> void:
	var queue: Array = _layers[task.layer]
	var head: AiTask = queue[0]
	if task.authority >= head.authority:
		var must_finish := (
			head == active
			and (
				head.interruptible == AiTask.Interruptible.NO
				or head.interruptible == AiTask.Interruptible.FINISH_THEN_REACT
			)
		)
		if must_finish:
			_insert(task, 1)
		else:
			_insert(task, 0)
			_cancel(head, AiTask.Reason.REPLACED)
		return
	var at := queue.size()
	for index in queue.size():
		if (queue[index] as AiTask).authority < task.authority:
			at = index
			break
	_insert(task, at)


func _insert(task: AiTask, at: int) -> void:
	_layers[task.layer].insert(at, task)
	_count += 1
	_dirty = true


func _remove(task: AiTask) -> void:
	var queue: Array = _layers[task.layer]
	var at := queue.find(task)
	if at >= 0:
		queue.remove_at(at)
		_count -= 1
		_dirty = true


func _all_tasks() -> Array[AiTask]:
	var every: Array[AiTask] = []
	for queue: Array in _layers:
		every.append_array(queue)
	every.append_array(_deferred)
	return every


func _order_in_force() -> AiTask:
	var orders: Array = _layers[AiTask.Layer.ORDER]
	return orders[0] if not orders.is_empty() else null


func _blocked(index: int) -> bool:
	return in_fallback() and (index == AiTask.Layer.ORDER or index == AiTask.Layer.ROUTINE)


func _expired(task: AiTask) -> bool:
	return (
		task.expires_after > 0.0
		and task.state == AiTask.State.PENDING
		and world_time - task.assigned_at > task.expires_after
	)


func _deliver_deferred() -> void:
	var waiting := _deferred
	_deferred = []
	for task in waiting:
		if _expired(task):
			task.drop(AiTask.Reason.EXPIRED)
			_ended(task, false)
			continue
		_note(&"delivered", task)
		_place(task)


func _attack_policy(task: AiTask) -> AiTask.UnderAttack:
	var policy := task.under_attack
	if policy == AiTask.UnderAttack.PROFILE:
		policy = profile.under_attack
	if policy == AiTask.UnderAttack.PROFILE:
		policy = AiTask.UnderAttack.FINISH_THEN_REACT
	return policy


func _fight_back(source: Object) -> void:
	if attack_task == null or active.claimed_channels() & AiTask.Channel.ACTION:
		_pending_attacker = source
		_note(&"hit_deferred", active)
		return
	if side_task != null:
		side_task.target = source
		return
	side_task = attack_task.fresh_copy()
	side_task.target = source
	side_task.channels = AiTask.Channel.ACTION
	side_task.bind(self, character, controller)
	_side_owner = active
	_note(&"fight_back", side_task)
	task_started.emit(side_task)


func _abort_above(amount: float, source: Object) -> void:
	_damage.append(world_time)
	_damage.append(amount)
	while _damage.size() >= 2 and world_time - _damage[0] > active.abort_window:
		_damage = _damage.slice(2)
	var total := 0.0
	for index in range(1, _damage.size(), 2):
		total += _damage[index]
	if total < active.abort_damage:
		_note(&"hit_counted", active)
		return
	_damage.clear()
	_pending_attacker = source
	var victim := active
	victim.reason = AiTask.Reason.ATTACKED
	victim.state = AiTask.State.FAILED
	note_failure(victim)
	victim.cancel()
	_finish(victim)


func _deliver_attacker() -> void:
	var source := _pending_attacker
	_pending_attacker = null
	if not is_instance_valid(source):
		return
	attacker_pending.emit(source)
	if attack_task != null:
		var answer := attack_task.fresh_copy()
		answer.target = source
		assign(answer, &"attacked")


func _advance_side(delta: float) -> void:
	if _side_owner != active or active == null:
		_end_side()
		return
	if side_task.advance(delta, profile) != AiTask.Status.RUNNING:
		_end_side()


func _end_side() -> void:
	if side_task == null:
		return
	var ended := side_task
	side_task = null
	_side_owner = null
	ended.drop(AiTask.Reason.CANCELLED)
	_release(ended)
	_note(&"side_ended", ended)
	task_finished.emit(ended, ended.state)


func _start_fallback(task: AiTask) -> void:
	_fallback_until = think_time + profile.fallback_seconds
	_dirty = true
	_failure_times.clear()
	_note(&"fallback", task)


# Lets go of the channels `task` drives, so a suspended or ended task does not keep the body
# walking, aiming or firing.
func _release(task: AiTask) -> void:
	if controller == null:
		return
	var mask := task.claimed_channels()
	if mask & AiTask.Channel.MOVE:
		controller.walk_direction = Vector3.ZERO
		controller.walk_strength = 1.0
	if mask & AiTask.Channel.LOOK:
		controller.look_direction = Vector3.ZERO
	if mask & AiTask.Channel.ACTION:
		controller.aim = false
		controller.fire = false


func _time_left() -> float:
	if active == null:
		return 0.0
	var limit := active.hard_limit(profile)
	return maxf(0.0, limit - active.elapsed) if limit > 0.0 else INF


func _failure_text() -> String:
	if _last_failure == null:
		return ""
	return "%s: %s" % [_last_failure.display_label(), AiTask.REASON_NAMES[_last_failure.reason]]


func _note(what: StringName, task: AiTask) -> void:
	decisions.write(world_time, what, task, beliefs)


# Two issuers are the same when they are the same kind and equal (a node and a name never are).
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
