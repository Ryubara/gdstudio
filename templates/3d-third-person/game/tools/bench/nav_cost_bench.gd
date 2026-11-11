extends Node
## What the AI navigator costs (gdstudio #967), the table of kit
## docs/engines/godot/crowds.md#ai-characters for the template's `AiNavigator`: N
## `ai_character.tscn` on a 96 m map of their own with 16 boxes, each walking to a goal and, on
## arriving, to the next (seeded), under the level's `AiDirector` with its shipped defaults.
##
## For each count it reads, over `FRAMES` frames, the navigators' own work a physics tick
## (the queries on their timer, the steering, the body-ray checks), the director's step beside it
## (the bodies, without the navigators), the path queries a tick (the most and the mean, against
## the budget) and the queries each navigator made against `repath_seconds`.
##
## The navigators' work is one clock read a tick around a loop that steps only navigators (kit
## #1062): with `AiNavigator.holding` on, the director's steps only note each navigator's seconds,
## and at the start of the next tick, before the director, `AiNavigator.step_held()` steps them
## all. A navigator sees its body where its last step left it, as it would in the director's
## step. The browser's clock is coarse (100 µs in Chrome without cross-origin isolation), so a
## sum of one read a navigator, as #967 read it, is no measure there; a read around the loop of
## hundreds of microseconds is.
##
## One line of JSON, `NAV_COST_BENCH {...}`. Desktop: `godot --headless --fixed-fps 60 --path game
## res://tools/bench/nav_cost_bench.tscn`; browser: the web export `gds template bench-web
## 3d-third-person nav_cost_bench` makes (kit docs/engines/godot/web-probes.md#bench-web), read by
## `tools/bench/nav_cost_bench.py` (`window.__nav_cost_bench`).

const COUNTS: Array[int] = [50, 100, 200]
const WARM_FRAMES := 60
const FRAMES := 300
const CHARACTER := "res://gameplay/ai/ai_character.tscn"
## The map: a square of `HALF` metres each way from the middle, in cells of `CELL` metres.
const HALF := 48
const CELL := 2
## The 16 boxes, on a 4 by 4 grid: `BOX_CELLS` cells a side, `BOX_SPACING` metres apart.
const BOX_CELLS := 2
const BOX_SPACING := 20

## Rounds of the fixed calibration loop timed before each row (`calibration_ms`): a busy machine
## reads slower there too, so two runs compare by it.
const CALIBRATION_ROUNDS := 200000

## The baked mesh's polygons, for the report.
var polygons := 0

var _arena: Node3D
var _director: AiDirector
var _navigators: Array[AiNavigator] = []
var _rng := RandomNumberGenerator.new()
var _spent: Array[float] = []
var _steps: Array[float] = []
var _queries: Array[int] = []
var _last_queries := 0
var _boxes: Array[Rect2i] = []
var _stepping := false
var _region: NavigationRegion3D
var _arrivals := 0
var _failures := 0
var _held_spent := 0.0


func _ready() -> void:
	_rng.seed = 967
	process_physics_priority = -1000
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 70.0, 70.0)
	camera.rotation.x = deg_to_rad(-45.0)
	add_child(camera)
	camera.make_current()
	_run.call_deferred()


func _run() -> void:
	var report := {"frames": FRAMES, "web": OS.has_feature("web"), "rows": []}
	for count in COUNTS:
		await _new_crowd(count)
		report.rows.append(await _measure(count))
		_arena.free()
		await get_tree().physics_frame
	var line := JSON.stringify(report)
	print("NAV_COST_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__nav_cost_bench = %s;" % line, true)
	else:
		get_tree().quit()


func _new_crowd(count: int) -> void:
	_arena = Node3D.new()
	add_child(_arena)
	_build_map()
	var viewer := Node3D.new()
	viewer.add_to_group(&"player")
	_arena.add_child(viewer)
	_director = AiDirector.new()
	_director.web_cap = COUNTS.max()
	_director.desktop_cap = COUNTS.max()
	_arena.add_child(_director)
	# Wait for this map's own region by its RID: an empty map answers every closest point with
	# the origin, and the last count's region stays in the map until its next iteration.
	var map := _arena.get_world_3d().navigation_map
	var settled := false
	for _frame in 300:
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			var nearest := NavigationServer3D.map_get_closest_point_owner(map, Vector3(1, 0, 1))
			if nearest == _region.get_rid() and NavigationServer3D.map_get_regions(map).size() == 1:
				settled = true
				break
		await get_tree().physics_frame
	if not settled:
		push_error("nav_cost_bench: the map never took its mesh")
	_navigators.clear()
	var scene := load(CHARACTER) as PackedScene
	for index in count:
		var character := scene.instantiate() as AiCharacter
		character.position = _open_point()
		_arena.add_child(character)
		var navigator := character.navigator as AiNavigator
		navigator.arrived.connect(_on_arrived.bind(navigator))
		navigator.failed.connect(_on_failed.bind(navigator))
		_navigators.append(navigator)
	await get_tree().physics_frame
	for navigator in _navigators:
		navigator.go_to(_open_point(), 0.6)


