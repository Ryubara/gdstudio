class_name AiRouteRules
extends RefCounted
## The rules a navigator's goals and routes follow, each learnt the hard way on Deadnight (kit
## docs/engines/godot/crowds.md#target-off-mesh, navigation-in-tests.md#a-goal-in-a-wall,
## navigation-in-tests.md#the-nearest-point-on-the-mesh-ignores-the-layers):
##
## - a goal is snapped to open ground of the walker's layers: the nearest point of the mesh can
##   lie on another layer's polygon, or behind the wall the goal stands in;
## - a route is kept while it still ends near the target and a new one is much longer, so a
##   target off the mesh whose nearest point flips sides does not turn the walker round;
## - goals that could not be reached or that the walker gave up on are remembered for a while.

## Metres a new route must be longer than what is left of the old one for the old to be kept.
const KEEP_LONGER_BY := 6.0
## The old route is kept only while it ends this near the target (metres, on the ground).
const KEEP_END_WITHIN := 3.5
## ...and more than this is left of it to walk.
const KEEP_LEFT_OVER := 1.0
## A point counts as on open ground when the mesh is this near it on the ground (metres).
const OPEN_GROUND := 0.35
## How far back toward the walker (metres) a goal in a wall is looked past, and in what steps.
const SNAP_REACH := 4.0
const SNAP_STEP := 0.4


## True when the walker should keep its old route (`old_left` metres still to walk, ending at
## `old_end`) rather than take a new one `new_length` long, for a target at `target`.
static func keeps_route(
	old_left: float, old_end: Vector3, new_length: float, target: Vector3
) -> bool:
	if old_left <= KEEP_LEFT_OVER or not old_end.is_finite():
		return false
	if AiNavPath.flat(old_end - target).length() > KEEP_END_WITHIN:
		return false
	return new_length > old_left + KEEP_LONGER_BY


## True when the mesh polygon nearest `point` belongs to a region of `layers` (the nearest point
## of a map looks at every region, whatever its layers).
static func on_layers(map: RID, point: Vector3, layers: int) -> bool:
	var owner := NavigationServer3D.map_get_closest_point_owner(map, point)
	if not owner.is_valid():
		return false
	if NavigationServer3D.map_get_regions(map).has(owner):
		return NavigationServer3D.region_get_navigation_layers(owner) & layers != 0
	return NavigationServer3D.link_get_navigation_layers(owner) & layers != 0


## Where to walk for `goal`, seen from `from`: the nearest point of the mesh when that is open
## ground of `layers` near the goal; for a goal inside a wall or a block, the first point of open
## ground on the line back toward `from`; INF when there is none within `SNAP_REACH`.
static func snap_goal(map: RID, goal: Vector3, from: Vector3, layers: int) -> Vector3:
	var back := AiNavPath.flat(from - goal)
	var reach := minf(back.length(), SNAP_REACH)
	var direction := back.normalized() if back.length_squared() > 0.0001 else Vector3.ZERO
	var travelled := 0.0
	while true:
		var probe := goal + direction * travelled
		var nearest := NavigationServer3D.map_get_closest_point(map, probe)
		var off := AiNavPath.flat(nearest - probe).length()
		if off < OPEN_GROUND and absf(nearest.y - probe.y) < AiNavPath.HEIGHT_REACH:
			if on_layers(map, nearest, layers):
				return nearest
		travelled += SNAP_STEP
		if travelled > reach or direction == Vector3.ZERO:
			break
	return Vector3.INF


## Goals remembered until a clock time, by the cell of the ground they fall in (`CELL` metres).
class GoalMemory:
	extends RefCounted
	## The side of a cell, metres: goals this near are the same goal.
	const CELL := 1.0

	var _until: Dictionary[Vector3i, float] = {}

	## Remembers `goal` until the clock reads `until`.
	func remember(goal: Vector3, until: float) -> void:
		_until[_cell(goal)] = until

	## True when `goal` is remembered at clock time `now`.
	func holds(goal: Vector3, now: float) -> bool:
		var key := _cell(goal)
		if not _until.has(key):
			return false
		if _until[key] <= now:
			_until.erase(key)
			return false
		return true

	## Forgets everything.
	func clear() -> void:
		_until.clear()

	## How many goals it holds (expired ones included until asked).
	func size() -> int:
		return _until.size()

	func _cell(goal: Vector3) -> Vector3i:
		return Vector3i((goal / CELL).floor())
