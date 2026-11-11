extends Node
## What one physics tick of a character's body costs: 1, 8 and 40 `player.tscn` on a flat floor,
## each walking a circle with sprint, a jump now and then and a crouch, stepped by hand so that
## only the body's own tick is timed (not the animation, the camera or the physics server's step).
##
## Two ways, when the body has them: `input` calls the body's `_physics_process` (its controller
## reads the actions and the camera, then the body steps), `commands` calls `step()` with a
## command made here (what a server or an AI pays). A build from before the command step has only
## the first, and the bench says so. `prone` is `commands` with the body lying down and crawling
## most of the time and getting up every five seconds (gdstudio #1012); a build without prone
## leaves it out.
##
## Run it headless on the desktop: `godot --headless --fixed-fps 60 --path game
## res://tools/bench/player_step_bench.tscn` and in a browser from the web export `gds template
## bench-web 3d-third-person player_step_bench` makes (kit
## docs/engines/godot/web-probes.md#bench-web) (`tools/bench/player_step_bench.py`). It prints one
## line of JSON that starts with `PLAYER_STEP_BENCH` and, on the web, puts it in
## `window.__player_step_bench`.

const COUNTS: Array[int] = [1, 8, 40]
const WARM_TICKS := 60
const TICKS := 600
const PLAYER := "res://gameplay/player/player.tscn"

var _results: Array[Dictionary] = []


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 30.0, 40.0)
	camera.rotation.x = deg_to_rad(-35.0)
	add_child(camera)
	camera.make_current()
	_run.call_deferred()


func _run() -> void:
	var has_step := false
	for count in COUNTS:
		for mode: String in ["input", "commands", "prone"]:
			var bodies := await _spawn(count)
			has_step = bodies[0].has_method(&"step")
			var has_prone := &"prone_tuning" in bodies[0]
			if mode != "input" and not has_step or mode == "prone" and not has_prone:
				_free(bodies)
				continue
			var micros := await _measure(bodies, mode)
			_results.append({"bodies": count, "mode": mode, "us_per_body_tick": micros})
			_free(bodies)
			await get_tree().physics_frame
	for action: StringName in [&"move_forward", &"sprint", &"jump", &"crouch"]:
		Input.action_release(action)
	var line := JSON.stringify({"has_step": has_step, "ticks": TICKS, "results": _results})
	print("PLAYER_STEP_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__player_step_bench = %s;" % line, true)
	else:
		get_tree().quit()


func _spawn(count: int) -> Array[CharacterBody3D]:
	var bodies: Array[CharacterBody3D] = []
	for index in count:
		var body := (load(PLAYER) as PackedScene).instantiate() as CharacterBody3D
		body.set(&"start_at_spawn", false)
		body.position = Vector3((index % 8) * 4.0 - 14.0, 0.0, floorf(index / 8.0) * 4.0 - 8.0)
		add_child(body)
		body.set_physics_process(false)
		bodies.append(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return bodies


func _free(bodies: Array[CharacterBody3D]) -> void:
	for body in bodies:
		body.queue_free()


# Microseconds one body's tick takes, over `TICKS` ticks after a warm-up.
func _measure(bodies: Array[CharacterBody3D], mode: String) -> float:
	var delta := 1.0 / Engine.physics_ticks_per_second
	var command: RefCounted = null
	if mode != "input":
		command = (load("res://gameplay/player/player_command.gd") as GDScript).new()
	var spent := 0
	for tick in WARM_TICKS + TICKS:
		await get_tree().physics_frame
		var jump := tick % 90 == 10
		var crouch := tick % 240 > 200
		var sprint := tick % 120 > 60
		if command != null:
			command.call(&"clear")
			command.set(&"yaw", tick * 0.01)
			command.set(&"move", Vector2(0.0, 1.0))
			command.set(&"sprint", sprint)
			command.set(&"crouch", crouch)
			command.set(&"jump", jump)
			command.set(&"jump_pressed", jump)
			if mode == "prone":
				command.set(&"prone", tick % 300 < 240)
				command.set(&"sprint", false)
		else:
			_hold(&"move_forward", true)
			_hold(&"sprint", sprint)
			_hold(&"crouch", crouch)
			_hold(&"jump", jump)
		var start := Time.get_ticks_usec()
		if command != null:
			for body in bodies:
				body.call(&"step", command, delta)
		else:
			for body in bodies:
				body._physics_process(delta)
		if tick >= WARM_TICKS:
			spent += Time.get_ticks_usec() - start
	return float(spent) / (TICKS * bodies.size())


func _hold(action: StringName, down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)
