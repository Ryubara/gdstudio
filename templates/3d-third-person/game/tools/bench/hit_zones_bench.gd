extends Node
## What the hit zones and the flinch cost: 1, 4 and 10 `character_dressed.tscn` standing in their
## idle clip on a flat floor.
##
## `shot_us`: one shot's second test (`HitZones.shot()` on the capsule: the zones put on the
## bones, then a ray against them), the mean of 300 shots at the chests in turn. `follow_us`: one
## `follow_bones()`, what the zones would cost a character every tick if they followed the
## skeleton all the time (they do not: they move only for a shot). `physics_ms`: the mean time
## from the tree's `physics_frame` to its next `process_frame` (the nodes' physics callbacks and
## the physics server's step, never the wait for the next frame, so it works on the web too) over
## 300 ticks with every character standing, and `flinch_ms` the same with every character
## flinching again each time its flinch ends (a chest hit, health off). `walking_ms` is the same
## with every character moved on each tick (its capsule and its shot hull with it), and
## `walking_no_hull_ms` with the shot hulls taken out of the world, so the difference is what the
## hulls cost (gdstudio #1431). `catch_up_us`: one throttled tree moved on by a tenth of a second,
## what a shot at a character whose pose is held pays first (`HitZones.posing`).
##
## Run it headless on the desktop: `godot --headless --fixed-fps 60 --path game
## res://tools/bench/hit_zones_bench.tscn` and in a browser from the web export `gds template
## bench-web 3d-third-person hit_zones_bench` makes (kit docs/engines/godot/web-probes.md#bench-web)
## (`tools/bench/hit_zones_bench.py`). It prints one line of JSON that starts with `HIT_ZONES_BENCH`
## and, on the web, puts it in `window.__hit_zones_bench`.

const COUNTS: Array[int] = [1, 4, 10]
const DRESSED := "res://gameplay/character/character_dressed.tscn"
const SHOTS := 300
const TICKS := 300
const WARM_TICKS := 60

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
	camera.position = Vector3(0.0, 4.0, 14.0)
	camera.rotation.x = deg_to_rad(-12.0)
	add_child(camera)
	camera.make_current()
	_run.call_deferred()


func _run() -> void:
	for count in COUNTS:
		var bodies := await _spawn(count)
		var row := {"characters": count}
		row["shot_us"] = _shot_cost(bodies)
		row["follow_us"] = _follow_cost(bodies)
		row["physics_ms"] = await _physics_ms(bodies, false)
		row["flinch_ms"] = await _physics_ms(bodies, true)
		row["walking_ms"] = await _walking_ms(bodies)
		_hulls_on(bodies, false)
		row["walking_no_hull_ms"] = await _walking_ms(bodies)
		_hulls_on(bodies, true)
		row["catch_up_us"] = _catch_up_cost(bodies)
		_results.append(row)
		for body in bodies:
			body.queue_free()
		await get_tree().physics_frame
	var line := JSON.stringify({"results": _results})
	print("HIT_ZONES_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__hit_zones_bench = %s;" % line, true)
	else:
		get_tree().quit()


func _spawn(count: int) -> Array[Character]:
	var bodies: Array[Character] = []
	for index in count:
		var body := (load(DRESSED) as PackedScene).instantiate() as Character
		body.position = Vector3((index % 5) * 2.0 - 4.0, 0.0, floorf(index / 5.0) * -3.0)
		Health.of(body).enabled = false
		add_child(body)
		bodies.append(body)
	for _tick in WARM_TICKS:
		await get_tree().physics_frame
	return bodies


func _shot_cost(bodies: Array[Character]) -> float:
	var spent := 0
	for shot in SHOTS:
		var body := bodies[shot % bodies.size()]
		var zones := body.get_node("HitZones") as HitZones
		var point := body.global_position + Vector3(0.0, 1.3, 0.34)
		var start := Time.get_ticks_usec()
		zones.shot(body, point, Vector3.FORWARD, 34.0, 40.0)
		spent += Time.get_ticks_usec() - start
	return float(spent) / SHOTS


func _follow_cost(bodies: Array[Character]) -> float:
	var spent := 0
	for round_index in SHOTS:
		var zones := bodies[round_index % bodies.size()].get_node("HitZones") as HitZones
		var start := Time.get_ticks_usec()
		zones.follow_bones()
		spent += Time.get_ticks_usec() - start
	return float(spent) / SHOTS


# Every character moved a little each tick, round a circle of its own, as a walking crowd is.
func _walking_ms(bodies: Array[Character]) -> float:
	var total := 0
	var homes: Array[Vector3] = []
	for body in bodies:
		homes.append(body.global_position)
	for tick in TICKS:
		var angle := tick * 0.05
		for index in bodies.size():
			bodies[index].global_position = homes[index] + Vector3(cos(angle), 0.0, sin(angle))
		await get_tree().physics_frame
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		total += Time.get_ticks_usec() - start
	for index in bodies.size():
		bodies[index].global_position = homes[index]
	return float(total) / TICKS / 1000.0


# Puts the characters' shot hulls in the world or takes them out (their shapes off).
func _hulls_on(bodies: Array[Character], on: bool) -> void:
	for body in bodies:
		var hull := ShotHull.of(body)
		if hull == null:
			continue
		for child in hull.get_children():
			if child is CollisionShape3D:
				child.disabled = not on


func _catch_up_cost(bodies: Array[Character]) -> float:
	var spent := 0
	var animations: Array[CharacterAnimation] = []
	for body in bodies:
		var animation := body.get_node("Animation") as CharacterAnimation
		animation.set_throttled(true)
		animations.append(animation)
	for round_index in SHOTS:
		var animation := animations[round_index % animations.size()]
		var start := Time.get_ticks_usec()
		animation.advance(0.1)
		spent += Time.get_ticks_usec() - start
	for animation in animations:
		animation.set_throttled(false)
	return float(spent) / SHOTS


func _physics_ms(bodies: Array[Character], flinching: bool) -> float:
	var total := 0
	var measured := 0
	for tick in TICKS:
		if flinching:
			for body in bodies:
				var reaction := body.get_node("HitReaction") as HitReaction
				if not reaction.is_flinching():
					var at := body.global_position + Vector3(0.0, 1.3, 0.2)
					body.take_hit(
						HitRecord.shot(0.0, &"chest", &"spine_03", at, Vector3.FORWARD, 40.0)
					)
		await get_tree().physics_frame
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		total += Time.get_ticks_usec() - start
		measured += 1
	return float(total) / measured / 1000.0
