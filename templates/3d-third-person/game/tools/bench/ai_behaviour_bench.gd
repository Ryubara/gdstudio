extends Node
## What the AI's reactions cost (gdstudio #968): the `AiDirector`'s step (tiers, thinks with the
## senses, the brain and the tasks, and every body's step) and the frame's work beside it, for a
## crowd of `ai_guard.tscn` (the hostile guard set) with its brains off, on and calm, and on
## against a threat.
##
## The guards stand on a grid 3 m apart around two targets (stand-ins for players, in the group
## `player`) that walk a circle among them. In the `threat` rows the targets are of the faction
## `player`, so most guards see one and the rest hear the shots, and the guard set's whole stack
## runs (noticed, engage, chase, search, barks, the threat reminder, the play state); in `calm`
## they are of the guards' own faction, `enemy`, so nothing is perceived. Brains off removes each
## guard's `Brain` node before it enters the tree: the senses and the empty task runner still
## run, so the difference is what the reactions add (the brain's thinks, the tasks it places,
## and what those tasks make the body do: turn, aim, fire, walk). The director's web caps are
## the count, its Full cap the shipped one (12 in a browser, 60 on the desktop), and the
## animation throttle is on, as `world.tscn` has it.
##
## The `threat` rows run with the director's attack slots (kit #1203: in a browser 6 a target and
## 12 in all; the rest hold), the `uncapped` rows are the same fight with the slots and the fight
## cap set to the count (every guard that sees a target fires, as before #1203). `engaged` is the
## mean of slots held a tick, `holders_full` the slot holders at the Full tier at the end.
## `slots=4` and `fight_cap=8` set the `threat` rows' counts (a target, all) on any platform.
##
## Each row measures at least 300 frames and 600 ticks. One line of JSON, `AI_BEHAVIOUR_BENCH
## {...}`: for each count and mode the director's step a tick (`step_mean_us`, `step_p95_us`,
## `us_each`), the median frame work in milliseconds, frames, ticks and ticks a frame, a
## calibration loop timed before the row (`calibration_ms`: a busy machine reads slower there
## too), the events the brains routed a second and the guards by active task at the end.
## Desktop: `godot --headless --fixed-fps 60 --path game res://tools/bench/ai_behaviour_bench.tscn
## [-- --counts=50,100 --modes=threat,uncapped]`; browser: a web export with this scene as
## `run/main_scene` and `tools/*` out of the exclude filter, read by
## `tools/bench/ai_behaviour_bench.py`
## (`window.__ai_behaviour_bench`; the page's query takes the same `counts=50&modes=threat`).

const COUNTS: Array[int] = [50, 100]
## Brains off (senses and an empty runner), brains on with the targets friendly (the brain's own
## work with nothing to answer: the guard's default task), brains on with them hostile, and the
## same with no attack slots.
const MODES: Array[String] = ["off", "calm", "threat", "uncapped"]
const WARM_FRAMES := 120
const FRAMES := 300
## Ticks a row measures at least: a browser draws about three frames a tick at 1x, so 300 frames
## alone held only 90 ticks there, 15 thinks a guard (gdstudio #1104).
const MIN_TICKS := 600
const GUARD := "res://gameplay/ai/ai_guard.tscn"
const RELATIONS := "res://gameplay/ai/relations/ai_relations.tres"
const SPACING := 3.0
const TARGETS := 2
const TARGET_RADIUS := 6.0
## Radians a tick the targets walk round their circle.
const TARGET_TURN := 0.004
const CALIBRATION_ROUNDS := 200000

var _arena: Node3D
var _director: AiDirector
var _throttle: AiAnimationThrottle
var _characters: Array[AiCharacter] = []
var _targets: Array[Node3D] = []
var _frame_end: FrameEnd
var _works: Array[float] = []
var _steps: Array[float] = []
var _tick_start := -1
var _ticks := 0
var _tick := 0
var _counts: Array[int] = COUNTS.duplicate()
var _modes: Array[String] = MODES.duplicate()
var _engaged := 0
var _slots := -1
var _fight_cap := -1


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
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 30.0, 40.0)
	camera.rotation.x = deg_to_rad(-35.0)
	add_child(camera)
	camera.make_current()
	_run.call_deferred()


func _run() -> void:
	_read_options()
	var report := {"frames": FRAMES, "web": OS.has_feature("web"), "rows": []}
	for count in _counts:
		for mode in _modes:
			_new_crowd(count, mode)
			report.rows.append(await _measure(count, mode))
			_arena.free()
	var line := JSON.stringify(report)
	print("AI_BEHAVIOUR_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ai_behaviour_bench = %s;" % line, true)
	else:
		get_tree().quit()


# `counts=50,100` and `modes=threat,uncapped` from the command line after `--` or the page's
# query.
func _read_options() -> void:
	var words := PackedStringArray()
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true))
		words = query.trim_prefix("?").split("&", false)
	else:
		for word in OS.get_cmdline_user_args():
			words.append(word.trim_prefix("--"))
	for word in words:
		var parts := word.split("=")
		if parts.size() == 2 and parts[0] == "counts":
			_counts.clear()
			for part in parts[1].split(",", false):
				_counts.append(int(part))
		elif parts.size() == 2 and parts[0] == "slots":
			_slots = int(parts[1])
		elif parts.size() == 2 and parts[0] == "fight_cap":
			_fight_cap = int(parts[1])
		elif parts.size() == 2 and parts[0] == "modes":
			_modes.clear()
			for part in parts[1].split(",", false):
				if MODES.has(part):
					_modes.append(part)


