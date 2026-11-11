extends Node
## What drawing ragdolls between physics ticks costs (`RagdollDrawing`, gdstudio #1126): four
## characters (the `max_active` cap) die in the air over a flat floor, round after round, and
## each frame every ragdoll's drawing is timed by hand (`RagdollDrawing.draw`, the work its
## modifier step does), with the once-a-tick check that turns it off while the body sleeps.
##
## One line of JSON: microseconds a ragdoll a frame (mean and the 95th percentile of the frames'
## sums divided by the ragdolls), microseconds a ragdoll a tick for the check, and how many frames
## and ragdolls. Run it headless on the desktop at a frame rate over the tick rate:
## `godot --headless --fixed-fps 144 --path game res://tools/bench/ragdoll_drawing_bench.tscn`
## and in a browser from a web export with this scene as `run/main_scene` and `tools/*` taken out
## of the preset's exclude filter (`tools/bench/ragdoll_drawing_bench.py`); there it puts the line
## in `window.__ragdoll_drawing_bench`.

const CHARACTER := "res://gameplay/character/character_dressed.tscn"
const RAGDOLLS := 4
const ROUNDS := 5
## Frames timed a round: the fall from 3 m, the landing and the first roll.
const ROUND_FRAMES := 150
const DROP_HEIGHT := 3.0

var _bodies: Array[Character] = []
var _frame_sums: Array[float] = []
var _tick_us := 0.0
var _ticks := 0
var _timing := false


class Still:
	extends CharacterController

	func sample() -> PlayerCommand:
		_command.clear()
		return _command


func _ready() -> void:
	process_priority = 1 << 30
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.0, 10.0)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	var scene := load(CHARACTER) as PackedScene
	for index in RAGDOLLS:
		var body := scene.instantiate() as Character
		var still := Still.new()
		body.add_child(still)
		body.controller = still
		body.position = Vector3(index * 2.5 - 4.0, 0.0, 0.0)
		add_child(body)
		_bodies.append(body)
	_run.call_deferred()


func _run() -> void:
	for _i in 60:
		await get_tree().process_frame
	for round_index in ROUNDS:
		for body in _bodies:
			body.teleport(Vector3(body.position.x, DROP_HEIGHT, float(round_index)))
		await get_tree().physics_frame
		for body in _bodies:
			body.die()
		await get_tree().physics_frame
		_timing = true
		for _i in ROUND_FRAMES:
			await get_tree().process_frame
		_timing = false
	_report()


func _physics_process(_delta: float) -> void:
	if not _timing:
		return
	for body in _bodies:
		var drawing := _drawing(body)
		if drawing == null:
			continue
		var start := Time.get_ticks_usec()
		drawing._physics_process(0.0)
		_tick_us += Time.get_ticks_usec() - start
		_ticks += 1


func _process(_delta: float) -> void:
	if not _timing:
		return
	var total := 0
	for body in _bodies:
		var drawing := _drawing(body)
		if drawing == null or not drawing.active:
			continue
		var skeleton := body.model.skeleton()
		var start := Time.get_ticks_usec()
		drawing.draw(skeleton, 1.0)
		total += Time.get_ticks_usec() - start
	_frame_sums.append(total / float(RAGDOLLS))


static func _drawing(body: Character) -> RagdollDrawing:
	var skeleton := body.model.skeleton()
	return skeleton.get_node_or_null(NodePath(RagdollDrawing.NODE_NAME)) as RagdollDrawing


func _report() -> void:
	var sorted := _frame_sums.duplicate()
	sorted.sort()
	var mean := 0.0
	for value in _frame_sums:
		mean += value
	mean /= maxf(_frame_sums.size(), 1.0)
	var result := {
		"ragdolls": RAGDOLLS,
		"frames": _frame_sums.size(),
		"draw_us_mean": mean,
		"draw_us_p95": sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0,
		"check_us_tick": _tick_us / maxf(_ticks, 1.0),
	}
	var line := JSON.stringify(result)
	print(line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ragdoll_drawing_bench = %s;" % line, true)
	get_tree().quit()
