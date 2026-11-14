# On the clock: the gate times the AI's step and thinks, held as a ratio of a ruler of the
# engine's physics (`PhysicsRuler`: a capsule's `move_and_slide` and rays) timed between the
# measured ticks, medians on both sides, so a slow runner or a busy machine slows both
# (`performance-budgets.md#reading-a-timing-on-a-shared-machine`). The ruler does not follow all
# of it: on unchanged code the step read up to 1.6 times apart inside the template job's long test
# process (the AI's counters and the heap differ with what ran before) and 1.3 to 1.45 in a
# process of its own, where the processor model is most of what is left. So the measure
# (`AiCostBench`) runs in fresh headless processes, `GATE_RUNS` of them, and the gate judges their
# median; and it judges the step as one score, the three crowd sizes pooled over their typical
# ratios, because a run's speed moves the sizes together while each size's own noise averages
# out. Linux and Windows have tables of their own (the same code builds to different speeds).
#
# The AI's cost gate (kit #971, #1526): 50, 100 and 200 civilians (the template's
# `civilian.tscn`) going about a 28 m mesh round a visitor in the player's faction and a raider in
# the enemy's (seen, fled from: the senses cast their rays), under the director's shipped budgets
# (its desktop cap raised to hold 200). Counts first, held exactly in every run: no character
# asks for a path more often than its `repath_seconds` allows, thinks more often than its
# profile's rate, or casts more than `max_rays_per_think` (2) rays a think; the shared budget is
# never overspent. Time second, loose, on the median of the runs: the step's score, each size's
# step over its typical ratio, a think over the ruler, and the server's record of the AI's hit
# volumes (`AiHitHistory`) over the step of the same ticks (a section of a few microseconds that
# a ruler does not follow). The second case runs the bench on a director whose step costs twice
# its work (`SlowAiDirector`) and must see the score fail: the gate's teeth (the docs table:
# `third-person/ai-characters.md#cost-gate`). A failure says the numbers. The crowd must walk (a
# crowd whose paths all fail costs nothing: `crowds.md`).
extends GdUnitTestSuite

const BENCH := "res://tests/fixtures/ai_cost_bench.tscn"
const COUNTS: Array[int] = [50, 100, 200]
## Fresh processes the gate measures in; it judges their median.
const GATE_RUNS := 3
## Fresh processes the teeth case measures in (the slow step reads far over the limit).
const SLOW_RUNS := 1
## The director's step a character a tick (median), microseconds a ruler millisecond (median),
## that unchanged code reads in a typical fresh process, by system and crowd size. Linux: the
## medians of 150 processes on CI (50 suite runs, 2026-11-14), which read 7.4 to 12.1, 6.7 to 9.7
## and 5.4 to 7.2; Windows: three desktop processes with other agents' Godot beside them.
const STEP_RATIO_TYPICAL := {
	"Linux": {50: 8.7, 100: 7.65, 200: 6.2},
	"Windows": {50: 11.0, 100: 9.5, 200: 7.8},
}
## The step's score at most: the geometric mean over the three sizes of the step ratio over its
## typical value, the median of the runs. Over 150 suite runs on CI (three soaks, five processor
## models) the gate scored 0.88 to 1.26 (a single process 0.87 to 1.27) and the step made twice as
## slow 1.76 to 2.54: the limit sits about 18 % above the one and below the other.
const STEP_SCORE_LIMIT := 1.48
## One size's step ratio over its typical value (the median of the runs) at most: a size that grew
## alone (a step that grows with the crowd) does not hide in the pool. The 150 suite runs read at
## most 1.32, 1.29 and 1.19.
const STEP_SIZE_LIMIT := 1.6
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


func test_the_ai_holds_its_counts_and_its_cost() -> void:
	var runs := _bench_runs(GATE_RUNS, false)
	var rows := _pooled(runs)
	var score := _median_score(runs)
	print("AI_COST_GATE score %.3f (runs %s)\n%s" % [score, _scores(runs), _table(rows)])
	(
		assert_float(score)
		. override_failure_message(
			(
				"step over budget: a score of %.3f over %.2f (runs %s)\n%s"
				% [score, STEP_SCORE_LIMIT, _scores(runs), _table(rows)]
			)
		)
		. is_less_equal(STEP_SCORE_LIMIT)
	)
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
	var runs := _bench_runs(SLOW_RUNS, true)
	var rows := _pooled(runs)
	var score := _median_score(runs)
	print("AI_COST_GATE_SLOW score %.3f\n%s" % [score, _table(rows)])
	(
		assert_float(score)
		. override_failure_message(
			"a step twice as slow passed the gate: a score of %.3f\n%s" % [score, _table(rows)]
		)
		. is_greater(STEP_SCORE_LIMIT)
	)
	for row in rows:
		var where := "at %d: %s" % [row.count, JSON.stringify(row)]
		for fault in _judge(row):
			(
				assert_bool(fault in ["step over budget at one size", "think over budget"])
				. override_failure_message("the slow step broke a count: %s %s" % [fault, where])
				. is_true()
			)


