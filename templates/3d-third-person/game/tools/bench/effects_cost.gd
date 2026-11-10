## Measures what the effect emitter costs while the pistol fires: the pistol shoots every physics
## tick it is allowed to, in six runs (nothing fired; shots with no flash and no impacts; with the
## flash; with flash and impacts; the same at 30 shots a second), and for each the frame time,
## the script time (`Performance.TIME_PROCESS` and `TIME_PHYSICS_PROCESS`), the draw calls, the
## nodes and the slowest frame are printed on lines starting `BENCH`. The first run with a flash
## also prints the cost of the very first flash (`FIRST`): the instancing and the first draw.
##
## On a computer (the numbers depend on the renderer, so run both):
## `gds godot -- --path game --scene res://tools/bench/effects_cost.tscn --rendering-method
## gl_compatibility` (and without the flag for Forward+). In the browser, export the project with
## the scene as the main scene (`run/main_scene`), serve it and read `window.gdbench` (an array of
## the runs) once `window.gdbench_done` is true.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Frames waited before a run is measured, and frames measured.
const WARM_FRAMES := 90
const MEASURED_FRAMES := 300

## The runs: a name, the weapon's fire rate (0 fires nothing), whether the flash and impacts are on.
const RUNS: Array[Dictionary] = [
	{"name": "idle", "rate": 0.0, "flash": false, "impacts": false},
	{"name": "shots_only_4", "rate": 4.0, "flash": false, "impacts": false},
	{"name": "flash_4", "rate": 4.0, "flash": true, "impacts": false},
	{"name": "flash_and_impacts_4", "rate": 4.0, "flash": true, "impacts": true},
	{"name": "shots_only_30", "rate": 30.0, "flash": false, "impacts": false},
	{"name": "flash_and_impacts_30", "rate": 30.0, "flash": true, "impacts": true},
]

var _run := -1
var _frame := 0
var _last := 0
var _times: Array[float] = []
var _script_ms := 0.0
var _physics_ms := 0.0
var _calls := 0
var _nodes := 0
var _results: Array = []
var _first_printed := false

@onready var _player: Player = $Main/Player
@onready var _camera: Camera3D = $Main/Camera
@onready var _emitter: EffectEmitter = $Main/Effects


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_player.teleport(Vector3(-6.0, 0.0, 14.5), 0.0)
	_next_run()


func _physics_process(_delta: float) -> void:
	if _run < 0 or _run >= RUNS.size():
		return
	var weapon := _player.weapon
	if float(RUNS[_run]["rate"]) > 0.0 and _frame >= 0:
		if weapon.can_fire():
			var started := Time.get_ticks_usec()
			weapon.fire()
			var spent := (Time.get_ticks_usec() - started) / 1000.0
			if bool(RUNS[_run]["flash"]) and not _first_printed:
				_first_printed = true
				print("FIRST fire() with the first flash took %.3f ms" % spent)
				_results.append({"first_fire_ms": spent})


func _process(_delta: float) -> void:
	if _run < 0 or _run >= RUNS.size():
		return
	var now := Time.get_ticks_usec()
	_frame += 1
	if _frame > WARM_FRAMES:
		_times.append((now - _last) / 1000.0)
		_script_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_last = now
	if _frame >= WARM_FRAMES + MEASURED_FRAMES:
		_finish_run()


func _next_run() -> void:
	_run += 1
	_frame = 0
	_times.clear()
	_script_ms = 0.0
	_physics_ms = 0.0
	_calls = 0
	if _run >= RUNS.size():
		_done()
		return
	var spec := RUNS[_run]
	var weapon := _player.weapon
	weapon.fire_rate = maxf(float(spec["rate"]), 0.5)
	weapon.muzzle_flash_enabled = bool(spec["flash"])
	weapon.impacts = bool(spec["impacts"])
	weapon.projectile_lifetime = 1.0
	_emitter.stop_all()
	_last = Time.get_ticks_usec()


func _finish_run() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var mean := 0.0
	for value in sorted:
		mean += value
	mean /= sorted.size()
	var result := {
		"name": RUNS[_run]["name"],
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"frame_ms_mean": snappedf(mean, 0.001),
		"frame_ms_p95": snappedf(sorted[int(sorted.size() * 0.95)], 0.001),
		"frame_ms_max": snappedf(sorted[sorted.size() - 1], 0.001),
		"script_ms": snappedf(_script_ms / MEASURED_FRAMES, 0.001),
		"physics_script_ms": snappedf(_physics_ms / MEASURED_FRAMES, 0.001),
		"draw_calls": snappedf(float(_calls) / MEASURED_FRAMES, 0.1),
		"nodes": _nodes,
		"slots": _emitter.slot_count(),
	}
	print("BENCH ", JSON.stringify(result))
	_results.append(result)
	_next_run()


func _done() -> void:
	_emitter.stop_all()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"window.gdbench = %s; window.gdbench_done = true;" % JSON.stringify(_results)
		)
		return
	set_process(false)
	set_physics_process(false)
	Input.action_release(&"fire")
	AudioSettings.stop_players(get_tree().root)
	for _frame_wait in 8:
		await get_tree().process_frame
	get_tree().quit()
