class_name AiSoakProbe
extends RefCounted
## The AI soak's per-episode probe (kit #1543): the rows and blocks `AiSoakWatch` keeps when its
## `probe_episodes` is on. The watch adds one row a tick of each probed character to a ring, and
## when a stuck episode that counts toward `stuck_share` ends (past the grace, with walking in it)
## prints its block as one `AI_SOAK_EPISODE {json}` line. Off, the watch records nothing, so the
## soak's output and cost are unchanged.
##
## Only static functions: turning the probe on makes no object. The AI's run depends on how many
## objects were made before it (a noise maker takes its phase from its instance id), so a probe
## that made one would change the run it is there to explain.
##
## A block holds the character, its kind, when the episode began, its length and walking seconds,
## whether it was alive at the end and its last tick (`until`: a body that died in an episode keeps
## it open until the run's end), the column names and one row a tick from `LEAD_SECONDS` before the
## episode until its end, at most the watch's `probe_ticks`: time, place, ground speed, the watch's
## "going", the navigator's mode, arrived, path left, refusal, stuck rung and goal, the
## controller's push and sprint, the situation and the runner's active task. It says what a stuck
## rise was before anyone guesses what changed (gdstudio #1532: every civilian episode was a flee
## point the navigator refused).
##
## The soak turns it on with `--probe` (every kind) or `--probe Civilian,Grunt` (those kinds), the
## environment variable `SOAK_PROBE` (same values) or the watch's `probe_episodes` in the
## inspector. Docs: the kit's `docs/gamedev/bots.md#ai-soak`.

## The columns of a row, in order.
const COLUMNS: Array[String] = [
	"t",
	"x",
	"z",
	"speed",
	"going",
	"mode",
	"arrived",
	"left",
	"refusal",
	"rung",
	"goal",
	"push",
	"sprint",
	"situation",
	"task",
]
## Seconds before an episode's start its block shows (how it came to stand).
const LEAD_SECONDS := 1.0
## The line a block is printed with.
const PREFIX := "AI_SOAK_EPISODE "
## Option values that turn the probe off; any other is on.
const OFF: Array[String] = ["0", "off", "false", "no"]
## Option values that probe every kind; any other is a comma list of kinds.
const EVERY: Array[String] = ["", "1", "all", "true", "on", "yes"]


## True when the option's value (`--probe`, `SOAK_PROBE`) turns the probe on.
static func option_on(value: String) -> bool:
	return not value.strip_edges().to_lower() in OFF


## The kinds the option's value names (a comma list of profile display names); empty: every kind.
static func option_kinds(value: String) -> PackedStringArray:
	var names := PackedStringArray()
	var text := value.strip_edges()
	if text.to_lower() in EVERY or text.to_lower() in OFF:
		return names
	for part in text.split(",", false):
		names.append(part.strip_edges())
	return names


## `ring` with `row` added, trimmed to its last `ticks` rows once it holds twice as many (a tick
## costs no shift of the whole ring).
static func push(ring: Array, row: Array, ticks: int) -> Array:
	ring.append(row)
	if ring.size() > ticks * 2:
		return ring.slice(ring.size() - ticks)
	return ring


## The block of an episode of `character` that began at `began` and ends at `clock`, with
## `walking` seconds asked to walk (`alive`: watched this tick), from the last `ticks` rows of
## `ring`.
static func block_of(
	character: AiCharacter,
	kind: String,
	began: float,
	clock: float,
	walking: float,
	alive: bool,
	ring: Array,
	ticks: int
) -> Dictionary:
	var rows: Array = []
	for row: Array in ring.slice(maxi(ring.size() - ticks, 0)):
		if row[0] >= began - LEAD_SECONDS:
			rows.append(row)
	return {
		"character": String(character.name),
		"kind": kind,
		"from": snappedf(began, 0.01),
		"seconds": snappedf(clock - began, 0.01),
		"walking": snappedf(walking, 0.01),
		"alive": alive,
		"until": rows[-1][0] if not rows.is_empty() else snappedf(clock, 0.01),
		"columns": COLUMNS,
		"rows": rows,
	}


## One row (`COLUMNS`) of what `character` does now (`going`: the watch's "asking its navigator for
## a goal").
static func row_of(character: AiCharacter, clock: float, going: bool) -> Array:
	var at := character.global_position
	var row: Array = [
		snappedf(clock, 0.01),
		snappedf(at.x, 0.01),
		snappedf(at.z, 0.01),
		snappedf(character.ground_speed(), 0.01),
		going,
	]
	var navigator := character.navigator as AiNavigator
	if navigator != null:
		var goal := navigator.goal
		(
			row
			. append_array(
				[
					String(AiNavigator.Mode.keys()[navigator.mode]),
					navigator.is_arrived(),
					(
						snappedf(navigator.path.left(at), 0.01)
						if navigator.path.has_points()
						else -1.0
					),
					navigator.refusal.replace("\n", " "),
					navigator.ladder.rung_name(),
					[snappedf(goal.x, 0.1), snappedf(goal.z, 0.1)] if goal.is_finite() else [],
				]
			)
		)
	else:
		row.append_array(["", false, -1.0, "", "", []])
	var controller := character.ai_controller()
	if controller != null:
		row.append(snappedf(controller.walk_direction.length() * controller.walk_strength, 0.01))
		row.append(controller.sprint)
	else:
		row.append_array([-1.0, false])
	row.append(AiSituation.name_of(character.situation.current))
	var tasks := character.task_runner as AiTasks
	row.append(String(tasks.runner.describe().active) if tasks != null else "")
	return row
