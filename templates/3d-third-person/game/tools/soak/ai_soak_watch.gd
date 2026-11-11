class_name AiSoakWatch
extends Node
## Watches every `AiCharacter` of its tree for what must never happen (kit #971) and keeps what
## each one did. Universal: it reads only the group `ai_characters` and the parts in a character's
## slots, so any scene with AI characters can hold one; `AiSoak` (`ai_soak.tscn`) is the soak that
## runs it on the template's sections. Place it after the level in the tree, so it reads each tick
## once the director has stepped.
##
## The gates, each an exported threshold (`report()` lists the ones broken):
##
## - `error`: an engine error while it watches (a `Logger`);
## - `stuck_episode`: a living character that keeps asking its navigator for a goal and moves less
##   than `stuck_metres` for longer than `stuck_episode_seconds`;
## - `stuck_share`: the stuck seconds of every character over `stuck_share` of their walking
##   seconds (an episode counts once it is longer than `stuck_grace_seconds`);
## - `idle_with_threat`: a hostile in view of its brain while its controller asks for nothing (no
##   reload, no weapon switch) for longer than `idle_seconds`;
## - `task_overdue`: the runner's active task active without a break for longer than its hard
##   timeout and `overdue_slack_seconds`;
## - `path_storm`: more path queries in a `storm_window_seconds` window than the window over the
##   navigator's `repath_seconds` (and one);
## - `think_p99`: the 99th percentile of every think's time over `think_p99_us`, scaled by a
##   calibration loop (`calibration_reference_ms` is the loop's time on the machine the budget
##   was set on, so a slow runner does not fail it: `performance-budgets.md`);
## - `belief`: a belief naming a node that is not a character with a faction (a wall, a prop) or a
##   character out of the tree (a body back in the pool);
## - anything the scenario adds with `fail()` (the soak's `round`).
##
## For every gate it breaks it keeps a sample of what the character held, did and decided (its
## beliefs, its layer stack, its last 20 decisions, its path's end, its tier): `failures`.

## A gate broke (once per character and gate).
signal gate_failed(gate: StringName, sample: Dictionary)

## Gate names, in the order the report lists them.
const GATES: Array[StringName] = [
	&"error",
	&"stuck_episode",
	&"stuck_share",
	&"idle_with_threat",
	&"task_overdue",
	&"path_storm",
	&"think_p99",
	&"belief",
	&"round",
]
## Decisions a sample keeps.
const SAMPLE_DECISIONS := 20
## Rounds of the calibration loop (the benches' loop: `tools/bench/ai_section_bench.gd`).
const CALIBRATION_ROUNDS := 200000
## Seconds between two calibrations.
const CALIBRATION_SECONDS := 10.0
## Seconds without a goal that end a stuck episode (the brain choosing the next goal is no move).
const GOAL_GAP_SECONDS := 1.0

@export_group("Stuck")
## Seconds a character may ask to walk and stay within `stuck_metres` before it counts as stuck.
@export_range(0.5, 120.0, 0.5, "suffix:s") var stuck_episode_seconds := 10.0
## Metres a walking character must move to count as moving.
@export_range(0.05, 5.0, 0.05, "suffix:m") var stuck_metres := 0.5
## Share of the walking time all characters together may spend stuck.
@export_range(0.0, 1.0, 0.001) var stuck_share := 0.01
## Seconds an episode must last before its time counts toward `stuck_share`.
@export_range(0.0, 30.0, 0.5, "suffix:s") var stuck_grace_seconds := 2.0

@export_group("Idle")
## Seconds a character may see a hostile and ask for nothing.
@export_range(0.5, 120.0, 0.5, "suffix:s") var idle_seconds := 5.0

@export_group("Tasks")
## Seconds past a task's hard timeout it may stay active (the think rate's slack).
@export_range(0.0, 30.0, 0.1, "suffix:s") var overdue_slack_seconds := 1.0

