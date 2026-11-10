# The probe of the arena-layout eval (kit evals/godot/arena-layout/TASK.md). `gds eval check` copies it into the game
# as tests/eval_probe/probe.gd, runs it headless (`godot -s`) and reads the `EVAL_ROW {json}` lines it prints. It
# measures the arena the way a level review does: the real body's reach by a flood fill of capsule-sized steps,
# sightlines by rays at chest height, the landmark by rays from the eye, the dead's gates and the navigation mesh.
extends SceneTree

const ARENA := "res://world/arena/arena.tscn"
const WINDOW := 24  # the probe's grid covers -24 to 24 m, past the footprint, so a way out is seen
const FOOTPRINT := 20.0  # the arena must keep every reachable place inside |x| and |z| of this
const RADIUS := 0.4
const BODY_HEIGHT := 1.8
const HOP := 1.1  # the highest block the body gets onto from level ground
const EYE := 1.6
const CHEST := 1.0
const FLOOR_LEVEL := 0.5  # a cell whose ground is up to this high is floor, higher is a top of something
const RAY_RUN := 60.0
const DIRECTIONS := 4
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

var _space: PhysicsDirectSpaceState3D
var _cells := {}  # Vector2i -> Vector3 ground point, or null when there is none
var _clear := {}  # Vector2i -> bool, the capsule fits standing there


func _initialize() -> void:
	_run()


func _row(name: String, value: Variant, op: String, limit: Variant) -> void:
	var ok := false
	match op:
		"==":
			ok = value == limit
		"<=":
			ok = value <= limit
		">=":
			ok = value >= limit
	print(
		"EVAL_ROW ",
		JSON.stringify({"name": name, "value": value, "op": op, "limit": limit, "pass": ok})
	)


func _info(name: String, value: Variant) -> void:
	print("EVAL_ROW ", JSON.stringify({"name": name, "value": value, "op": "info", "limit": ""}))


func _run() -> void:
	var scene := load(ARENA) as PackedScene
	_row("the arena scene loads", scene != null, "==", true)
	if scene == null:
		quit()
		return
	root.add_child(scene.instantiate())
	for i in 4:
		await physics_frame
	_space = root.world_3d.direct_space_state
	var spawn := _spawn()
	var reach := _flood(spawn)
	_measure_reach(reach)
	_measure_cover()
	_measure_gates(spawn, reach)
	_measure_sight(reach)
	_measure_landmark(reach)
	await _measure_navigation(reach)
	quit()


func _cell_centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x), floori(point.z))


func _ground(cell: Vector2i) -> Variant:
	if _cells.has(cell):
		return _cells[cell]
	var centre := _cell_centre(cell)
	var from := Vector3(centre.x, 30.0, centre.y)
	var hit := _space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, Vector3(centre.x, -3.0, centre.y))
	)
	var found: Variant = null
	if not hit.is_empty() and (hit.normal as Vector3).y >= 0.7:
		found = hit.position
	_cells[cell] = found
	return found


func _capsule_free(ground: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = BODY_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.margin = 0.0
	query.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * (BODY_HEIGHT / 2.0 + 0.02))
	return _space.intersect_shape(query, 1).is_empty()


func _fits(cell: Vector2i, ground: Vector3) -> bool:
	if not _clear.has(cell):
		_clear[cell] = _capsule_free(ground)
	return _clear[cell]


func _spawn() -> Vector3:
	var spawns := get_nodes_in_group("player_spawn")
	_row("player spawns (group player_spawn)", spawns.size(), "==", 1)
	if spawns.is_empty():
		return Vector3.ZERO
	return (spawns[0] as Node3D).global_position


## The cells the real body reaches from the spawn: a rise of up to HOP, any drop, a place the capsule fits.
func _flood(spawn: Vector3) -> Dictionary:
	var start := _cell_of(spawn)
	var reach := {}
	var first: Variant = _ground(start)
	if first == null or not _fits(start, first):
		return reach
	reach[start] = first
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var here: Vector3 = reach[cell]
		for offset in NEIGHBOURS:
			var next := cell + offset
			if reach.has(next) or absi(next.x) > WINDOW or absi(next.y) > WINDOW:
				continue
			var ground: Variant = _ground(next)
			if ground == null or (ground as Vector3).y - here.y > HOP or not _fits(next, ground):
				continue
			var rise: float = (ground as Vector3).y - here.y
			if rise > 0.4 and not _capsule_free(Vector3(here.x, (ground as Vector3).y, here.z)):
				continue  # mid-hop the body is above its own cell at the height it climbs to
			reach[next] = ground
			queue.append(next)
	return reach