## What a pooled row breaks, empty when it holds.
static func _judge(row: Dictionary) -> PackedStringArray:
	var faults := PackedStringArray()
	if row.has("missing"):
		faults.append("%d run(s) printed no row" % row.missing)
		return faults
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
	if row.step_part > STEP_SIZE_LIMIT:
		faults.append("step over budget at one size")
	if row.think_ratio > _limits(THINK_RATIO_LIMITS)[row.count]:
		faults.append("think over budget")
	if row.history_ratio > HISTORY_RATIO_LIMITS[row.count]:
		faults.append("history over budget")
	return faults


## This system's limits of `table` (Linux's on a system with none of its own).
static func _limits(table: Dictionary) -> Dictionary:
	return table.get(OS.get_name(), table["Linux"])


## The step's score of one run's rows: the geometric mean of each row's `step_part`.
static func _step_score(rows: Array) -> float:
	if rows.is_empty():
		return 0.0
	var logs := 0.0
	for row: Dictionary in rows:
		logs += log(maxf(row.step_part, 0.0001))
	return exp(logs / rows.size())


## The median of the runs' scores (a run short of rows scores 0, and its missing rows fail).
static func _median_score(runs: Array) -> float:
	var scores := PackedFloat64Array()
	for rows: Array in runs:
		scores.append(_step_score(rows) if rows.size() == COUNTS.size() else 0.0)
	return AiCostBench.median(scores)


static func _scores(runs: Array) -> String:
	var parts := PackedStringArray()
	for rows: Array in runs:
		parts.append("%.3f" % _step_score(rows))
	return ", ".join(parts)


## One row a crowd size from all the runs: the counts at their worst, the timings at their median.
static func _pooled(runs: Array) -> Array[Dictionary]:
	var pooled: Array[Dictionary] = []
	for count in COUNTS:
		var rows: Array[Dictionary] = []
		for run: Array in runs:
			for row: Dictionary in run:
				if row.count == count:
					rows.append(row)
		if rows.size() < runs.size():
			pooled.append({"count": count, "missing": runs.size() - rows.size()})
			continue
		var row := rows[0].duplicate()
		for other in rows:
			for key in ["storms", "fast_thinkers", "rays_over", "budget_over"]:
				row[key] = maxi(row[key], other[key])
			row.walking_share = minf(row.walking_share, other.walking_share)
		for key in ["step_ratio", "step_part", "think_ratio", "history_ratio", "ruler_ms"]:
			var values := PackedFloat64Array()
			for other in rows:
				values.append(other[key])
			row[key] = AiCostBench.median(values)
		row.runs = rows.size()
		pooled.append(row)
	return pooled


## The rows of `runs` fresh headless processes of the bench (`slow`: the twice-as-slow director),
## one array a run, each row with its `step_part` over this system's typical ratio.
func _bench_runs(runs: int, slow: bool) -> Array:
	var all := []
	for _index in runs:
		var args := PackedStringArray(
			[
				"--headless",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"--fixed-fps",
				str(Engine.physics_ticks_per_second),
				BENCH,
			]
		)
		if slow:
			args.append_array(["--", "--slow"])
		var output: Array = []
		OS.execute(OS.get_executable_path(), args, output, true)
		var text := "\n".join(PackedStringArray(output))
		var rows: Array[Dictionary] = []
		for line in text.split("\n"):
			if not line.begins_with(AiCostBench.ROW_PREFIX):
				continue
			var row: Dictionary = JSON.parse_string(line.trim_prefix(AiCostBench.ROW_PREFIX))
			for key in ["count", "storms", "fast_thinkers", "rays_over", "budget_over"]:
				row[key] = int(row[key])
			row.step_part = snappedf(row.step_ratio / _limits(STEP_RATIO_TYPICAL)[row.count], 0.001)
			print(AiCostBench.ROW_PREFIX + JSON.stringify(row))
			rows.append(row)
		if rows.is_empty():
			print("AI_COST_BENCH printed no rows:\n" + text.right(3000))
		all.append(rows)
	return all


static func _table(rows: Array[Dictionary]) -> String:
	var table := PackedStringArray()
	for row in rows:
		table.append(JSON.stringify(row))
	return "\n".join(table)