@export_group("Path queries")
## The window the query rate is read over.
@export_range(1.0, 60.0, 0.5, "suffix:s") var storm_window_seconds := 5.0
## Queries a window may hold, as a share of the window over `repath_seconds` (1: never more often
## than the navigator's interval allows).
@export_range(0.1, 10.0, 0.1) var storm_factor := 1.0

@export_group("Think cost")
## The 99th percentile of a think, microseconds, on the machine the budget was set on.
@export_range(10.0, 100000.0, 10.0, "suffix:us") var think_p99_us := 2000.0
## The calibration loop's time on that machine, milliseconds.
@export_range(0.1, 1000.0, 0.1, "suffix:ms") var calibration_reference_ms := 11.0
## Thinks the percentile needs before it is judged.
@export_range(1, 100000) var think_min_count := 200

@export_group("Run")
## Off: it keeps counting but judges nothing (a bench reads its numbers).
@export var judging := true

## Simulated seconds watched.
var clock := 0.0
## Every broken gate's sample, in the order they broke.
var failures: Array[Dictionary] = []
## Engine errors seen (text).
var errors: Array[String] = []
## Milliseconds of each calibration loop.
var calibrations := PackedFloat64Array()
## Every think's time, microseconds.
var think_us := PackedFloat64Array()

var _logger := ErrorCount.new()
var _watches: Dictionary[int, Watch] = {}
var _told: Dictionary[String, bool] = {}
var _next_calibration := 0.0
var _tick := 0


## What it keeps of one character over the whole run (a pooled body spawned again stays one).
class Watch:
	var character: AiCharacter
	var kind := ""
	var anchor := Vector3.ZERO
	var anchor_at := 0.0
	var goal_at := -INF
	var episode_walking := 0.0
	var walking := 0.0
	var stuck := 0.0
	var worst_episode := 0.0
	var idle := 0.0
	var idle_total := 0.0
	var worst_idle := 0.0
	var task: AiTask = null
	var fallback: AiTask = null
	var task_since := 0.0
	var thinks := 0
	var think_us := PackedFloat64Array()
	var queries := 0
	var asked := 0
	var query_times := PackedFloat64Array()
	var worst_window := 0
	var failed_by_reason: Dictionary[String, int] = {}
	var alive := 0.0
	var seen_tick := -1


