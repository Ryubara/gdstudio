## Measures what the hitscan tracer (gdstudio #1270) costs while the pistol fires hitscan, flash,
## light and impacts on as in play. Five runs (nothing fired; hitscan shots without and with the
## tracer at 4 shots a second; the same at 30), each printing the frame time, the draw calls, the
## nodes and the slowest frame on a line starting `BENCH`. `first_frames_max_ms`, the slowest
## frame of the second before a run is measured, is the first streak's hitch in the first tracer
## run (a program linked at the first draw). At the end `micro` prints the script cost of one shot
## with and without the tracer, of one `TracerPool.draw` (the pool full, the oldest cut) and of
## one step of the pool full and empty.
##
## On a computer: `gds godot -- --path game --scene res://tools/bench/tracer_cost.tscn
## --rendering-method gl_compatibility` (and without the flag for Forward+). In the browser,
## `gds template bench-web 3d-third-person tracer_cost --run` (kit
## docs/engines/godot/web-probes.md#bench-web; `tracer_cost.py` reads it and counts the programs
## each run links). It lives in tools/, which the export leaves out, and nothing in the game refers
## to it.
extends Node

## Seconds waited before a run is measured, and seconds measured (by the clock: a frame is 2 ms
## on the desktop and 6 in Chrome, and a run must hold many shots at 4 a second).
const WARM_SECONDS := 1.0
const MEASURED_SECONDS := 5.0
## The runs: a name, the weapon's fire rate (0 fires nothing) and whether the tracer is on.
const RUNS: Array[Dictionary] = [
	{"name": "idle", "rate": 0.0, "tracer": false},
	{"name": "hitscan_4", "rate": 4.0, "tracer": false},
	{"name": "tracer_4", "rate": 4.0, "tracer": true},
	{"name": "hitscan_30", "rate": 30.0, "tracer": false},
	{"name": "tracer_30", "rate": 30.0, "tracer": true},
]
## Where the runs stand (facing north, along -Z: the shots meet the map 10 to 30 m out).
const START := Vector3(-6.0, 0.0, 14.5)
const TRACER := "res://gameplay/weapon/pistol_tracer.tres"
## How many calls each script cost is averaged over.
const MICRO_CALLS := 2000

var _run := -1
var _frame := 0
var _began := 0
var _last := 0
var _times: Array[float] = []
var _calls := 0
var _nodes := 0
var _shown := 0
var _results: Array = []
var _warm_max := 0.0
var _definition: WeaponDef

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _emitter: EffectEmitter = $Main/World/Effects
@onready var _pool: TracerPool = $Main/World/Tracers


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_player.teleport(START, 0.0)
	# Its own copy: the pistol's definition is shared by every weapon that holds it.
	_definition = _player.weapon.definition.duplicate()
	_definition.hitscan = true
	# No magazine: the runs fire at their rate for as long as they last, never reloading.
	_definition.magazine_size = 0
	_player.weapon.definition = _definition
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__mark && window.__mark('warm_up')")
	if _emitter.is_warming():
		await _emitter.warmed
	_next_run()


func _physics_process(_delta: float) -> void:
	if _run < 0 or _run >= RUNS.size():
		return
	if float(RUNS[_run]["rate"]) > 0.0 and _player.weapon.can_fire():
		_player.weapon.fire()


func _process(_delta: float) -> void:
	if _run < 0 or _run >= RUNS.size():
		return
	var now := Time.get_ticks_usec()
	var seconds := (now - _began) / 1000000.0
	_frame += 1
	if _frame > 1 and seconds <= WARM_SECONDS:
		_warm_max = maxf(_warm_max, (now - _last) / 1000.0)
	if seconds > WARM_SECONDS:
		_times.append((now - _last) / 1000.0)
		_calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		_shown = maxi(_shown, _pool.shown_count())
	_last = now
	if seconds >= WARM_SECONDS + MEASURED_SECONDS:
		_finish_run()


