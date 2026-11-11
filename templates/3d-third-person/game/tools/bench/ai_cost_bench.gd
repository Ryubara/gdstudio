extends Node
## What AI characters cost (gdstudio #963): the `AiDirector`'s step (tiers, thinks and the bodies'
## steps, what the AI budget of `docs/engines/godot/crowds.md#ai-characters` holds) and the whole
## frame's work beside it (animation, footsteps and the physics step too), for a crowd of
## `ai_character.tscn` standing and walking around a stand-in for the player.
##
## The characters stand on a grid 3 m apart around the player, all nearer than the Full range, so
## the director's Full cap decides the tiers (20 at Full in a browser, 60 on the desktop; the rest
## Reduced, stepped every 3rd tick). Walking, each turns its way a little every half second.
##
## One line of JSON, `AI_COST_BENCH {...}`: for each count and mode the director's step per tick
## (`step_mean_us`, `step_p95_us`, `us_each`), the median frame work in milliseconds (from the
## frame's first physics tick to its last node processed, as `parts_cost_bench.gd` reads it) and
## the count at each tier. Desktop:
## `godot --headless --fixed-fps 60 --path game res://tools/bench/ai_cost_bench.tscn`; browser: a
## web export with this scene as `run/main_scene` and `tools/*` out of the exclude filter, read by
## `tools/bench/ai_cost_bench.py` (`window.__ai_cost_bench`).

const COUNTS: Array[int] = [1, 20, 40, 120]
const WARM_FRAMES := 60
const FRAMES := 300
const CHARACTER := "res://gameplay/ai/ai_character.tscn"
const SPACING := 3.0
const TURN_EVERY := 30
## The walk: a share of the run, about a person's walking pace.
const WALK_STRENGTH := 0.35

var _arena: Node3D
var _director: AiDirector
var _characters: Array[AiCharacter] = []
var _frame_end: FrameEnd
var _works: Array[float] = []
var _steps: Array[float] = []
var _tick_start := -1
var _rng := RandomNumberGenerator.new()


## Processed after every other node: says when a frame's processing is over.
class FrameEnd:
	extends Node
	signal done

	func _init() -> void:
		process_priority = 1 << 30

	func _process(_delta: float) -> void:
		done.emit()


func _ready() -> void:
	_rng.seed = 963
	_frame_end = FrameEnd.new()
	add_child(_frame_end)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var viewer := Node3D.new()
	viewer.add_to_group(&"player")
	add_child(viewer)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 30.0, 40.0)
	camera.rotation.x = deg_to_rad(-35.0)
	add_child(camera)
	camera.make_current()
	_run.call_deferred()


func _run() -> void:
	var report := {"frames": FRAMES, "web": OS.has_feature("web"), "rows": []}
	for count in COUNTS:
		_new_crowd(count)
		report.rows.append(await _measure(count, false))
		_walk(true)
		report.rows.append(await _measure(count, true))
		_arena.free()
	var line := JSON.stringify(report)
	print("AI_COST_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ai_cost_bench = %s;" % line, true)
	else:
		get_tree().quit()


func _new_crowd(count: int) -> void:
	_arena = Node3D.new()
	add_child(_arena)
	_director = AiDirector.new()
	_director.web_cap = COUNTS.max()
	_director.desktop_cap = COUNTS.max()
	_arena.add_child(_director)
	_characters.clear()
	var side := ceili(sqrt(count))
	var scene := load(CHARACTER) as PackedScene
	for index in count:
		var character := scene.instantiate() as AiCharacter
		var cell := (
			Vector2(index % side, floorf(float(index) / side)) - Vector2.ONE * (side - 1) / 2.0
		)
		character.position = Vector3(cell.x * SPACING, 0.0, cell.y * SPACING + 2.0)
		_arena.add_child(character)
		_characters.append(character)


func _walk(on: bool) -> void:
	for character in _characters:
		var angle := _rng.randf() * TAU
		character.ai_controller().walk_direction = (
			Vector3(cos(angle), 0.0, sin(angle)) if on else Vector3.ZERO
		)
		character.ai_controller().walk_strength = WALK_STRENGTH


func _measure(count: int, walking: bool) -> Dictionary:
	for _i in WARM_FRAMES:
		await get_tree().process_frame
	_works.clear()
	_steps.clear()
	_tick_start = -1
	get_tree().physics_frame.connect(_on_physics_frame)
	_frame_end.done.connect(_on_frame_end)
	for frame in FRAMES:
		await get_tree().process_frame
		if walking and frame % TURN_EVERY == 0:
			_turn_a_little()
	get_tree().physics_frame.disconnect(_on_physics_frame)
	_frame_end.done.disconnect(_on_frame_end)
	var steps := _steps.duplicate()
	steps.sort()
	_works.sort()
	var total := 0.0
	for spent in steps:
		total += spent
	var mean := total / maxi(steps.size(), 1)
	return {
		"characters": count,
		"walking": walking,
		"step_mean_us": mean,
		"step_p95_us": steps[int(steps.size() * 0.95)] if not steps.is_empty() else -1.0,
		"us_each": mean / count,
		"work_ms": _works[_works.size() / 2] if not _works.is_empty() else -1.0,
		"full": _director.count_at(AiDirector.Tier.FULL),
		"reduced": _director.count_at(AiDirector.Tier.REDUCED),
		"dormant": _director.count_at(AiDirector.Tier.DORMANT),
	}


# Each walker turns up to 40 degrees, and back toward the middle once it is far out.
func _turn_a_little() -> void:
	for character in _characters:
		var controller := character.ai_controller()
		var way := controller.walk_direction.rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
		if character.global_position.length() > 25.0:
			way = -character.global_position.normalized()
			way.y = 0.0
		controller.walk_direction = way


func _on_physics_frame() -> void:
	if _tick_start < 0:
		_tick_start = Time.get_ticks_usec()
	# The step of the tick before this one (the director runs inside the tick).
	if _director != null and _director.tick > 0:
		_steps.append(float(_director.last_step_usec))


func _on_frame_end() -> void:
	if _tick_start >= 0:
		_works.append((Time.get_ticks_usec() - _tick_start) / 1000.0)
	_tick_start = -1