func _measure_reach(reach: Dictionary) -> void:
	var outside := 0
	var void_edges := 0
	var floor_cells := 0
	var tops := 0
	for cell: Vector2i in reach:
		var centre := _cell_centre(cell)
		if absf(centre.x) > FOOTPRINT or absf(centre.y) > FOOTPRINT:
			outside += 1
		for offset in NEIGHBOURS:
			var next := cell + offset
			if absi(next.x) > WINDOW or absi(next.y) > WINDOW or _ground(next) == null:
				void_edges += 1
				break
		if (reach[cell] as Vector3).y <= FLOOR_LEVEL:
			floor_cells += 1
		else:
			tops += 1
	_row("reachable ground the body walks on (m2)", floor_cells, ">=", 600)
	_row("reachable places outside the 40 m footprint", outside, "==", 0)
	_row("reachable places at a drop into the void", void_edges, "==", 0)
	_info("places the body reaches on top of something", tops)


func _top_of(node: Node3D) -> float:
	var at := node.global_position
	var hit := _space.intersect_ray(
		PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 3.0)
	)
	return (hit.position as Vector3).y if not hit.is_empty() else -99.0


func _measure_cover() -> void:
	var pieces := get_nodes_in_group("cover")
	_row("cover pieces (group cover), at least", pieces.size(), ">=", 8)
	_row("cover pieces (group cover), at most", pieces.size(), "<=", 16)
	var lowest := 99.0
	var highest := -99.0
	var quarters := {}
	for piece: Node3D in pieces:
		var top := _top_of(piece)
		lowest = minf(lowest, top)
		highest = maxf(highest, top)
		var quarter := Vector2i(
			1 if piece.global_position.x >= 0.0 else -1, 1 if piece.global_position.z >= 0.0 else -1
		)
		quarters[quarter] = quarters.get(quarter, 0) + 1
	_row("lowest cover top (m)", snappedf(lowest, 0.01), ">=", 1.3)
	_row("highest cover top (m)", snappedf(highest, 0.01), "<=", 1.5)
	var least := 99
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			least = mini(least, quarters.get(Vector2i(sx, sz), 0))
	_row("cover pieces in the thinnest quarter", least, ">=", 2)


func _clear_line(from: Vector3, to: Vector3) -> bool:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _measure_gates(spawn: Vector3, reach: Dictionary) -> void:
	var gates := get_nodes_in_group("enemy_gates")
	_row("enemy gates (group enemy_gates)", gates.size(), "==", 4)
	var reachable := 0
	var hidden := 0
	var nearest_spawn := 999.0
	var nearest_gate := 999.0
	var innermost := 999.0
	for gate: Node3D in gates:
		var at := gate.global_position
		var cell := _cell_of(at)
		if reach.has(cell) and absf(at.y - (reach[cell] as Vector3).y) <= 0.5:
			reachable += 1
		else:
			_info("a gate the body cannot walk to", "%s at %s" % [gate.name, at])
		nearest_spawn = minf(nearest_spawn, _flat(at, spawn))
		innermost = minf(innermost, maxf(absf(at.x), absf(at.z)))
		if _clear_line(spawn + Vector3.UP * CHEST, at + Vector3.UP * CHEST):
			_info("a gate in the spawn's sight", gate.name)
		else:
			hidden += 1
		for other: Node3D in gates:
			if other != gate:
				nearest_gate = minf(nearest_gate, _flat(at, other.global_position))
	_row("gates the body can walk to, standing on ground", reachable, "==", 4)
	_row("nearest gate to the spawn (m)", snappedf(nearest_spawn, 0.1), ">=", 12.0)
	_row("nearest two gates apart (m)", snappedf(nearest_gate, 0.1), ">=", 15.0)
	_row("gate nearest the middle, along an axis (m)", snappedf(innermost, 0.1), ">=", 14.0)
	_row("gates out of the spawn's sight at chest height", hidden, ">=", 3)


