# On the clock: the AI cost gate's bench, run in a Godot process of its own (kit #1526).
class_name AiCostBench
extends Node
## The AI cost gate's measure (`tests/gameplay/test_ai_cost_gate.gd`): 50, 100 and 200 of the
## template's `civilian.tscn` on a `BehaviourArena`, each held for `TICKS` ticks after `WARM_TICKS`,
## with the director's step and thinks timed over `PhysicsRuler`. Run as the main scene
## (`ai_cost_bench.tscn`, `-- --slow` for the twice-as-slow director) it prints one
## `AI_COST_ROW {json}` line a crowd size and quits: the gate runs it in fresh processes, because
## the AI keeps counters across a process (the navigators' phases and seeds) and a long test run
## leaves its heap in another state, so the same code read 1.6 times apart inside the template
## job against 1.3 to 1.45 in a process of its own (kit docs
## third-person/ai-characters.md#cost-gate).

const ROW_PREFIX := "AI_COST_ROW "
const CIVILIAN := "res://gameplay/ai/characters/civilian.tscn"
const COUNTS: Array[int] = [50, 100, 200]
const WARM_TICKS := 120
const TICKS := 300
## Metres between two characters of the grid they start on.
const SPACING := 1.6
## Ticks between two timings of the ruler in the measured window.
const CALIBRATE_TICKS := 50
## How many times its work the slow director's step costs.
const SLOW_FACTOR := 2.0

var _arena: BehaviourArena
var _ruler: PhysicsRuler
var _candidates: RulerCandidates


func _ready() -> void:
	if get_parent() == get_tree().root:
		_run.call_deferred("--slow" in OS.get_cmdline_user_args())


## Measures the three crowds (on `SlowAiDirector` when `slow`), prints their rows and quits.
func _run(slow: bool) -> void:
	var rows := await measure_all(slow)
	for row in rows:
		row["case"] = "slow" if slow else "gate"
		print(ROW_PREFIX + JSON.stringify(row))
	AudioDrain.stop_all(_arena)
	_arena.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## The rows of the three crowds, in `COUNTS` order.
func measure_all(slow := false) -> Array[Dictionary]:
	_arena = BehaviourArena.new()
	add_child(_arena)
	_ruler = PhysicsRuler.new()
	_arena.add_child(_ruler)
	_candidates = RulerCandidates.new()
	_arena.add_child(_candidates)
	_arena.build()
	await _arena.settle()
	if slow:
		var director := SlowAiDirector.new()
		director.name = "AiDirector"
		director.factor = SLOW_FACTOR
		_arena.add_child(director)
		_arena.director = director
	var rows: Array[Dictionary] = []
	for count in COUNTS:
		rows.append(await _measure(count))
		_clear_crowd()
		await get_tree().physics_frame
	return rows


