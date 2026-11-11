extends Node
## What the AI senses cost (gdstudio #966), in two parts:
##
## - **Thinks.** N `ai_character.tscn` (bodies not stepped: only the senses are timed) on a 120 m
##   map with 16 boxes, 4 hostile targets walking circles among them, each character facing its
##   own seeded way; every physics tick a sixth of them sense (10 Hz at 60 Hz, as the director
##   spreads them) with a shared `AiBudget` of 8 rays a tick, and a target shoots every half
##   second (hearing). Per think: mean, p50 and p99 in microseconds; per tick: the senses'
##   total; rays and thinks a second.
## - **Crowd.** 40 walking characters with the director, as `ai_cost_bench.gd` runs them, with
##   the senses on and off: the director's step a tick (the thinks run inside it) and the
##   median frame work, so the pull request says what the senses add to the crowd.
##
## One line of JSON, `AI_SENSES_BENCH {...}`. Desktop:
## `godot --headless --fixed-fps 60 --path game res://tools/bench/ai_senses_bench.tscn`; browser:
## a web export with this scene as `run/main_scene` and `tools/*` out of the exclude filter, read
## by `tools/bench/ai_senses_bench.py` (`window.__ai_senses_bench`).

const THINK_COUNTS: Array[int] = [40, 200]
const CROWD := 40
const WARM_FRAMES := 60
const FRAMES := 300
const CHARACTER := "res://gameplay/ai/ai_character.tscn"
const RELATIONS := "res://gameplay/ai/relations/ai_relations.tres"
const MAP := 120.0
const BOXES := 16
const TARGETS := 4
const THINK_EVERY := 6
const RAYS_PER_TICK := 8
const SHOT_EVERY := 30
const WALK_STRENGTH := 0.35
const TURN_EVERY := 30

var _arena: Node3D
var _rng := RandomNumberGenerator.new()
var _characters: Array[AiCharacter] = []
var _targets: Array[Node3D] = []
var _budget := AiBudget.new()
var _think_usec: Array[float] = []
var _tick_usec: Array[float] = []
var _rays := 0
var _thinks := 0
var _tick := 0
var _thinking := false
var _director: AiDirector
var _frame_end: FrameEnd
var _works: Array[float] = []
var _steps: Array[float] = []
var _tick_start := -1
var _senses_usec: Array[float] = []
var _thinks_seen := PackedInt32Array()


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
	camera.position = Vector3(0.0, 60.0, 70.0)
	camera.rotation.x = deg_to_rad(-40.0)
	add_child(camera)
	camera.make_current()
	_run.call_deferred()


func _run() -> void:
	var report := {"frames": FRAMES, "web": OS.has_feature("web"), "thinks": [], "crowd": []}
	for count in THINK_COUNTS:
		report.thinks.append(await _measure_thinks(count))
	for senses_on in [false, true]:
		report.crowd.append(await _measure_crowd(senses_on))
	var line := JSON.stringify(report)
	print("AI_SENSES_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ai_senses_bench = %s;" % line, true)
	else:
		get_tree().quit()


# A floor, 16 seeded boxes, the relationships, the noise board and the targets.
func _new_map(seed_value: int) -> void:
	_rng.seed = seed_value
	_arena = Node3D.new()
	add_child(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(MAP, 1.0, MAP))
	for _index in BOXES:
		var spot := Vector3(_rng.randf_range(-40.0, 40.0), 1.5, _rng.randf_range(-40.0, 40.0))
		_add_box(spot, Vector3(_rng.randf_range(2.0, 6.0), 3.0, _rng.randf_range(2.0, 6.0)))
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
		member.faction = &"player"
		target.add_child(member)
		_arena.add_child(target)
		_targets.append(target)


func _add_box(spot: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = spot
	_arena.add_child(body)


func _add_characters(count: int, spread: float) -> void:
	_characters.clear()
	var scene := load(CHARACTER) as PackedScene
	for index in count:
		var character := scene.instantiate() as AiCharacter
		character.name = "Ai%d" % index
		character.position = Vector3(
			_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread)
		)
		character.rotation.y = 0.0
		_arena.add_child(character)
		character.facing = _rng.randf() * TAU
		_characters.append(character)


func _move_targets() -> void:
	for index in _targets.size():
		var angle := _tick * 0.01 + index * TAU / _targets.size()
		_targets[index].position = Vector3(cos(angle) * 18.0, 0.0, sin(angle) * 18.0)
	if _tick % SHOT_EVERY == 0:
		var shooter := _targets[(_tick / SHOT_EVERY) % _targets.size()]
		AiNoise.emit(self, AiNoise.SHOT, shooter.position, 1.0, shooter)