func _floor_cells(reach: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in reach:
		if (reach[cell] as Vector3).y <= FLOOR_LEVEL:
			cells.append(cell)
	cells.sort()
	return cells


func _measure_sight(reach: Dictionary) -> void:
	var cells := _floor_cells(reach)
	if cells.size() < 2:
		_row("floor cells to measure sightlines from", cells.size(), ">=", 2)
		return
	var longest := 0.0
	var longest_from := ""
	var total := 0.0
	var runs := 0
	for cell in cells:
		var from := (reach[cell] as Vector3) + Vector3.UP * CHEST
		for d in DIRECTIONS:
			var angle := TAU * d / DIRECTIONS
			var to := from + Vector3(cos(angle), 0.0, sin(angle)) * RAY_RUN
			var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
			var run := RAY_RUN if hit.is_empty() else from.distance_to(hit.position)
			if run > longest:
				longest = run
				longest_from = "%s heading %d deg" % [_cell_centre(cell), roundi(rad_to_deg(angle))]
			total += run
			runs += 1
	var mean := snappedf(total / runs, 0.1)
	_info("the longest clear line starts at", longest_from)
	_row("longest clear line at chest height (m)", snappedf(longest, 0.1), "<=", 30.0)
	_row("mean clear run at chest height, at most (m)", mean, "<=", 14.0)
	_row("mean clear run at chest height, at least (m)", mean, ">=", 6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var open := 0
	var pairs := 600
	for i in pairs:
		var a: Vector2i = cells[rng.randi() % cells.size()]
		var b: Vector2i = cells[rng.randi() % cells.size()]
		if _clear_line(
			(reach[a] as Vector3) + Vector3.UP * CHEST, (reach[b] as Vector3) + Vector3.UP * CHEST
		):
			open += 1
	var share := snappedf(float(open) / pairs, 0.01)
	_row("share of random place pairs that see each other, at most", share, "<=", 0.6)
	_row("share of random place pairs that see each other, at least", share, ">=", 0.15)


func _measure_landmark(reach: Dictionary) -> void:
	var marks := get_nodes_in_group("landmark")
	_row("landmarks (group landmark)", marks.size(), "==", 1)
	if marks.is_empty():
		return
	var mark: Node3D = marks[0]
	var top := _top_of(mark)
	_row("landmark top above the floor (m)", snappedf(top, 0.01), ">=", 6.0)
	var target := Vector3(mark.global_position.x, top - 0.05, mark.global_position.z)
	var seen := 0
	var cells := _floor_cells(reach)
	for cell in cells:
		var from := (reach[cell] as Vector3) + Vector3.UP * EYE
		var hit := _space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, target + (target - from).normalized() * 0.5)
		)
		if hit.is_empty() or mark.is_ancestor_of(hit.collider as Node):
			seen += 1
	_row(
		"share of the ground the landmark is seen from",
		snappedf(float(seen) / maxi(cells.size(), 1), 0.01),
		">=",
		0.85
	)


func _measure_navigation(reach: Dictionary) -> void:
	var baked := 0
	for node in root.find_children("*", "NavigationRegion3D", true, false):
		var region := node as NavigationRegion3D
		if region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 0:
			baked += 1
	_row("navigation regions with a baked mesh", baked, ">=", 1)
	var cells := _floor_cells(reach)
	if cells.is_empty():
		return
	var map := root.world_3d.navigation_map
	var sample := reach[cells[0]] as Vector3
	for i in 120:
		await physics_frame
		if NavigationServer3D.map_get_closest_point(map, sample).distance_to(sample) < 1.0:
			break
	var covered := 0
	for cell in cells:
		var point := reach[cell] as Vector3
		if NavigationServer3D.map_get_closest_point(map, point).distance_to(point) <= 0.6:
			covered += 1
	_row(
		"share of the ground within 0.6 m of the navigation mesh",
		snappedf(float(covered) / cells.size(), 0.01),
		">=",
		0.95
	)
