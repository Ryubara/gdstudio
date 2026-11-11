extends Node
## What a region reaching the navigation map costs the frame (gdstudio #1075): the project turns
## off Godot's threaded region and map builds (`navigation/world/region_use_async_iterations`,
## `navigation/world/map_use_async_iterations`), so the build runs in the frame's navigation step.
## For three meshes (the AI section's, the pathing section's, a 128 m grid of 4096 quads) it adds
## a region with the mesh, waits until the map answers on it, then frees it, `TRIALS` times in
## each mode: STEP (both builds off, the project's choice) and THREADED (both on, Godot's default;
## a web build has no threads, so there it is the same as STEP).
##
## The cost it reads is the time from the last `_physics_process` of a frame to the first
## `_process` of the same frame: the navigation step and the physics step of a world with no
## bodies, on the main thread, with no wait for the display in it (a browser paces frames, so the
## wall time between frames says nothing there).
##
## One line of JSON, `NAV_SYNC_BENCH {...}`. Desktop:
## `godot --headless --fixed-fps 60 --path game res://tools/bench/nav_sync_bench.tscn`; browser:
## a web export with this scene as `run/main_scene` and `tools/*` out of the exclude filter, read
## by `tools/bench/nav_sync_bench.py` (`window.__nav_sync_bench`).

enum Mode { STEP, THREADED }

const TRIALS := 20
const IDLE_FRAMES := 60
const SETTLE_FRAMES := 5
const CAP := 600
const AI_MESH := "res://world/prototype/ai_section/ai_section_navmesh.tres"
const PATHING_MESH := "res://world/prototype/pathing_section/pathing_section_navmesh.tres"
## The grid: `GRID` quads a side of `GRID_CELL` metres.
const GRID := 64
const GRID_CELL := 2.0
## Where the regions stand: away from anything else on the map.
const AWAY := Vector3(500.0, 0.0, 500.0)
const ARRIVE := 0.75

var _late_usec := 0
var _after_physics: Array[float] = []
# Made in `_ready`, never at `new()`: a scene loaded and never run (a test that opens
# every scene) would leave it an orphan.
var _probe: _ProcessProbe


## Reads the after-physics time at the start of each frame's idle step.
class _ProcessProbe:
	extends Node

	var bench: Node

	func _init() -> void:
		process_priority = -1000

	func _process(_delta: float) -> void:
		bench.take_after_physics()


func _ready() -> void:
	process_physics_priority = 1000
	_probe = _ProcessProbe.new()
	_probe.bench = self
	add_child(_probe)
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	_late_usec = Time.get_ticks_usec()


## Called by the probe: the time since this frame's last physics callback.
func take_after_physics() -> void:
	if _late_usec > 0:
		_after_physics.append(float(Time.get_ticks_usec() - _late_usec))
	_late_usec = 0


func _run() -> void:
	var report := {
		"web": OS.has_feature("web"),
		"threads": OS.has_feature("threads"),
		"trials": TRIALS,
		"rows": [],
	}
	var map := get_viewport().find_world_3d().navigation_map
	while NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().process_frame
	for _frame in IDLE_FRAMES:
		await get_tree().process_frame
	_after_physics.clear()
	for _frame in IDLE_FRAMES:
		await get_tree().process_frame
	report["idle_us"] = _stats(_after_physics)
	var meshes := {
		"ai_section": load(AI_MESH) as NavigationMesh,
		"pathing_section": load(PATHING_MESH) as NavigationMesh,
		"grid_128m": _grid_mesh(),
	}
	for mesh_name: String in meshes:
		for mode: Mode in [Mode.STEP, Mode.THREADED]:
			report.rows.append(await _measure(mesh_name, meshes[mesh_name], mode))
	var line := JSON.stringify(report)
	print("NAV_SYNC_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__nav_sync_bench = %s;" % line, true)
	else:
		get_tree().quit()


func _measure(mesh_name: String, mesh: NavigationMesh, mode: Mode) -> Dictionary:
	var threaded := mode == Mode.THREADED
	var map := get_viewport().find_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(map, threaded)
	var probe := _centre(mesh, 0) + AWAY
	var ticks: Array[float] = []
	var add_cost: Array[float] = []
	var remove_cost: Array[float] = []
	# One trial more than counted: the first pays for the first use of the server's builders.
	for trial in TRIALS + 1:
		var region := NavigationRegion3D.new()
		region.navigation_mesh = mesh
		region.position = AWAY
		add_child(region)
		NavigationServer3D.region_set_use_async_iterations(region.get_rid(), threaded)
		_after_physics.clear()
		var tick := 0
		while tick < CAP and not _answers(map, probe):
			await get_tree().process_frame
			tick += 1
		# The frame that answered is read at its idle step, after this resumes: one frame more.
		await get_tree().process_frame
		var added := _most(_after_physics)
		region.free()
		_after_physics.clear()
		for _frame in SETTLE_FRAMES:
			await get_tree().process_frame
		if trial > 0:
			ticks.append(float(tick))
			add_cost.append(added)
			remove_cost.append(_most(_after_physics))
	return {
		"mesh": mesh_name,
		"polygons": mesh.get_polygon_count(),
		"mode": Mode.keys()[mode],
		"ticks": _stats(ticks),
		"add_us": _stats(add_cost),
		"remove_us": _stats(remove_cost),
	}


func _answers(map: RID, probe: Vector3) -> bool:
	return NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < ARRIVE


func _grid_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	for z in GRID + 1:
		for x in GRID + 1:
			vertices.append(Vector3(x * GRID_CELL, 0.0, z * GRID_CELL))
	mesh.vertices = vertices
	for z in GRID:
		for x in GRID:
			var a := z * (GRID + 1) + x
			# Clockwise seen from above.
			mesh.add_polygon(PackedInt32Array([a, a + 1, a + GRID + 2, a + GRID + 1]))
	return mesh


func _centre(mesh: NavigationMesh, polygon: int) -> Vector3:
	var sum := Vector3.ZERO
	var indices := mesh.get_polygon(polygon)
	for index in indices:
		sum += mesh.vertices[index]
	return sum / indices.size()


func _most(values: Array[float]) -> float:
	var most := 0.0
	for value in values:
		most = maxf(most, value)
	return most


func _stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {
		"mean": total / maxf(sorted.size(), 1.0),
		"median": sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0,
		"p95": sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0,
		"most": sorted[-1] if not sorted.is_empty() else 0.0,
	}
