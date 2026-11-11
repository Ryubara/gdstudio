extends Node
## What a puppet (another player online, `RemotePlayers`) costs a frame, and which part of it:
## seven puppets made as `RemotePlayers` makes them (`player.tscn`, `Player.make_puppet()`), each
## walking a small circle placed by `Player.puppet_to()` every physics tick, as a TICK would.
##
## Each variant is a camera and a mode, measured over `FRAMES` frames after `WARM_FRAMES`, in
## `ROUNDS` interleaved rounds (a busy machine moves every variant alike):
##
## - cameras: `near` (the puppets 6 to 10 m in front of it, all in view), `far` (40 m), `away`
##   (near, turned round: none in view);
## - modes: `none` (the puppets off: hidden and not processed), `full` (every puppet animates every
##   frame, as before #1138), `frozen` (no tree advances: what is left is placing and drawing a
##   still skinned body), `hidden` (the trees run, the models are hidden: the animation's CPU
##   work without the skinning and the drawing), `half` (every tree advanced every second frame),
##   `throttle` (the online game's `CharacterAnimationThrottle` with its defaults).
##
## A row is the mean frame (`frame_ms`, wall clock between two process frames) and its 95th
## percentile. Run it headless on the desktop:
## `godot --headless --path game res://tools/bench/puppet_bench.tscn`
## and in a browser from a web export with this scene as `run/main_scene` and `tools/*` taken out
## of the preset's exclude filter (`tools/bench/puppet_bench.py`). It prints one line of JSON that
## starts with `PUPPET_BENCH` and, on the web, puts it in `window.__puppet_bench`.

const PLAYER := "res://gameplay/player/player.tscn"
const PUPPETS := 7
const ROUNDS := 3
const FRAMES := 240
const WARM_FRAMES := 40
## Metres of each puppet's circle, and its walking speed.
const CIRCLE := 1.5
const SPEED := 2.0
const VARIANTS: Array[Array] = [
	["near", "none"],
	["near", "full"],
	["near", "frozen"],
	["near", "hidden"],
	["near", "half"],
	["near", "throttle"],
	["far", "full"],
	["far", "throttle"],
	["away", "full"],
	["away", "throttle"],
]

var _camera: Camera3D
var _throttle: CharacterAnimationThrottle
var _puppets: Array[Player] = []
var _entry := PlayerEntry.new()
var _time := 0.0
var _mode := ""
var _frame := 0
var _last_us := 0
var _samples := PackedInt32Array()


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	add_child(sun)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()
	_throttle = CharacterAnimationThrottle.new()
	_throttle.camera = _camera
	add_child(_throttle)
	for index in PUPPETS:
		var puppet := (load(PLAYER) as PackedScene).instantiate() as Player
		puppet.make_puppet()
		add_child(puppet)
		_entry.position = _spot(index, 0.0)
		PlayerPuppet.warp(puppet, _entry)
		_puppets.append(puppet)
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	_time += delta
	for index in _puppets.size():
		var puppet := _puppets[index]
		if puppet.process_mode == PROCESS_MODE_DISABLED:
			continue
		var at := _spot(index, _time)
		var moving := (at - _spot(index, _time - delta)) / delta
		_entry.position = at
		_entry.yaw = atan2(-moving.x, -moving.z)
		_entry.state = Character.State.WALK
		puppet.puppet_to(_entry, moving, delta)


func _process(delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_samples.append(now - _last_us)
	_last_us = now
	if _mode == "half" and _frame % 2 == 0:
		for puppet in _puppets:
			_animation(puppet).advance(delta * 2.0)


func _run() -> void:
	var rows: Dictionary[String, Array] = {}
	for round_index in ROUNDS:
		for variant in VARIANTS:
			var key := "%s/%s" % [variant[0], variant[1]]
			_set_variant(variant[0], variant[1])
			for _i in WARM_FRAMES:
				await get_tree().process_frame
			_samples.clear()
			_last_us = 0
			for _i in FRAMES:
				await get_tree().process_frame
			if not rows.has(key):
				rows[key] = []
			rows[key].append(_summary(_samples))
	var results: Array[Dictionary] = []
	for key in rows:
		var means: Array[float] = []
		var p95s: Array[float] = []
		for row: Dictionary in rows[key]:
			means.append(row.mean)
			p95s.append(row.p95)
		means.sort()
		p95s.sort()
		(
			results
			. append(
				{
					"variant": key,
					"frame_ms": means[means.size() / 2],
					"frame_ms_runs": means,
					"p95_ms": p95s[p95s.size() / 2],
				}
			)
		)
	var line := JSON.stringify({"puppets": PUPPETS, "results": results})
	print("PUPPET_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__puppet_bench = %s;" % line, true)
	else:
		get_tree().quit()


func _set_variant(camera_at: String, mode: String) -> void:
	match camera_at:
		"near":
			_camera.position = Vector3(0.0, 2.2, 8.0)
			_camera.rotation = Vector3(deg_to_rad(-10.0), 0.0, 0.0)
		"far":
			_camera.position = Vector3(0.0, 6.0, 40.0)
			_camera.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0)
		"away":
			_camera.position = Vector3(0.0, 2.2, 8.0)
			_camera.rotation = Vector3(deg_to_rad(-10.0), PI, 0.0)
	_mode = mode
	_throttle.enabled = false
	for puppet in _puppets:
		_throttle.remove(puppet)
		var animation := _animation(puppet)
		animation.set_throttled(mode in ["frozen", "half"])
		puppet.model.visible = mode not in ["hidden", "none"]
		puppet.process_mode = PROCESS_MODE_DISABLED if mode == "none" else PROCESS_MODE_INHERIT
	if mode == "throttle":
		_throttle.enabled = true
		for puppet in _puppets:
			_throttle.add(puppet)


# Where puppet `index` is at `time`: on its own circle, the seven in a row across the view.
func _spot(index: int, time: float) -> Vector3:
	var centre := Vector3((index - (PUPPETS - 1) * 0.5) * 1.6, 0.0, -float(index % 3) * 2.0)
	var angle := time * SPEED / CIRCLE + index
	return centre + Vector3(cos(angle), 0.0, sin(angle)) * CIRCLE


static func _animation(puppet: Player) -> CharacterAnimation:
	return puppet.get_node("Animation") as CharacterAnimation


static func _summary(samples: PackedInt32Array) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += value
	var count := maxi(sorted.size(), 1)
	return {
		"mean": snappedf(float(total) / count / 1000.0, 0.001),
		"p95": snappedf(sorted[mini(int(count * 0.95), count - 1)] / 1000.0, 0.001),
	}