func _new_crowd(count: int, mode: String) -> void:
	_arena = Node3D.new()
	add_child(_arena)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_arena.add_child(floor_body)
	var factions := AiFactions.new()
	factions.relations = load(RELATIONS) as AiRelations
	_arena.add_child(factions)
	_arena.add_child(AiNoise.new())
	_targets.clear()
	for index in TARGETS:
		var target := Node3D.new()
		target.name = "Target%d" % index
		target.add_to_group(&"player")
		var member := AiFactionMember.new()
		member.faction = &"player" if mode in ["threat", "uncapped"] else &"enemy"
		target.add_child(member)
		_arena.add_child(target)
		_targets.append(target)
	_tick = 0
	_move_targets()
	_director = AiDirector.new()
	_director.web_cap = count
	_director.desktop_cap = count
	if mode == "threat" and _slots >= 0:
		_director.web_attack_slots = _slots
		_director.desktop_attack_slots = _slots
	if mode == "threat" and _fight_cap >= 0:
		_director.web_fight_cap = _fight_cap
		_director.desktop_fight_cap = _fight_cap
	if mode == "uncapped":
		_director.web_attack_slots = count
		_director.desktop_attack_slots = count
		_director.web_fight_cap = count
		_director.desktop_fight_cap = count
	_throttle = AiAnimationThrottle.new()
	_director.add_child(_throttle)
	_director.animation_throttle = _throttle
	_arena.add_child(_director)
	_characters.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 968
	var side := ceili(sqrt(count))
	var scene := load(GUARD) as PackedScene
	for index in count:
		var character := scene.instantiate() as AiCharacter
		character.name = "Guard%d" % index
		if mode == "off":
			var brain := character.brain
			character.brain = null
			if brain != null:
				character.remove_child(brain)
				brain.free()
		var cell := (
			Vector2(index % side, floorf(float(index) / side)) - Vector2.ONE * (side - 1) / 2.0
		)
		character.position = Vector3(cell.x * SPACING, 0.0, cell.y * SPACING)
		_arena.add_child(character)
		character.facing = rng.randf() * TAU
		_characters.append(character)


func _move_targets() -> void:
	for index in _targets.size():
		var angle := _tick * TARGET_TURN + index * TAU / _targets.size()
		_targets[index].position = Vector3(
			cos(angle) * TARGET_RADIUS, 0.0, sin(angle) * TARGET_RADIUS
		)


func _measure(count: int, mode: String) -> Dictionary:
	get_tree().physics_frame.connect(_on_tick)
	for _i in WARM_FRAMES:
		await get_tree().process_frame
	var calibration := _calibrate()
	var routed_before := _routed()
	_ticks = 0
	_engaged = 0
	_works.clear()
	_steps.clear()
	_tick_start = -1
	_frame_end.done.connect(_on_frame_end)
	var frames := 0
	while frames < FRAMES or _ticks < MIN_TICKS:
		await get_tree().process_frame
		frames += 1
	_frame_end.done.disconnect(_on_frame_end)
	get_tree().physics_frame.disconnect(_on_tick)
	var seconds := _ticks / float(Engine.physics_ticks_per_second)
	var steps := _steps.duplicate()
	steps.sort()
	_works.sort()
	var total := 0.0
	for spent in steps:
		total += spent
	var mean := total / maxi(steps.size(), 1)
	return {
		"characters": count,
		"mode": mode,
		"calibration_ms": calibration,
		"frames": frames,
		"ticks": _ticks,
		"ticks_per_frame": float(_ticks) / frames,
		"step_mean_us": mean,
		"step_p95_us": steps[int(steps.size() * 0.95)] if not steps.is_empty() else -1.0,
		"us_each": mean / count,
		"work_ms": _works[_works.size() / 2] if not _works.is_empty() else -1.0,
		"routed_per_second": (_routed() - routed_before) / maxf(seconds, 0.001),
		"tasks": _tasks(),
		"full": _director.count_at(AiDirector.Tier.FULL),
		"engaged": float(_engaged) / maxi(_ticks, 1),
		"fight_cap": _director.fight_cap(),
		"holders_full": _holders_at_full(),
	}


# Slot holders at the Full tier now.
func _holders_at_full() -> int:
	var found := 0
	for character in _characters:
		if character.tier == AiDirector.Tier.FULL and _director.slots.holds(character):
			found += 1
	return found


func _routed() -> int:
	var total := 0
	for character in _characters:
		var brain := AiBrain.of(character)
		if brain != null:
			total += brain.routed
	return total


# How many guards run each task now (`idle` for none).
func _tasks() -> Dictionary:
	var kinds := {}
	for character in _characters:
		var tasks := character.task_runner as AiTasks
		var kind := String(tasks.runner.active_kind()) if tasks != null else ""
		if kind.is_empty():
			kind = "idle"
		kinds[kind] = kinds.get(kind, 0) + 1
	return kinds


func _on_tick() -> void:
	_tick += 1
	_move_targets()
	_ticks += 1
	_engaged += _director.slots.count()
	if _tick_start < 0:
		_tick_start = Time.get_ticks_usec()
	# The step of the tick before this one (the director runs inside the tick).
	if _director.tick > 0:
		_steps.append(float(_director.last_step_usec))


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
