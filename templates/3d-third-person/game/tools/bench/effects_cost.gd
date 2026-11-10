## Measures what the effect emitter costs while the pistol fires. The pistol shoots every physics
## tick it is allowed to, in nine runs (nothing fired; shots with no flash and no impacts; the
## flash without its light; the flash; flash and impacts; the same two at 30 shots a second; then
## walking into the room with a probe of its own, and flash and impacts there), and
## for each the frame time, the draw calls, the nodes and the slowest frame are printed on lines
## starting `BENCH`. `first_frames_max_ms`, the slowest of the 90 frames before a run is measured,
## is the first-use hitch of the first run with a flash (and of the first with its light):
## programs built for a new draw. At the end `micro` prints the
## script cost of one play and of one step of the pool. `FIRST` is the first `fire()` call.
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

## The runs: a name, the weapon's fire rate (0 fires nothing), whether the flash (its light too) and
## impacts are on.
const RUNS: Array[Dictionary] = [
	{"name": "idle", "rate": 0.0, "flash": false, "light": false, "impacts": false},
	{"name": "shots_only_4", "rate": 4.0, "flash": false, "light": false, "impacts": false},
	{"name": "flash_no_light_4", "rate": 4.0, "flash": true, "light": false, "impacts": false},
	{"name": "flash_4", "rate": 4.0, "flash": true, "light": true, "impacts": false},
	{"name": "flash_and_impacts_4", "rate": 4.0, "flash": true, "light": true, "impacts": true},
	{"name": "shots_only_30", "rate": 30.0, "flash": false, "light": false, "impacts": false},
	{"name": "flash_and_impacts_30", "rate": 30.0, "flash": true, "light": true, "impacts": true},
	{
		"name": "room_enter",
		"rate": 0.0,
		"flash": false,
		"light": false,
		"impacts": false,
		"at": ROOM
	},
	{
		"name": "room_flash_and_impacts_4",
		"rate": 4.0,
		"flash": true,
		"light": true,
		"impacts": true
	},
]
## Where the runs start (facing north, along -Z), and the room with a reflection probe and a lamp of
## its own that the last runs walk into: the first time the player sees it (kit #981).
const START := Vector3(-6.0, 0.0, 14.5)
const ROOM := Vector3(14.0, 0.0, -12.0)
## How many plays the cost of one play is averaged over.
const MICRO_PLAYS := 2000

var _run := -1
var _frame := 0
var _last := 0
var _times: Array[float] = []
var _calls := 0
var _nodes := 0
var _results: Array = []
var _first_printed := false
var _flash_energy := -1.0
var _warm_max := 0.0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _camera: Camera3D = $Main/PlayerRig/Camera
@onready var _emitter: EffectEmitter = $Main/World/Effects


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_player.teleport(START, 0.0)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__mark && window.__mark('warm_up')")
	if _emitter.is_warming():
		await _emitter.warmed
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
	if _frame > 1 and _frame <= WARM_FRAMES:
		_warm_max = maxf(_warm_max, (now - _last) / 1000.0)
	if _frame > WARM_FRAMES:
		_times.append((now - _last) / 1000.0)
		_calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_last = now
	if _frame >= WARM_FRAMES + MEASURED_FRAMES:
		_finish_run()


func _next_run() -> void:
	_run += 1
	_frame = 0
	_times.clear()
	_warm_max = 0.0
	_calls = 0
	if _run >= RUNS.size():
		_done()
		return
	var spec := RUNS[_run]
	if spec.has("at"):
		_player.teleport(spec["at"], 0.0)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__mark && window.__mark('%s')" % spec["name"])
	var weapon := _player.weapon
	weapon.fire_rate = maxf(float(spec["rate"]), 0.5)
	weapon.muzzle_flash_enabled = bool(spec["flash"])
	_flash_energy = _flash_energy if _flash_energy >= 0.0 else weapon.muzzle_flash.light_energy
	weapon.muzzle_flash.light_energy = _flash_energy if bool(spec["light"]) else 0.0
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
		"renderer": RenderingServer.get_current_rendering_method(),
		"frame_ms_mean": snappedf(mean, 0.001),
		"frame_ms_p95": snappedf(sorted[int(sorted.size() * 0.95)], 0.001),
		"frame_ms_max": snappedf(sorted[sorted.size() - 1], 0.001),
		"first_frames_max_ms": snappedf(_warm_max, 0.001),
		"draw_calls": snappedf(float(_calls) / MEASURED_FRAMES, 0.1),
		"nodes": _nodes,
		"slots": _emitter.slot_count(),
	}
	print("BENCH ", JSON.stringify(result))
	_results.append(result)
	_next_run()


# The script cost of one play and of one step of the pool, with the pool full (the oldest is cut).
func _micro() -> Dictionary:
	var effect := _player.weapon.muzzle_flash
	var marker := _player.weapon.muzzle
	_emitter.stop_all()
	var started := Time.get_ticks_usec()
	for _play in MICRO_PLAYS:
		_emitter.play_on(effect, marker)
	var play_us := float(Time.get_ticks_usec() - started) / MICRO_PLAYS
	started = Time.get_ticks_usec()
	for _step in MICRO_PLAYS:
		_emitter.advance(0.0)
	var advance_us := float(Time.get_ticks_usec() - started) / MICRO_PLAYS
	var active := _emitter.active_count()
	_emitter.stop_all()
	started = Time.get_ticks_usec()
	for _step in MICRO_PLAYS:
		_emitter.advance(0.0)
	var idle_us := float(Time.get_ticks_usec() - started) / MICRO_PLAYS
	return {
		"name": "micro",
		"play_on_us": snappedf(play_us, 0.01),
		"advance_us_with_active": snappedf(advance_us, 0.01),
		"active": active,
		"advance_us_idle": snappedf(idle_us, 0.01),
	}


func _done() -> void:
	var micro := _micro()
	print("BENCH ", JSON.stringify(micro))
	_results.append(micro)
	_player.weapon.muzzle_flash.light_energy = _flash_energy
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
