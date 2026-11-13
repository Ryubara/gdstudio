# On the clock: the gate times the AI's step and thinks, held as a ratio of a ruler of the
# engine's physics (`PhysicsRuler`: a capsule's `move_and_slide` and rays) timed between the
# measured ticks, medians on both sides, so a slow runner or a busy machine slows both
# (`performance-budgets.md#reading-a-timing-on-a-shared-machine`). Over 150 runs on GitHub's
# Linux runners (four processor models) the step read 1.55 times from the fastest run to the
# slowest over this ruler, against 1.7 over a loop of GDScript and 1.9 over a `sin` loop: the
# step varies from run to run on one runner while every ruler holds, so no ruler follows all of
# it, and the limits sit 14 to 18 % over the highest ratio of those runs and under twice the
# lowest. Linux and Windows have tables of their own (the same code builds to different speeds).
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
# ruler does not follow) over the step of the same ticks. The second case runs the gate on a
# director whose step costs twice its work (`SlowAiDirector`) and must see the step fail at every
# size: the gate's teeth (the docs table: `third-person/ai-characters.md#cost-gate`). A failure
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
## at most, by system and crowd size. Linux: 150 CI runs read 6.2 to 9.6, 5.9 to 8.1 and 5.0 to
## 6.4; Windows: four desktop runs with 25 Godot processes beside them, 10.5 to 12.2, 9.4 to
## 11.6 and 8.0 to 8.9 (twice as slow: 19.7, 20.3 and 15.1 at the least).
const STEP_RATIO_LIMITS := {
	"Linux": {50: 11.0, 100: 9.5, 200: 7.5},
	"Windows": {50: 15.0, 100: 14.0, 200: 11.5},
}
## A think (median), microseconds a ruler millisecond, at most, by system and crowd size (a think
## grows with the crowd it reads). Linux: 150 CI runs read 8.7 to 13.4, 11.1 to 15.4 and 14.8 to
## 19.6; Windows: the four desktop runs, 12.7 to 15.4, 17.4 to 20.2 and 23.6 to 26.0.
const THINK_RATIO_LIMITS := {
	"Linux": {50: 15.5, 100: 18.0, 200: 23.0},
	"Windows": {50: 19.0, 100: 25.0, 200: 32.0},
}
## The hit history's record (median) over the director's step (median) of the same ticks, at
## most, by crowd size (278 CI runs read at most 0.043, 0.051 and 0.062; the desktop 0.034, 0.041
## and 0.058).
const HISTORY_RATIO_LIMITS: Dictionary[int, float] = {50: 0.055, 100: 0.06, 200: 0.09}
## The share of the time the crowd must spend walking, at least.
const WALKING_SHARE_MIN := 0.2
## How many times its work the teeth case's step costs.
const SLOW_FACTOR := 2.0

var _arena: BehaviourArena
var _ruler: PhysicsRuler


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_ruler = PhysicsRuler.new()
	_arena.add_child(_ruler)
	_arena.build()
	await _arena.settle()


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func test_the_ai_holds_its_counts_and_its_cost() -> void:
	var rows := await _measure_all()
	print("AI_COST_GATE\n" + _table(rows))
	for row in rows:
		var faults := _judge(row)
		(
			assert_array(faults)
			. override_failure_message(
				"%s at %d: %s" % [", ".join(faults), row.count, JSON.stringify(row)]
			)
			. is_empty()
		)


func test_a_step_twice_as_slow_fails_the_gate() -> void:
	var slow := SlowAiDirector.new()
	slow.name = "AiDirector"
	slow.factor = SLOW_FACTOR
	_arena.add_child(slow)
	_arena.director = slow
	var rows := await _measure_all()
	print("AI_COST_GATE_SLOW\n" + _table(rows))
	for row in rows:
		var faults := _judge(row)
		var where := "at %d: %s" % [row.count, JSON.stringify(row)]
		(
			assert_array(faults)
			. override_failure_message("a step twice as slow passed the gate " + where)
			. contains(["step over budget"])
		)
		for fault in faults:
			(
				assert_bool(fault in ["step over budget", "think over budget"])
				. override_failure_message("the slow step broke a count: %s %s" % [fault, where])
				. is_true()
			)


## What a row breaks, empty when it holds.
static func _judge(row: Dictionary) -> PackedStringArray:
	var faults := PackedStringArray()
	if row.storms > 0:
		faults.append("path queries over the rate")
	if row.fast_thinkers > 0:
		faults.append("thinks over the rate")
	if row.rays_over > 0:
		faults.append("rays over 2 a think")
	if row.budget_over > 0:
		faults.append("budget overspent")
	if row.walking_share < WALKING_SHARE_MIN:
		faults.append("the crowd did not walk")
	if row.step_ratio > _limits(STEP_RATIO_LIMITS)[row.count]:
		faults.append("step over budget")
	if row.think_ratio > _limits(THINK_RATIO_LIMITS)[row.count]:
		faults.append("think over budget")
	if row.history_ratio > HISTORY_RATIO_LIMITS[row.count]:
		faults.append("history over budget")
	return faults


## This system's limits of `table` (Linux's on a system with none of its own).
static func _limits(table: Dictionary) -> Dictionary:
	return table.get(OS.get_name(), table["Linux"])


func _measure_all() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for count in COUNTS:
		rows.append(await _measure(count))
		_clear_crowd()
		await get_tree().physics_frame
	return rows


static func _table(rows: Array[Dictionary]) -> String:
	var table := PackedStringArray()
	for row in rows:
		table.append(JSON.stringify(row))
	return "\n".join(table)


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
	return {
		"count": count,
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