func _measure_thinks(count: int) -> Dictionary:
	_new_map(966)
	_add_characters(count, 45.0)
	for character in _characters:
		character.set_physics_process(false)
		character.budget = _budget
	_budget.rays_per_tick = RAYS_PER_TICK
	_think_usec.clear()
	_tick_usec.clear()
	_rays = 0
	_thinks = 0
	_tick = 0
	for _i in WARM_FRAMES:
		await get_tree().physics_frame
	_thinking = true
	get_tree().physics_frame.connect(_on_think_tick)
	for _frame in FRAMES:
		await get_tree().physics_frame
	get_tree().physics_frame.disconnect(_on_think_tick)
	_thinking = false
	var seconds := FRAMES / float(Engine.physics_ticks_per_second)
	var thinks := _think_usec.duplicate()
	thinks.sort()
	var ticks := _tick_usec.duplicate()
	ticks.sort()
	var row := {
		"characters": count,
		"targets": TARGETS,
		"think_mean_us": _mean(thinks),
		"think_p50_us": _at(thinks, 0.5),
		"think_p99_us": _at(thinks, 0.99),
		"tick_mean_us": _mean(ticks),
		"tick_p99_us": _at(ticks, 0.99),
		"thinks_per_second": _thinks / seconds,
		"rays_per_second": _rays / seconds,
		"believed": _believed(),
	}
	_arena.free()
	return row


func _on_think_tick() -> void:
	_tick += 1
	_move_targets()
	_budget.reset()
	var tick_start := Time.get_ticks_usec()
	for index in range(_tick % THINK_EVERY, _characters.size(), THINK_EVERY):
		var senses := _characters[index].senses as AiSenses
		var rays_before := senses.rays_cast
		var start := Time.get_ticks_usec()
		senses.sense(THINK_EVERY / float(Engine.physics_ticks_per_second))
		_think_usec.append(float(Time.get_ticks_usec() - start))
		_rays += senses.rays_cast - rays_before
		_thinks += 1
	_tick_usec.append(float(Time.get_ticks_usec() - tick_start))


func _believed() -> int:
	var found := 0
	for character in _characters:
		for target in _targets:
			if (character.senses as AiSenses).beliefs.believes(target):
				found += 1
	return found


func _measure_crowd(senses_on: bool) -> Dictionary:
	_new_map(963)
	_director = AiDirector.new()
	_director.web_cap = CROWD
	_director.desktop_cap = CROWD
	_arena.add_child(_director)
	_add_characters(CROWD, 9.0)
	for character in _characters:
		if not senses_on:
			character.senses = null
		var angle := _rng.randf() * TAU
		character.ai_controller().walk_direction = Vector3(cos(angle), 0.0, sin(angle))
		character.ai_controller().walk_strength = WALK_STRENGTH
	_tick = 0
	for _i in WARM_FRAMES:
		await get_tree().process_frame
	_works.clear()
	_steps.clear()
	_tick_start = -1
	_rays = 0
	_senses_usec.clear()
	_thinks_seen.resize(_characters.size())
	_thinks_seen.fill(0)
	get_tree().physics_frame.connect(_on_crowd_tick)
	_frame_end.done.connect(_on_frame_end)
	for frame in FRAMES:
		await get_tree().process_frame
		if frame % TURN_EVERY == 0:
			for character in _characters:
				var walk := character.ai_controller().walk_direction
				character.ai_controller().walk_direction = walk.rotated(Vector3.UP, 0.4)
	get_tree().physics_frame.disconnect(_on_crowd_tick)
	_frame_end.done.disconnect(_on_frame_end)
	var steps := _steps.duplicate()
	steps.sort()
	_works.sort()
	var row := {
		"characters": CROWD,
		"senses": senses_on,
		"step_mean_us": _mean(steps),
		"step_p95_us": _at(steps, 0.95),
		"work_ms": _at(_works, 0.5),
		"senses_mean_us": _mean(_senses_usec),
		"rays_per_second": _rays / (FRAMES / float(Engine.physics_ticks_per_second)),
		"believed": _believed() if senses_on else 0,
	}
	_arena.free()
	return row


func _on_crowd_tick() -> void:
	_tick += 1
	_move_targets()
	if _tick_start < 0:
		_tick_start = Time.get_ticks_usec()
	_steps.append(float(_director.last_step_usec))
	_rays += _director.budget.rays
	var spent := 0.0
	for index in _characters.size():
		var senses := _characters[index].senses as AiSenses
		if senses != null and senses.thinks != _thinks_seen[index]:
			_thinks_seen[index] = senses.thinks
			spent += senses.last_sense_usec
	_senses_usec.append(spent)


func _on_frame_end() -> void:
	if _tick_start >= 0:
		_works.append((Time.get_ticks_usec() - _tick_start) / 1000.0)
	_tick_start = -1


static func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxi(values.size(), 1)


static func _at(sorted: Array[float], share: float) -> float:
	if sorted.is_empty():
		return -1.0
	return sorted[mini(int(sorted.size() * share), sorted.size() - 1)]