func _next_run() -> void:
	_run += 1
	_frame = 0
	_times.clear()
	_warm_max = 0.0
	_calls = 0
	_shown = 0
	if _run >= RUNS.size():
		_done()
		return
	var spec := RUNS[_run]
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__mark && window.__mark('%s')" % spec["name"])
	_definition.fire_rate = maxf(float(spec["rate"]), 0.5)
	_definition.tracer = load(TRACER) as TracerDef if bool(spec["tracer"]) else null
	_emitter.stop_all()
	_pool.clear()
	_last = Time.get_ticks_usec()
	_began = _last


func _finish_run() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var mean := 0.0
	for value in sorted:
		mean += value
	mean /= sorted.size()
	var result := {
		"name": RUNS[_run]["name"],
		"renderer": RenderingServer.get_current_rendering_method(),
		"frame_ms_mean": snappedf(mean, 0.001),
		"frame_ms_p95": snappedf(sorted[int(sorted.size() * 0.95)], 0.001),
		"frame_ms_max": snappedf(sorted[sorted.size() - 1], 0.001),
		"first_frames_max_ms": snappedf(_warm_max, 0.001),
		"frames": sorted.size(),
		"draw_calls": snappedf(float(_calls) / sorted.size(), 0.1),
		"nodes": _nodes,
		"streaks_most": _shown,
	}
	print("BENCH ", JSON.stringify(result))
	_results.append(result)
	_next_run()


# The script cost of one shot with and without the tracer, of one draw with the pool full, and of
# one step of the pool full and empty.
func _micro() -> Dictionary:
	var weapon := _player.weapon
	var shot_us := {}
	for with_tracer in [false, true]:
		_definition.tracer = load(TRACER) as TracerDef if with_tracer else null
		var spent := 0
		for _shot in MICRO_CALLS:
			weapon.make_ready()
			var started := Time.get_ticks_usec()
			weapon.fire()
			spent += Time.get_ticks_usec() - started
		shot_us[with_tracer] = float(spent) / MICRO_CALLS
		_emitter.stop_all()
	var look := load(TRACER) as TracerDef
	var from := weapon.muzzle.global_position
	var to := from + Vector3.FORWARD * 20.0
	_pool.clear()
	var started := Time.get_ticks_usec()
	for _draw in MICRO_CALLS:
		_pool.draw(look, from, to)
	var draw_us := float(Time.get_ticks_usec() - started) / MICRO_CALLS
	var full := _pool.active_count()
	var advance_us := _advance_us()
	# Four streaks: what 30 shots a second keep showing (each lasts about 0.12 s).
	_pool.clear()
	for _draw in 4:
		_pool.draw(look, from, to)
	var advance_four_us := _advance_us()
	_pool.clear()
	started = Time.get_ticks_usec()
	for _step in MICRO_CALLS:
		_pool.advance(0.0)
	var idle_us := float(Time.get_ticks_usec() - started) / MICRO_CALLS
	return {
		"name": "micro",
		"shot_us_without_tracer": snappedf(shot_us[false], 0.01),
		"shot_us_with_tracer": snappedf(shot_us[true], 0.01),
		"draw_us": snappedf(draw_us, 0.01),
		"advance_us_full": snappedf(advance_us, 0.01),
		"advance_us_four": snappedf(advance_four_us, 0.01),
		"streaks_full": full,
		"advance_us_idle": snappedf(idle_us, 0.01),
	}


# One step of the pool as it is, the mean of `MICRO_CALLS` (no time passes, so none ends).
func _advance_us() -> float:
	var started := Time.get_ticks_usec()
	for _step in MICRO_CALLS:
		_pool.advance(0.0)
	return float(Time.get_ticks_usec() - started) / MICRO_CALLS


func _done() -> void:
	var micro := _micro()
	print("BENCH ", JSON.stringify(micro))
	_results.append(micro)
	_emitter.stop_all()
	_pool.clear()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"window.gdbench = %s; window.gdbench_done = true;" % JSON.stringify(_results)
		)
		return
	set_process(false)
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame_wait in 8:
		await get_tree().process_frame
	get_tree().quit()