func _measure(count: int) -> Dictionary:
	var director := _arena.director if _arena.director != null else _arena.add_director()
	director.desktop_cap = maxi(director.desktop_cap, count)
	_arena.add_target("Visitor", Vector3(0.5, 0.0, 0.5))
	_arena.add_target("Raider", Vector3(9.5, 0.0, 9.5), &"enemy")
	var crowd: Array[AiCharacter] = []
	var side := ceili(sqrt(count))
	for index in count:
		var spot := Vector3(
			(index % side - side / 2.0) * SPACING + 0.3,
			0.0,
			(index / side - side / 2.0) * SPACING + 0.3
		)
		crowd.append(_arena.add_kind(CIVILIAN, spot, TAU * index / count))
	for _i in WARM_TICKS:
		await get_tree().physics_frame
	var calibrations := PackedFloat64Array([_ruler.measure_ms()])
	var candidates: Dictionary[String, PackedFloat64Array] = {}
	_time_candidates(candidates)
	var thinks := PackedInt32Array()
	var queries := PackedInt32Array()
	var rays := PackedInt32Array()
	for character in crowd:
		thinks.append(character.think_count)
		queries.append((character.navigator as AiNavigator).path_queries)
		rays.append((character.senses as AiSenses).rays_cast)
	var history := AiHitHistory.new()
	var ids: Dictionary[int, AiCharacter] = {}
	for index in crowd.size():
		ids[index + 1] = crowd[index]
	var steps := PackedFloat64Array()
	var think_times := PackedFloat64Array()
	var histories := PackedFloat64Array()
	var walking := 0
	var rays_over := 0
	var budget_over := 0
	var last_counts := thinks.duplicate()
	for tick in TICKS:
		await get_tree().physics_frame
		steps.append(float(director.last_step_usec) / count)
		var budget := director.budget
		if budget.paths > budget.paths_per_tick or budget.rays > budget.rays_per_tick:
			budget_over += 1
		if budget.thinks > budget.thinks_per_tick:
			budget_over += 1
		history.record(tick, ids)
		histories.append(float(history.last_record_us) / count)
		for index in crowd.size():
			var character := crowd[index]
			var navigator := character.navigator as AiNavigator
			if navigator.is_active() and not navigator.is_arrived():
				walking += 1
			if character.think_count != last_counts[index]:
				last_counts[index] = character.think_count
				think_times.append(character.last_think_usec)
				if (character.senses as AiSenses).last_rays > character.profile.max_rays_per_think:
					rays_over += 1
		if (tick + 1) % CALIBRATE_TICKS == 0:
			calibrations.append(_ruler.measure_ms())
			_time_candidates(candidates)
	var seconds := float(TICKS) / Engine.physics_ticks_per_second
	var storms := 0
	var fast_thinkers := 0
	var asked := 0
	var thought := 0
	var cast := 0
	for index in crowd.size():
		var character := crowd[index]
		var navigator := character.navigator as AiNavigator
		var own_queries := navigator.path_queries - queries[index]
		var own_thinks := character.think_count - thinks[index]
		asked += own_queries
		thought += own_thinks
		cast += (character.senses as AiSenses).rays_cast - rays[index]
		if own_queries > seconds / AiSoakWatch.repath_of(navigator) + 1.0:
			storms += 1
		if own_thinks > seconds * character.profile.think_rate + 1.0:
			fast_thinkers += 1
	var calibration := maxf(median(calibrations), 0.001)
	var step_each := median(steps)
	var think_each := median(think_times)
	var history_each := median(histories)
	var row := {
		"count": count,
		"pid": OS.get_process_id(),
		"ruler_ms": snappedf(calibration, 0.01),
		"system": OS.get_name(),
		"step_us_each": snappedf(step_each, 0.01),
		"think_us": snappedf(think_each, 0.1),
		"history_us_each": snappedf(history_each, 0.001),
		"step_ratio": snappedf(step_each / calibration, 0.001),
		"think_ratio": snappedf(think_each / calibration, 0.001),
		"history_ratio": snappedf(history_each / maxf(step_each, 0.001), 0.0001),
		"walking_share": snappedf(float(walking) / (TICKS * count), 0.01),
		"queries_per_s_each": snappedf(asked / seconds / count, 0.01),
		"thinks_per_s_each": snappedf(thought / seconds / count, 0.01),
		"rays_per_think": snappedf(float(cast) / maxi(thought, 1), 0.01),
		"storms": storms,
		"fast_thinkers": fast_thinkers,
		"rays_over": rays_over,
		"budget_over": budget_over,
	}
	for key in candidates:
		row[key] = snappedf(median(candidates[key]), 0.001)
	return row


## Times every `RulerCandidates` ruler once (right after the physics ruler) into `into`, by name:
## printed beside the step for the soak to compare, never judged (kit #1534).
func _time_candidates(into: Dictionary[String, PackedFloat64Array]) -> void:
	var times := _candidates.measure_ms()
	for key in times:
		var values: PackedFloat64Array = into.get(key, PackedFloat64Array())
		values.append(times[key])
		into[key] = values


func _clear_crowd() -> void:
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		if _arena.is_ancestor_of(node):
			node.free()
	for target_name in ["Visitor", "Raider"]:
		var target := _arena.get_node_or_null(target_name)
		if target != null:
			target.free()
	AiSensePool.forget()


static func median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
