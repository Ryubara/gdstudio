extends Node
## What the AI section's population costs (kit #969): the `AiDirector`'s step (tiers, thinks with
## the senses, the brains and the tasks, and every body's step) and the frame's work beside it, in
## the real game (`main.tscn`) with the section's whole population (3 grunts, 2 shooters, 2 allies,
## 3 civilians) awake around the player.
##
## Two rows, each in a fresh `main.tscn`: `watch`, the player (invulnerable) stands in the doorway
## looking in and never fires, so the enemies engage, the allies follow and the civilians go about
## their homes; `fight`, `SectionPilot` walks the player round the section and shoots whatever is
## hostile in its sight, as the soak does (`tools/soak/ai_soak.tscn`): deaths, respawns,
## civilians fleeing from shots. A row starts once every spawner has put out its count, warms up
## for `WARM_TICKS` and measures `TICKS`.
##
## One line of JSON, `AI_SECTION_BENCH {...}`: for each row the director's step a tick
## (`step_mean_us`, `step_p95_us`), the living characters on average and the step for each
## (`us_each`), the median frame work in milliseconds, frames, ticks and ticks a frame, and a
## calibration loop timed before the row (`calibration_ms`: a busy machine reads slower there too).
## Desktop: `godot --headless --fixed-fps 60 --path game res://tools/bench/ai_section_bench.tscn`;
## browser: `gds template bench-web 3d-third-person ai_section_bench --run`, read by
## `tools/bench/ai_section_bench.py` (`window.__ai_section_bench`).

const MAIN := "res://main.tscn"
const MODES: Array[String] = ["watch", "fight"]
const WARM_TICKS := 120
const TICKS := 900
## Ticks a row waits at most for the population to be out.
const SPAWN_TICKS := 600
const CALIBRATION_ROUNDS := 200000
## The pilot's loop in the section's space (its origin is the doorway), the soak's.
const LOOP: Array[Vector3] = [
	Vector3(-3.0, 0.0, 0.0),
	Vector3(-12.0, 0.0, -4.0),
	Vector3(-20.0, 0.0, -12.0),
	Vector3(-25.0, 0.0, 1.5),
	Vector3(-12.0, 0.0, 11.0),
	Vector3(-6.0, 0.0, 3.0),
]

var _main: Node
var _frame_end: FrameEnd
var _works: Array[float] = []
var _steps: Array[float] = []
var _alive := 0
var _tick_start := -1
var _ticks := 0


## Processed after every other node: says when a frame's processing is over.
class FrameEnd:
	extends Node
	signal done

	func _init() -> void:
		process_priority = 1 << 30

	func _process(_delta: float) -> void:
		done.emit()


func _ready() -> void:
	_frame_end = FrameEnd.new()
	add_child(_frame_end)
	_run.call_deferred()


func _run() -> void:
	var report := {"ticks": TICKS, "web": OS.has_feature("web"), "rows": []}
	for mode in MODES:
		_main = (load(MAIN) as PackedScene).instantiate()
		add_child(_main)
		await get_tree().process_frame
		_place_player(mode)
		report.rows.append(await _measure(mode))
		_main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	var line := JSON.stringify(report)
	print("AI_SECTION_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ai_section_bench = %s;" % line, true)
	else:
		get_tree().quit()


func _place_player(mode: String) -> void:
	var player := _main.get_node("PlayerRig/Player") as Player
	Health.of(player).invulnerable = true
	var section := _main.get_node("World/AISection") as Node3D
	var points := PackedVector3Array()
	for point in LOOP:
		points.append(section.to_global(point))
	player.teleport(points[0], -PI / 2.0)
	if mode == "fight":
		var pilot := SectionPilot.new()
		pilot.player = player
		pilot.camera_rig = _main.get_node("PlayerRig/PlayerCamera")
		pilot.waypoints = points
		_main.add_child(pilot)


func _spawners() -> Array[AiSpawner]:
	var found: Array[AiSpawner] = []
	for node in _main.get_node("World/AISection/Population").get_children():
		if node is AiSpawner:
			found.append(node)
	return found


func _population_out() -> bool:
	for spawner in _spawners():
		if spawner.spawned_total < spawner.count:
			return false
	return true


func _measure(mode: String) -> Dictionary:
	var waited := 0
	while not _population_out() and waited < SPAWN_TICKS:
		await get_tree().physics_frame
		waited += 1
	for _i in WARM_TICKS:
		await get_tree().physics_frame
	var calibration := _calibrate()
	_ticks = 0
	_alive = 0
	_works.clear()
	_steps.clear()
	_tick_start = -1
	get_tree().physics_frame.connect(_on_tick)
	_frame_end.done.connect(_on_frame_end)
	var frames := 0
	while _ticks < TICKS:
		await get_tree().process_frame
		frames += 1
	_frame_end.done.disconnect(_on_frame_end)
	get_tree().physics_frame.disconnect(_on_tick)
	var steps := _steps.duplicate()
	steps.sort()
	_works.sort()
	var total := 0.0
	for spent in steps:
		total += spent
	var mean := total / maxi(steps.size(), 1)
	var alive := float(_alive) / maxi(_ticks, 1)
	return {
		"mode": mode,
		"spawn_ticks": waited,
		"calibration_ms": calibration,
		"frames": frames,
		"ticks": _ticks,
		"ticks_per_frame": float(_ticks) / maxi(frames, 1),
		"alive": alive,
		"step_mean_us": mean,
		"step_p95_us": steps[int(steps.size() * 0.95)] if not steps.is_empty() else -1.0,
		"us_each": mean / maxf(alive, 1.0),
		"work_ms": _works[_works.size() / 2] if not _works.is_empty() else -1.0,
	}


func _on_tick() -> void:
	_ticks += 1
	if _tick_start < 0:
		_tick_start = Time.get_ticks_usec()
	var director := AiDirector.find(get_tree())
	if director == null:
		return
	# The step of the tick before this one (the director runs inside the tick).
	if director.tick > 0:
		_steps.append(float(director.last_step_usec))
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var character := node as AiCharacter
		if character != null and not character.is_dead():
			_alive += 1


func _on_frame_end() -> void:
	if _tick_start >= 0:
		_works.append((Time.get_ticks_usec() - _tick_start) / 1000.0)
	_tick_start = -1


# Milliseconds a fixed loop of GDScript takes: the machine's speed now.
func _calibrate() -> float:
	var start := Time.get_ticks_usec()
	var value := 0.0
	for index in CALIBRATION_ROUNDS:
		value = sin(value + index) * 0.5
	return (Time.get_ticks_usec() - start + int(value * 0.0)) / 1000.0
