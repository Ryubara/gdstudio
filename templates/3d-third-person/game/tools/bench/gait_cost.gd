## Measures what the gait fitting costs (gdstudio #1158): dressed players walk, blend into a jog,
## sprint and stop over and over (each a little out of step with the next, so the body states
## change on different frames), stepped by commands, with the tree's `GaitSettings` in one of the
## runs named by the first user argument (or `?run=` in the web build's address): `off` (no speed
## matching, no momentum blend, no transitions: the tree as it was before), `on` (the template's
## settings) or `lean_off` (the template's settings with only the lean off, gdstudio #1403: the
## lean's cost is `on` less `lean_off`). The second (or `?players=`) is how many (1, 10, 40). A
## frame's work is the span from the first node's `_process` to the end of the deferred calls
## after the last one (the skeletons run their modifiers there, the momentum blend among them). It
## prints the mean and the median on a line starting `BENCH` and, in a browser, puts them in
## `window.__gait_cost`; the fitting's cost for one character is `on`'s mean less `off`'s, over
## the players.
##
## `<godot> --headless --path game res://tools/bench/gait_cost.tscn -- on 40`; in Chrome,
## `gds template bench-web 3d-third-person gait_cost --run` (`gait_cost.py` reads every run). One
## run a process. It lives in tools/, which the game's export leaves out.
extends Node3D

const WARM_FRAMES := 120
const MEASURED_FRAMES := 900
## The moves each player cycles through: seconds, push forward, walk button, sprint button.
const MOVES: Array[Array] = [
	[0.8, 1.0, true, false],
	[0.8, 0.65, false, false],
	[0.8, 1.0, false, true],
	[0.7, 0.0, false, false],
]
const CYCLE := 3.1

var _players: Array[Player] = []
var _commands: Array[PlayerCommand] = []
var _frame_start := 0
var _works := PackedFloat64Array()
var _measuring := false
var _time := 0.0


func _ready() -> void:
	process_priority = -(1 << 30)
	_bench.call_deferred()


func _process(_delta: float) -> void:
	if _measuring:
		_frame_start = Time.get_ticks_usec()


func _physics_process(delta: float) -> void:
	_time += delta
	for index in _players.size():
		var command := _commands[index]
		var at := fmod(_time + index * 0.37, CYCLE)
		for move in MOVES:
			if at < move[0]:
				command.move = Vector2(0.0, move[1])
				command.walk = move[2]
				command.sprint = move[3]
				break
			at -= move[0]
		# Back and forth on the floor: the yaw turns half round each cycle.
		command.yaw = PI * floorf((_time + index * 0.37) / CYCLE)
		_players[index].step(command, delta)


func _bench() -> void:
	var run_name := _argument(0, "run", "on")
	var count := int(_argument(1, "players", "40"))
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, 6.0, 18.0)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	camera.make_current()
	var settings := (
		(load("res://gameplay/character/gait_settings.tres") as GaitSettings).duplicate()
	)
	if run_name == "off":
		settings.speed_match = false
		settings.momentum_blend = false
		settings.transitions = false
	elif run_name == "lean_off":
		settings.lean = false
	var scene := load("res://gameplay/player/player.tscn") as PackedScene
	for index in count:
		var player := scene.instantiate() as Player
		player.start_at_spawn = false
		player.position = Vector3(index % 8 - 3.5, 0.0, floorf(index / 8.0) - 2.0) * 2.5
		add_child(player)
		if player.controller != null:
			player.controller.queue_free()
			player.controller = null
		player.set_physics_process(false)
		(player.get_node("Animation") as CharacterAnimation).gait_settings = settings
		_players.append(player)
		_commands.append(PlayerCommand.new())
	var last := FrameEnd.new()
	last.process_priority = 1 << 30
	last.bench = self
	add_child(last)
	for _frame in WARM_FRAMES:
		await get_tree().process_frame
	_measuring = true
	while _works.size() < MEASURED_FRAMES:
		await get_tree().process_frame
	_measuring = false
	var sorted := _works.duplicate()
	sorted.sort()
	var total := 0.0
	for work in _works:
		total += work
	var result := {
		"run": run_name,
		"characters": count,
		"frames": _works.size(),
		"mean_ms": total / _works.size(),
		"median_ms": sorted[sorted.size() / 2],
	}
	print(
		(
			"BENCH %s: %d characters, work %.3f ms a frame (median %.3f)"
			% [run_name, count, result.mean_ms, result.median_ms]
		)
	)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__gait_cost = %s;" % JSON.stringify(result), true)
		return
	get_tree().quit()


## Ends the frame's span: called deferred from the last node's `_process`.
func end_frame() -> void:
	if _measuring and _frame_start > 0:
		_works.append((Time.get_ticks_usec() - _frame_start) / 1000.0)


# The user argument at `index`, or in the web build the address's `key=`; `fallback` when absent.
func _argument(index: int, key: String, fallback: String) -> String:
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true))
		for pair in query.trim_prefix("?").split("&"):
			if pair.begins_with(key + "="):
				return pair.trim_prefix(key + "=")
		return fallback
	var arguments := OS.get_cmdline_user_args()
	return arguments[index] if arguments.size() > index else fallback


# The node that processes last and closes the frame's span after the deferred calls.
class FrameEnd:
	extends Node

	var bench: Node

	func _process(_delta: float) -> void:
		if bench != null:
			bench.call_deferred(&"end_frame")
