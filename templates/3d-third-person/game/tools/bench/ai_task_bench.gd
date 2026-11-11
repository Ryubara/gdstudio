extends Node
## What the task system costs (gdstudio #965): `AiTaskRunner.tick` for 40 and 200 runners, each
## with a typical stack of three tasks (DEFAULT idle, a ROUTINE patrol that is a repeat of a
## walk and a wait, and a RESPONSE investigate given every few seconds, which suspends the patrol
## and resumes it), plus the cost of an idle runner. No bodies and no scene: the runner's own
## work, which a character's think adds to the director's step.
##
## Every runner is stepped on every physics tick (six times the 10 Hz think at 60 Hz, so the
## number is a ceiling); `us_each` is one runner's step, and `think_tick_us_40` what 40
## characters thinking at 10 Hz add to a physics tick (40 / 6 thinks a tick).
##
## One line of JSON, `AI_TASK_BENCH {...}`. Desktop:
## `godot --headless --fixed-fps 60 --path game res://tools/bench/ai_task_bench.tscn`; browser: a
## web export with this scene as `run/main_scene` and `tools/*` out of the exclude filter, read by
## `tools/bench/ai_task_bench.py` (`window.__ai_task_bench`).

const COUNTS: Array[int] = [40, 200]
const WARM_TICKS := 120
const TICKS := 600
const STEP := 1.0 / 60.0
## Seconds between two investigations of one runner (each runner is offset).
const NOISE_EVERY := 4.0
## Ticks of the director's think interval at 10 Hz on a 60 Hz tick.
const THINK_INTERVAL := 6

var _runners: Array[AiTaskRunner] = []
var _controllers: Array[AiController] = []
var _rng := RandomNumberGenerator.new()


## Walks along `walk` on the movement channel for `seconds`, as a patrol leg or a go-to would.
class BenchWalk:
	extends AiTask
	var seconds := 2.0
	var walk := Vector3.FORWARD

	func update(_delta: float) -> Status:
		controller.walk_direction = walk
		return Status.SUCCEEDED if elapsed >= seconds else Status.RUNNING


## Stands for `seconds`, looking along `look` (a wait, a look-around, an idle).
class BenchWait:
	extends AiTask
	var seconds := 1.0
	var look := Vector3.LEFT

	func update(_delta: float) -> Status:
		controller.look_direction = look
		return Status.SUCCEEDED if seconds > 0.0 and elapsed >= seconds else Status.RUNNING


func _ready() -> void:
	_rng.seed = 965
	var rows: Array[Dictionary] = []
	for count in COUNTS:
		rows.append(_measure(count, true))
	rows.append(_measure(200, false))
	var result := {"ticks": TICKS, "rows": rows}
	var forty: Dictionary = rows[0]
	result["think_tick_us_40"] = forty.us_each * 40.0 / THINK_INTERVAL
	var line := JSON.stringify(result)
	print("AI_TASK_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ai_task_bench = %s;" % line, true)
	_free_all()
	get_tree().quit()


func _measure(count: int, busy: bool) -> Dictionary:
	_free_all()
	for _index in count:
		_runners.append(_make_runner(busy))
	var noise_at := PackedFloat32Array()
	for _index in count:
		noise_at.append(_rng.randf_range(0.0, NOISE_EVERY))
	var times := PackedFloat64Array()
	var clock := 0.0
	for tick in WARM_TICKS + TICKS:
		clock += STEP
		var start := Time.get_ticks_usec()
		for index in count:
			var runner := _runners[index]
			if busy and clock >= noise_at[index]:
				noise_at[index] += NOISE_EVERY
				runner.assign(_investigate())
			runner.tick(STEP)
		if tick >= WARM_TICKS:
			times.append(Time.get_ticks_usec() - start)
	times.sort()
	var total := 0.0
	for value in times:
		total += value
	var mean := total / times.size()
	return {
		"runners": count,
		"busy": busy,
		"tick_mean_us": mean,
		"tick_p95_us": times[int(times.size() * 0.95)],
		"us_each": mean / count,
		"decisions": _runners[0].decisions.written,
	}


func _make_runner(busy: bool) -> AiTaskRunner:
	var runner := AiTaskRunner.new()
	var controller := AiController.new()
	_controllers.append(controller)
	runner.controller = controller
	if not busy:
		return runner
	var idle := BenchWait.new()
	idle.layer = AiTask.Layer.DEFAULT
	idle.seconds = 0.0
	idle.ends_on_condition = true
	runner.assign(idle)
	var leg := BenchWalk.new()
	leg.walk = Vector3.FORWARD.rotated(Vector3.UP, _rng.randf_range(-PI, PI))
	var wait := BenchWait.new()
	var route := AiTaskSequence.new()
	route.children = [leg, wait]
	var patrol := AiTaskRepeat.new()
	patrol.id = &"patrol"
	patrol.children = [route]
	runner.assign(patrol)
	return runner


func _investigate() -> AiTask:
	var look := BenchWalk.new()
	look.id = &"investigate"
	look.layer = AiTask.Layer.RESPONSE
	look.seconds = 1.0
	return look


func _free_all() -> void:
	for controller in _controllers:
		controller.free()
	_controllers.clear()
	_runners.clear()
