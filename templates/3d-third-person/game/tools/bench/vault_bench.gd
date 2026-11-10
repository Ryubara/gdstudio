extends Node
## What vaulting adds to a character's physics tick: 1, 8 and 40 `player.tscn` running down lanes
## of 0.9 m walls that carry a `Vaultable`, stepped by commands (what a server or an AI pays),
## three ways: `off` (no `vault_settings`: the body as it was), `press` (jump pressed every half
## second, so a probe runs at each press and the body vaults when a wall is near) and `auto` (the
## automatic trigger with the sprint held, so a probe runs on every tick the body sprints and is
## not vaulting). `open_off` and `open_auto` run the other way, where there are no walls: what the
## automatic trigger's probe costs a sprinting body that never finds one. It also times one
## `VaultProbe.measure()` alone.
##
## Run it headless on the desktop:
## `godot --headless --fixed-fps 60 --path game res://tools/bench/vault_bench.tscn`
## and in a browser from a web export with this scene as `run/main_scene` (and `tools/*` taken out
## of the preset's exclude filter) through `tools/bench/player_step_bench.py`, which waits for the
## same page global. It prints one line of JSON that starts with `VAULT_BENCH`.

const COUNTS: Array[int] = [1, 8, 40]
const MODES: Array[String] = ["off", "press", "auto", "open_off", "open_auto"]
const WARM_TICKS := 60
const TICKS := 600
const PLAYER := "res://gameplay/player/player.tscn"
const SETTINGS := "res://gameplay/character/vault_settings.tres"
## The lanes: 2.5 m apart, walls across all of them every `WALL_EVERY` metres.
const LANE := 2.5
const WALL_EVERY := 7.0
const WALLS := 18
const PROBES := 2000

var _results: Array[Dictionary] = []


func _ready() -> void:
	_add_box(Vector3(0.0, -0.5, -60.0), Vector3(240.0, 1.0, 300.0), false)
	for row in WALLS:
		_add_box(Vector3(0.0, 0.45, -6.0 - row * WALL_EVERY), Vector3(240.0, 0.9, 0.3), true)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 30.0, 40.0)
	camera.rotation.x = deg_to_rad(-35.0)
	add_child(camera)
	camera.make_current()
	_run.call_deferred()


func _add_box(centre: Vector3, size: Vector3, vaultable: bool) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	if vaultable:
		body.add_child(Vaultable.new())
	add_child(body)


func _run() -> void:
	for count in COUNTS:
		for mode in MODES:
			var bodies := await _spawn(count, mode)
			var report := await _measure(bodies, mode)
			report["bodies"] = count
			report["mode"] = mode
			_results.append(report)
			_free(bodies)
			await get_tree().physics_frame
	var probe := await _probe_alone()
	# `has_step` is what the web runner of `player_step_bench` reads first.
	var line := JSON.stringify(
		{"has_step": true, "ticks": TICKS, "probe_us": probe, "results": _results}
	)
	print("VAULT_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__player_step_bench = %s;" % line, true)
	else:
		get_tree().quit()


func _spawn(count: int, mode: String) -> Array[Player]:
	var bodies: Array[Player] = []
	for index in count:
		var body := (load(PLAYER) as PackedScene).instantiate() as Player
		body.start_at_spawn = false
		body.position = Vector3((index - count / 2.0) * LANE, 0.0, 0.0)
		add_child(body)
		body.set_physics_process(false)
		if mode.ends_with("off"):
			body.vault_settings = null
		else:
			var settings := (load(SETTINGS) as VaultSettings).duplicate() as VaultSettings
			if mode.ends_with("auto"):
				settings.trigger = VaultSettings.Trigger.AUTO_ON_SPRINT
			body.vault_settings = settings
		bodies.append(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return bodies


func _free(bodies: Array[Player]) -> void:
	for body in bodies:
		body.queue_free()


# Microseconds one body's tick takes over `TICKS` ticks after a warm-up, and how many vaults the
# bodies made.
func _measure(bodies: Array[Player], mode: String) -> Dictionary:
	var delta := 1.0 / Engine.physics_ticks_per_second
	var command := PlayerCommand.new()
	var vaults := [0]
	for body in bodies:
		body.vault_motion.started.connect(func(_plan: VaultPlan) -> void: vaults[0] += 1)
	var spent := 0
	for tick in WARM_TICKS + TICKS:
		await get_tree().physics_frame
		var press := mode == "press" and tick % 30 == 0
		command.clear()
		# Forward is -Z, into the walls; the open runs go back along +Z.
		command.move = Vector2(0.0, -1.0 if mode.begins_with("open") else 1.0)
		command.sprint = mode.ends_with("auto") or mode == "open_off"
		command.jump = press
		command.jump_pressed = press
		var start := Time.get_ticks_usec()
		for body in bodies:
			body.step(command, delta)
		if tick >= WARM_TICKS:
			spent += Time.get_ticks_usec() - start
	return {"us_per_body_tick": float(spent) / (TICKS * bodies.size()), "vaults": vaults[0]}


# Microseconds one probe takes, a wall 1 m ahead (a vault found) and nothing ahead (refused).
func _probe_alone() -> Dictionary:
	var bodies := await _spawn(1, "press")
	var body := bodies[0]
	var settings := body.vault_settings
	var result := {}
	for case: String in ["vault", "nothing"]:
		var feet := Vector3(0.0, 0.0, -6.0 + 0.15 + 1.0) if case == "vault" else Vector3.ZERO
		var start := Time.get_ticks_usec()
		var found := ""
		for _index in PROBES:
			var plan := VaultProbe.measure(body, feet, Vector3.FORWARD, 0.34, 1.8, 4.0, settings)
			found = plan.refusal
		result[case] = float(Time.get_ticks_usec() - start) / PROBES
		result[case + "_refusal"] = found
	_free(bodies)
	return result
