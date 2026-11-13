# On the clock: the gate times the AI's step and thinks, held as a ratio of a ruler loop timed
# between the measured ticks, medians on both sides, so a busy machine slows both
# (`performance-budgets.md#reading-a-timing-on-a-shared-machine`). The ruler is GDScript work of
# the AI's kind (vectors, an array, a dictionary), not the soak's `sin` loop: the C library's
# `sin` ran 1.65 times faster on the Linux runner than on Windows while the AI's step cost the
# same, so a limit in `sin` loops failed CI and held loose on the desktop.
#
# The AI's cost gate (kit #971): 50, 100 and 200 civilians (the template's `civilian.tscn`) going
# about a 28 m mesh round a visitor in the player's faction and a raider in the enemy's (seen,
# fled from: the senses cast their rays), under the director's shipped
# budgets (its desktop cap raised to hold 200). Counts first, held exactly: no character asks
# for a path more often than its `repath_seconds` allows, thinks more often than its profile's
# rate, or casts more than `max_rays_per_think` (2) rays a think; the shared budget is never
# overspent. Time second, loose: the director's step a character a tick, a think, and the server's
# record of the AI's hit volumes (`AiHitHistory`, the `ai_history_us` of the server's `stats`
# line) a character, each a median: the step and a think over the median of the ruler timed
# every `CALIBRATE_TICKS` ticks, the history (a section of a few microseconds that a
# loop of arithmetic does not follow) over the step of the same ticks; limits sit between the
# highest ratio seen with a second suite loading the machine and twice the lowest, so a step
# twice as slow fails (the docs table: `third-person/ai-characters.md#cost-gate`). A failure
# says the number. The crowd must walk (a crowd whose paths all fail costs nothing: `crowds.md`).
extends GdUnitTestSuite

const CIVILIAN := "res://gameplay/ai/characters/civilian.tscn"
const COUNTS: Array[int] = [50, 100, 200]
const WARM_TICKS := 120
const TICKS := 300
## Metres between two characters of the grid they start on.
const SPACING := 1.6
## Ticks between two timings of the ruler in the measured window.
const CALIBRATE_TICKS := 50
## The director's step a character a tick (median), microseconds a ruler millisecond (median),
## at most, by crowd size.
const STEP_RATIO_LIMITS: Dictionary[int, float] = {50: 8.0, 100: 7.5, 200: 6.5}
## A think (median), microseconds a ruler millisecond, at most, by crowd size (a think
## grows with the crowd it reads).
const THINK_RATIO_LIMITS: Dictionary[int, float] = {50: 13.0, 100: 14.0, 200: 18.0}
## The hit history's record (median) over the director's step (median) of the same ticks, at
## most, by crowd size.
const HISTORY_RATIO_LIMITS: Dictionary[int, float] = {50: 0.055, 100: 0.06, 200: 0.09}
## The share of the time the crowd must spend walking, at least.
const WALKING_SHARE_MIN := 0.2

var _arena: BehaviourArena
var _rulers: CostRulers


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_rulers = CostRulers.new()
	_arena.add_child(_rulers)
	_arena.build()
	await _arena.settle()


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func test_the_ai_holds_its_counts_and_its_cost() -> void:
	var rows: Array[Dictionary] = []
	for count in COUNTS:
		rows.append(await _measure(count))
		_clear_crowd()
		await get_tree().physics_frame
	var table := PackedStringArray()
	for row in rows:
		table.append(JSON.stringify(row))
	print("AI_COST_GATE\n" + "\n".join(table))
	for row in rows:
		var where := "at %d: %s" % [row.count, JSON.stringify(row)]
		(
			assert_int(row.storms)
			. override_failure_message("path queries over the rate " + where)
			. is_zero()
		)
		(
			assert_int(row.fast_thinkers)
			. override_failure_message("thinks over the rate " + where)
			. is_zero()
		)
		assert_int(row.rays_over).override_failure_message("rays over 2 a think " + where).is_zero()
		assert_int(row.budget_over).override_failure_message("budget overspent " + where).is_zero()
		assert_float(row.walking_share).override_failure_message("the crowd did not walk " + where)
		assert_float(row.walking_share).is_greater_equal(WALKING_SHARE_MIN)
		assert_float(row.step_ratio).override_failure_message("step over budget " + where)
		assert_float(row.step_ratio).is_less_equal(STEP_RATIO_LIMITS[row.count])
		assert_float(row.think_ratio).override_failure_message("think over budget " + where)
		assert_float(row.think_ratio).is_less_equal(THINK_RATIO_LIMITS[row.count])
		assert_float(row.history_ratio).override_failure_message("history over budget " + where)
		assert_float(row.history_ratio).is_less_equal(HISTORY_RATIO_LIMITS[row.count])


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
	var sin_loop := AiSoakWatch.calibrate()
	var calibrations := PackedFloat64Array([CostRulers.script_ms()])
	var physics_rulers := PackedFloat64Array([_rulers.physics_ms()])
	var crowd_nodes: Array[Node] = []
	for character in crowd:
		crowd_nodes.append_array(CostRulers.nodes_under(character))
	var tree_rulers := PackedFloat64Array([CostRulers.tree_ms(crowd_nodes)])
	var memory_rulers := PackedFloat64Array([CostRulers.memory_ms()])
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
			calibrations.append(CostRulers.script_ms())
			physics_rulers.append(_rulers.physics_ms())
			tree_rulers.append(CostRulers.tree_ms(crowd_nodes))
			memory_rulers.append(CostRulers.memory_ms())
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
	var calibration := maxf(_median(calibrations), 0.001)
	var step_each := _median(steps)
	var think_each := _median(think_times)
	var history_each := _median(histories)
	var physics_ruler := maxf(_median(physics_rulers), 0.001)
	var step_low := _quantile(steps, 0.1)
	var tree_ruler := maxf(_median(tree_rulers), 0.001)
	return {
		"count": count,
		"ruler_ms": snappedf(calibration, 0.01),
		"sin_loop_ms": snappedf(sin_loop, 0.01),
		"physics_ruler_ms": snappedf(physics_ruler, 0.01),
		"step_p10_us_each": snappedf(step_low, 0.01),
		"step_p25_us_each": snappedf(_quantile(steps, 0.25), 0.01),
		"think_p25_us": snappedf(_quantile(think_times, 0.25), 0.1),
		"tree_ruler_ms": snappedf(tree_ruler, 0.01),
		"memory_ruler_ms": snappedf(_median(memory_rulers), 0.01),
		"crowd_nodes": crowd_nodes.size(),
		"step_tree_ratio": snappedf(step_each / tree_ruler, 0.001),
		"think_tree_ratio": snappedf(think_each / tree_ruler, 0.001),
		"step_physics_ratio": snappedf(step_each / physics_ruler, 0.001),
		"think_physics_ratio": snappedf(think_each / physics_ruler, 0.001),
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


func _clear_crowd() -> void:
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		if _arena.is_ancestor_of(node):
			node.free()
	for target_name in ["Visitor", "Raider"]:
		var target := _arena.get_node_or_null(target_name)
		if target != null:
			target.free()
	AiSensePool.forget()


static func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


static func _quantile(values: PackedFloat64Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * share), sorted.size() - 1)]
