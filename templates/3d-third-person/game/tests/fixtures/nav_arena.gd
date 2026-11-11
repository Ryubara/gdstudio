class_name NavArena
extends AiArena
## An `AiArena` with a navigation mesh of its own on the world's map (kit
## docs/engines/godot/navigation-in-tests.md#a-small-mesh-of-your-own): a grid of 1 m squares over
## the floor, with holes where `add_wall()` put a wall (the wall's body stands half a metre inside
## its hole, as a baked mesh keeps an agent's radius off a wall). `build()` makes the region and
## `settle()` waits until the map answers on it. Free it with `auto_free`; the region goes with it.

## The grid covers -HALF to HALF on x and z, metres.
const HALF := 14

var region: NavigationRegion3D
var _holes: Array[Rect2i] = []
var _vertices := PackedVector3Array()
var _corner_index: Dictionary[Vector2i, int] = {}


## A wall over the cells of `cells` (x and z, metres, whole numbers): a hole in the mesh and, half
## a metre inside it, a static box `height` high. Returns the box (null with `solid` off: only the
## hole).
func add_wall(cells: Rect2i, height := 2.0, solid := true) -> StaticBody3D:
	_holes.append(cells)
	if not solid:
		return null
	var size := Vector3(cells.size.x - 1.0, height, cells.size.y - 1.0)
	var centre := Vector2(cells.position) + Vector2(cells.size) / 2.0
	return add_block(centre, size, height)


## A two-way navigation link from `from` to `to` (in the arena's space).
func add_link(from: Vector3, to: Vector3) -> NavigationLink3D:
	var link := NavigationLink3D.new()
	link.start_position = from
	link.end_position = to
	add_child(link)
	return link


## Makes the region from the grid less its holes, on the world's map.
func build() -> void:
	var mesh := NavigationMesh.new()
	_vertices.clear()
	_corner_index.clear()
	var polygons: Array[PackedInt32Array] = []
	for x in range(-HALF, HALF):
		for z in range(-HALF, HALF):
			if _in_hole(Vector2i(x, z)):
				continue
			polygons.append(
				PackedInt32Array(
					[
						_corner(Vector2i(x, z)),
						_corner(Vector2i(x + 1, z)),
						_corner(Vector2i(x + 1, z + 1)),
						_corner(Vector2i(x, z + 1))
					]
				)
			)
	mesh.vertices = _vertices
	for polygon in polygons:
		mesh.add_polygon(polygon)
	region = NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = mesh
	add_child(region)


## Waits (at most `cap` physics frames) until the map answers at `probe` from this arena's
## region, and holds no other.
func settle(probe := Vector3(0.5, 0.0, 0.5), cap := 300) -> bool:
	var map := get_world_3d().navigation_map
	for _frame in cap:
		# The region of the suite before may still be in the map: wait for this one's.
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			var nearest := NavigationServer3D.map_get_closest_point_owner(map, probe)
			if nearest == region.get_rid() and NavigationServer3D.map_get_regions(map).size() == 1:
				return true
		await get_tree().physics_frame
	return false


## An AI character at `spot` with its navigator (the director must be added first for a budget).
func add_walker(spot: Vector3, profile: AiProfile = null) -> AiNavigator:
	var character := add_character(spot, profile)
	return character.navigator as AiNavigator


## Physics ticks until `navigator` arrives or fails, at most `seconds`; true when it arrived.
static func walk(tree: SceneTree, navigator: AiNavigator, seconds := 20.0) -> bool:
	var ticks := roundi(seconds * Engine.physics_ticks_per_second)
	for _tick in ticks:
		await tree.physics_frame
		if navigator.is_arrived():
			return true
		if not navigator.is_active():
			report(navigator)
			return false
	report(navigator)
	return navigator.is_arrived()


## Prints where a walk ended and why, for a failure.
static func report(navigator: AiNavigator) -> void:
	var at := navigator.character.global_position
	print(
		(
			"walk ended at %s, %s, %d queries, path %s"
			% [at, navigator.debug_text(), navigator.path_queries, navigator.path.points]
		)
	)


func _in_hole(cell: Vector2i) -> bool:
	for hole in _holes:
		if hole.has_point(cell):
			return true
	return false


func _corner(at: Vector2i) -> int:
	if not _corner_index.has(at):
		_corner_index[at] = _vertices.size()
		_vertices.append(Vector3(at.x, 0.0, at.y))
	return _corner_index[at]


## Counts the errors printed while it is installed (`OS.add_logger`): a query before the map's
## first iteration prints one, and GdUnit4 does not count it.
class ErrorLog:
	extends Logger
	var lines: Array[String] = []
	var _added := false

	func start() -> void:
		OS.add_logger(self)
		_added = true

	func stop() -> void:
		if _added:
			OS.remove_logger(self)
			_added = false

	func _log_error(
		function: String,
		_file: String,
		_line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_backtraces: Array[ScriptBacktrace]
	) -> void:
		lines.append("%s: %s %s" % [function, code, rationale])