## Keeps the engine's errors while it watches.
class ErrorCount:
	extends Logger
	var lines: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(
		function: String,
		_file: String,
		_line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		lines.append("%s: %s %s" % [function, code, rationale])
		_mutex.unlock()


func _enter_tree() -> void:
	OS.add_logger(_logger)


func _exit_tree() -> void:
	OS.remove_logger(_logger)


func _ready() -> void:
	# After every node that steps the characters (the director is in the level, before it).
	process_physics_priority = 1000


func _physics_process(delta: float) -> void:
	clock += delta
	_tick += 1
	if clock >= _next_calibration:
		calibrations.append(calibrate())
		_next_calibration = clock + CALIBRATION_SECONDS
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var character := node as AiCharacter
		if character != null and character.is_inside_tree() and not character.is_dead():
			_check(_watch_of(character), delta)
	_take_errors()


## The watch of `character`, made the first time it is seen.
func _watch_of(character: AiCharacter) -> Watch:
	var id := character.get_instance_id()
	if _watches.has(id):
		return _watches[id]
	var watch := Watch.new()
	watch.character = character
	watch.kind = character.profile.display_name if character.profile != null else "AI"
	watch.anchor = character.global_position
	watch.anchor_at = clock
	watch.thinks = character.think_count
	var navigator := character.navigator as AiNavigator
	watch.queries = navigator.path_queries if navigator != null else 0
	var tasks := character.task_runner as AiTasks
	if tasks != null:
		tasks.runner.task_failed.connect(_on_task_failed.bind(watch))
	_watches[id] = watch
	return watch


func _check(watch: Watch, delta: float) -> void:
	var character := watch.character
	if watch.seen_tick != _tick - 1:
		_begin_life(watch)
	watch.seen_tick = _tick
	watch.alive += delta
	_check_stuck(watch, delta)
	_check_idle(watch, delta)
	_check_task(watch)
	_check_queries(watch)
	if character.think_count != watch.thinks:
		# A think ran this tick (a new spawn's count starts again from 0).
		watch.thinks = character.think_count
		var spent := float(character.last_think_usec)
		think_us.append(spent)
		watch.think_us.append(spent)
		_check_beliefs(watch)


# A character seen again after a tick out of sight (dead, back in the pool, a new spawn) starts
# its episodes again: nothing it did before counts toward them.
func _begin_life(watch: Watch) -> void:
	watch.anchor_at = clock
	watch.episode_walking = 0.0
	watch.anchor = watch.character.global_position
	watch.goal_at = -INF
	watch.idle = 0.0
	watch.task = null
	watch.thinks = watch.character.think_count


func _check_stuck(watch: Watch, delta: float) -> void:
	var character := watch.character
	var navigator := character.navigator as AiNavigator
	var going := navigator != null and navigator.is_active() and not navigator.is_arrived()
	if going:
		watch.goal_at = clock
		watch.walking += delta
		watch.episode_walking += delta
	var moved := character.global_position.distance_to(watch.anchor) > stuck_metres
	if moved or clock - watch.goal_at > GOAL_GAP_SECONDS:
		_end_episode(watch)
		watch.anchor = character.global_position
		return
	var episode := clock - watch.anchor_at
	watch.worst_episode = maxf(watch.worst_episode, episode)
	if episode > stuck_episode_seconds:
		_fail_once(
			&"stuck_episode",
			watch,
			"asked to walk for %.1f s and moved under %.2f m" % [episode, stuck_metres]
		)


# Ends the episode under way: its walking seconds count as stuck when it lasted past the grace.
func _end_episode(watch: Watch) -> void:
	if clock - watch.anchor_at > stuck_grace_seconds:
		watch.stuck += watch.episode_walking
	watch.anchor_at = clock
	watch.episode_walking = 0.0


func _check_idle(watch: Watch, delta: float) -> void:
	var character := watch.character
	var mind := character.brain as AiBrain
	var threat: AiBelief = mind.call(&"_threat_in_view") if mind != null else null
	if threat == null or threat.band != AiRelations.Band.HOSTILE or asks_something(character):
		watch.idle = 0.0
		return
	watch.idle += delta
	watch.idle_total += delta
	watch.worst_idle = maxf(watch.worst_idle, watch.idle)
	if watch.idle > idle_seconds:
		_fail_once(
			&"idle_with_threat",
			watch,
			"a hostile in view for %.1f s and nothing asked (%s)" % [watch.idle, threat.describe()]
		)


func _check_task(watch: Watch) -> void:
	var tasks := watch.character.task_runner as AiTasks
	if tasks == null:
		return
	var runner := tasks.runner
	var active := runner.active
	# A task that failed into its fallback runs the fallback under its own name, with the
	# fallback's timeout: a new task for this gate.
	var fallback: AiTask = active.get(&"_running_fallback") if active != null else null
	if active != watch.task or fallback != watch.fallback or active == null or not runner.can_think:
		watch.task = active
		watch.fallback = fallback
		watch.task_since = runner.world_time
		return
	var running := fallback if fallback != null else active
	var limit := running.hard_limit(runner.profile)
	var age := runner.world_time - watch.task_since
	if limit > 0.0 and age > limit + overdue_slack_seconds:
		_fail_once(
			&"task_overdue",
			watch,
			"%s active for %.1f s, hard timeout %.1f s" % [active.display_label(), age, limit]
		)


func _check_queries(watch: Watch) -> void:
	var navigator := watch.character.navigator as AiNavigator
	if navigator == null:
		return
	var asked := navigator.path_queries - watch.queries
	watch.queries = navigator.path_queries
	watch.asked += maxi(asked, 0)
	for _i in maxi(asked, 0):
		watch.query_times.append(clock)
	var start := 0
	while (
		start < watch.query_times.size() and watch.query_times[start] < clock - storm_window_seconds
	):
		start += 1
	if start > 0:
		watch.query_times = watch.query_times.slice(start)
	var in_window := watch.query_times.size()
	watch.worst_window = maxi(watch.worst_window, in_window)
	var allowed := storm_window_seconds / repath_of(navigator) * storm_factor + 1.0
	if in_window > allowed:
		_fail_once(
			&"path_storm",
			watch,
			(
				"%d path queries in %.1f s, at most %.0f (repath %.2f s)"
				% [in_window, storm_window_seconds, allowed, repath_of(navigator)]
			)
		)


func _check_beliefs(watch: Watch) -> void:
	var senses := watch.character.senses as AiSenses
	if senses == null:
		return
	for belief: AiBelief in senses.beliefs.by_id.values():
		var entity := belief.entity()
		if entity == null:
			continue
		var wrong := ""
		if not entity.is_inside_tree():
			wrong = "out of the tree"
		elif not entity is Character or AiFactionMember.of(entity) == null:
			wrong = "not a character with a faction"
		if wrong != "":
			_fail_once(&"belief", watch, "a belief names %s, %s" % [entity.name, wrong])
			return


func _on_task_failed(_task: AiTask, reason: AiTask.Reason, watch: Watch) -> void:
	var key := (
		String(AiTask.REASON_NAMES[reason]) if reason < AiTask.REASON_NAMES.size() else str(reason)
	)
	watch.failed_by_reason[key] = watch.failed_by_reason.get(key, 0) + 1


func _take_errors() -> void:
	if _logger.lines.is_empty():
		return
	for line in _logger.lines:
		errors.append(line)
		if errors.size() == 1:
			fail(&"error", null, line)
	_logger.lines.clear()


## The gates the run broke at its end (the whole-run ones judged now), each with its count.
func finish() -> Dictionary[StringName, int]:
	_take_errors()
	for watch: Watch in _watches.values():
		_end_episode(watch)
	var walking := 0.0
	var stuck := 0.0
	for watch: Watch in _watches.values():
		walking += watch.walking
		stuck += watch.stuck
	if walking > 0.0 and stuck / walking > stuck_share:
		fail(
			&"stuck_share",
			null,
			"stuck %.1f s of %.1f s walking (%.2f %%)" % [stuck, walking, 100.0 * stuck / walking]
		)
	var sorted := think_us.duplicate()
	sorted.sort()
	var p99 := percentile(sorted, 0.99)
	var budget := think_budget_us()
	if sorted.size() >= think_min_count and p99 > budget:
		fail(&"think_p99", null, "think p99 %.0f us over %.0f us" % [p99, budget])
	var broken: Dictionary[StringName, int] = {}
	for sample in failures:
		var gate: StringName = sample.gate
		broken[gate] = broken.get(gate, 0) + 1
	return broken


## The think budget for this machine: `think_p99_us` scaled by the median calibration.
func think_budget_us() -> float:
	var sorted := calibrations.duplicate()
	sorted.sort()
	var now := percentile(sorted, 0.5) if not sorted.is_empty() else calibration_reference_ms
	return think_p99_us * maxf(1.0, now / calibration_reference_ms)


## Breaks `gate` for `character` (null: the run) with `text` and a sample of the character.
func fail(gate: StringName, character: AiCharacter, text: String) -> void:
	if not judging:
		return
	var sample := {"gate": gate, "t": snappedf(clock, 0.01), "why": text}
	if character != null:
		sample.merge(sample_of(character))
	failures.append(sample)
	gate_failed.emit(gate, sample)


func _fail_once(gate: StringName, watch: Watch, text: String) -> void:
	var key := "%s %d" % [gate, watch.character.get_instance_id()]
	if _told.has(key):
		return
	_told[key] = true
	fail(gate, watch.character, text)


## What `character` holds, does and decided now: Deadnight's `idle_samples`.
static func sample_of(character: AiCharacter) -> Dictionary:
	var sample := {
		"character": String(character.name),
		"kind": character.profile.display_name if character.profile != null else "AI",
		"at": _rounded(character.global_position),
		"tier": AiDirector.TIER_NAMES[clampi(character.tier, 0, 2)],
		"situation": AiSituation.name_of(character.situation.current),
		"thinks": character.think_count,
	}
	var senses := character.senses as AiSenses
	if senses != null:
		sample["beliefs"] = Array(senses.beliefs.describe())
	var tasks := character.task_runner as AiTasks
	if tasks != null:
		var runner := tasks.runner
		var layers := runner.describe()
		sample["active"] = layers.active
		sample["stack"] = layers.stack
		sample["last_failure"] = layers.last_failure
		var decisions := runner.decisions.entries()
		var lines: Array[String] = []
		for entry in decisions.slice(maxi(decisions.size() - SAMPLE_DECISIONS, 0)):
			lines.append("%.2f %s %s" % [entry.time, entry.what, entry.task])
		sample["decisions"] = lines
	var navigator := character.navigator as AiNavigator
	if navigator != null:
		var end := navigator.goal
		sample["path_end"] = _rounded(end) if end.is_finite() else "none"
		sample["navigator"] = navigator.debug_text()
		sample["path_queries"] = navigator.path_queries
	var mind := character.brain as AiBrain
	if mind != null:
		sample["last_event"] = String(mind.last_event)
		sample["last_answer"] = mind.last_answer
	return sample


## One line of numbers a character: what the nightly job keeps.
func character_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for watch: Watch in _watches.values():
		var sorted := watch.think_us.duplicate()
		sorted.sort()
		(
			rows
			. append(
				{
					"character":
					String(watch.character.name) if is_instance_valid(watch.character) else "",
					"kind": watch.kind,
					"alive_seconds": snappedf(watch.alive, 0.1),
					"walking_seconds": snappedf(watch.walking, 0.1),
					"stuck_seconds": snappedf(watch.stuck, 0.1),
					"worst_stuck_episode": snappedf(watch.worst_episode, 0.1),
					"idle_with_threat_seconds": snappedf(watch.idle_total, 0.1),
					"worst_idle_with_threat": snappedf(watch.worst_idle, 0.1),
					"thinks": sorted.size(),
					"think_us_p50": percentile(sorted, 0.5),
					"think_us_p99": percentile(sorted, 0.99),
					"path_queries": watch.asked,
					"worst_query_window": watch.worst_window,
					"tasks_failed_by_reason": watch.failed_by_reason,
				}
			)
		)
	return rows


## The value at `share` (0 to 1) of sorted numbers (nearest rank), 0 for none.
static func percentile(sorted: PackedFloat64Array, share: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(ceil(share * sorted.size())) - 1, 0, sorted.size() - 1)]


## The navigator's interval between two queries.
static func repath_of(navigator: AiNavigator) -> float:
	if navigator.repath_seconds > 0.0:
		return navigator.repath_seconds
	var character := navigator.character
	return (
		character.profile.repath_seconds
		if character != null and character.profile != null
		else 0.25
	)


## True when the character's controller asks for something (a move, aim, fire, jump, crouch), or
## its weapon reloads or switches.
static func asks_something(character: AiCharacter) -> bool:
	var controller := character.ai_controller()
	if controller != null and not controller.is_still():
		return true
	if character.weapon != null and character.weapon.is_reloading():
		return true
	return character.loadout != null and character.loadout.is_switching()


## Milliseconds a fixed loop of GDScript takes: the machine's speed now.
static func calibrate() -> float:
	var start := Time.get_ticks_usec()
	var value := 0.0
	for index in CALIBRATION_ROUNDS:
		value = sin(value + index) * 0.5
	return (Time.get_ticks_usec() - start + int(value * 0.0)) / 1000.0


static func _rounded(point: Vector3) -> Array[float]:
	return [snappedf(point.x, 0.01), snappedf(point.y, 0.01), snappedf(point.z, 0.01)]