func _measure(count: int) -> Dictionary:
	for _i in WARM_FRAMES:
		await get_tree().process_frame
	var calibration := _calibrate()
	_spent.clear()
	_steps.clear()
	_queries.clear()
	_last_queries = _total_queries()
	var queries_before := _last_queries
	AiNavigator.holding = true
	_stepping = true
	get_tree().physics_frame.connect(_on_physics_frame)
	var ticks_before := _director.tick
	_arrivals = 0
	_failures = 0
	var walked_before := _walked_seconds()
	for _frame in FRAMES:
		await get_tree().process_frame
	get_tree().physics_frame.disconnect(_on_physics_frame)
	_stepping = false
	AiNavigator.holding = false
	AiNavigator.step_held()
	var ticks := _director.tick - ticks_before
	var seconds := float(ticks) / Engine.physics_ticks_per_second
	var spent := _mean(_spent)

	var step := _mean(_steps)
	var most := 0
	for taken in _queries:
		most = maxi(most, taken)
	var asked := _total_queries() - queries_before
	var repath := (_navigators[0].character.profile as AiProfile).repath_seconds
	return {
		"characters": count,
		"arrivals": _arrivals,
		"failures": _failures,
		# The share of the time the crowd walked with a goal (a commanded speed): 1 when every
		# navigator walks every tick.
		"walking_share": (_walked_seconds() - walked_before) / maxf(seconds * count, 0.001),
		"polygons": polygons,
		"nav_mean_us": spent,
		"nav_us_each": spent / count,
		"calibration_ms": calibration,
		"step_mean_us": step,
		"queries_most_a_tick": most,
		"queries_mean_a_tick": float(asked) / maxi(ticks, 1),
		"paths_per_tick": _director.paths_per_tick,
		"queries_each_a_second": float(asked) / count / maxf(seconds, 0.001),
		"repath_limit_a_second": 1.0 / repath,
		"full": _director.count_at(AiDirector.Tier.FULL),
		"reduced": _director.count_at(AiDirector.Tier.REDUCED),
		"dormant": _director.count_at(AiDirector.Tier.DORMANT),
	}


# Before the director (`process_physics_priority`): steps the navigators its last tick held.
func _physics_process(_delta: float) -> void:
	if not _stepping:
		return
	var start := Time.get_ticks_usec()
	AiNavigator.step_held()
	_held_spent = float(Time.get_ticks_usec() - start)


func _on_physics_frame() -> void:
	# The navigators' work and the director's step of the tick before this one.
	_spent.append(_held_spent)
	_held_spent = 0.0
	_steps.append(float(_director.last_step_usec))
	var total := _total_queries()
	_queries.append(total - _last_queries)
	_last_queries = total


func _on_arrived(navigator: AiNavigator) -> void:
	_arrivals += 1
	navigator.go_to.call_deferred(_open_point(), 0.6)


func _on_failed(_reason: int, navigator: AiNavigator) -> void:
	_failures += 1
	navigator.go_to.call_deferred(_open_point(), 0.6)


func _walked_seconds() -> float:
	var total := 0.0
	for navigator in _navigators:
		total += navigator.watch.walking_seconds
	return total


func _total_queries() -> int:
	var total := 0
	for navigator in _navigators:
		total += navigator.path_queries
	return total


func _calibrate() -> float:
	var start := Time.get_ticks_usec()
	var value := 0.0
	for index in CALIBRATION_ROUNDS:
		value = sin(value + index) * 0.5
	return (Time.get_ticks_usec() - start + int(value * 0.0)) / 1000.0


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxi(values.size(), 1)


# A point on the open floor, off the boxes.
func _open_point() -> Vector3:
	while true:
		var point := Vector3(
			_rng.randf_range(-HALF + 2, HALF - 2), 0.0, _rng.randf_range(-HALF + 2, HALF - 2)
		)
		var cell := Vector2i(floori(point.x / CELL), floori(point.z / CELL))
		var clear := true
		for box in _boxes:
			if box.grow(1).has_point(cell):
				clear = false
		if clear:
			return point
	return Vector3.ZERO


# The floor and the 16 boxes under a region that bakes its mesh from them, as a level does (a
# baked mesh has a few large polygons, which is what a query's cost depends on).
func _build_map() -> void:
	_boxes.clear()
	# Synchronous iterations from the start: the map takes the baked mesh at the next physics step
	# (kit docs/engines/godot/navigation-in-tests.md, a small mesh of your own).
	NavigationServer3D.map_set_use_async_iterations(_arena.get_world_3d().navigation_map, false)
	for row in 4:
		for column in 4:
			var at := Vector2i(
				(-30 + column * BOX_SPACING) / CELL, (-30 + row * BOX_SPACING) / CELL
			)
			_boxes.append(Rect2i(at, Vector2i(BOX_CELLS, BOX_CELLS)))
	var region := NavigationRegion3D.new()
	_region = region
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# The map's cells (0.25 m, 0.1 m high). A radius of 0.5 m warns that it is ceiled to the cells
	# (4.7.2, though 0.5 is two cells); 0.25, 0.75 and 1 do not.
	mesh.cell_size = 0.25
	mesh.cell_height = 0.1
	mesh.agent_radius = 0.75
	mesh.agent_max_climb = 0.3
	mesh.agent_height = 1.8
	region.navigation_mesh = mesh
	_arena.add_child(region)
	# The region's polygons on the physics step too, not a worker thread (gdstudio #1075).
	NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
	region.add_child(_box(Vector3(0, -0.5, 0), Vector3(HALF * 2.0, 1.0, HALF * 2.0)))
	for box in _boxes:
		var centre := Vector2(box.position * CELL) + Vector2(box.size * CELL) / 2.0
		var size := float(box.size.x * CELL) - 1.0
		region.add_child(_box(Vector3(centre.x, 1.0, centre.y), Vector3(size, 2.0, size)))
	region.bake_navigation_mesh(false)
	polygons = mesh.get_polygon_count()


func _box(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	return body
