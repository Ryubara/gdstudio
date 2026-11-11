class_name AiNavPath
extends RefCounted
## A path an `AiNavigator` walks: the points the query gave, which of them start a navigation link
## (the stretch from such a point to the next is the link), and the point it is walking to.
##
## A point is passed when the body is within `desired` of it, or nearer the next point than the
## point itself is (so a body that ran wide of a corner does not turn back for it); the start of a
## link is passed only by reaching it. Heights come from the path: a point counts as reached only
## within `HEIGHT_REACH` of its height, so the top of a staircase is not reached from below it.

## How near in height (metres) a point must be to count as reached.
const HEIGHT_REACH := 1.2

## The points, from where the query started to the goal.
var points := PackedVector3Array()
## For each point, the instance id of the `NavigationLink3D` whose link starts there, or 0.
var link_ids := PackedInt64Array()
## The next point to reach.
var index := 0

# For each point, the length of the path from it to the end.
var _rest := PackedFloat32Array()


## Takes a new list of points (and the link owners, one per point, 0 for none).
func assign(new_points: PackedVector3Array, new_links: PackedInt64Array) -> void:
	points = new_points
	link_ids = new_links
	link_ids.resize(points.size())
	index = mini(1, points.size())
	_rest.resize(points.size())
	var total := 0.0
	for at_index in range(points.size() - 1, -1, -1):
		_rest[at_index] = total
		if at_index > 0:
			total += points[at_index - 1].distance_to(points[at_index])


## Forgets the path.
func clear() -> void:
	points = PackedVector3Array()
	link_ids = PackedInt64Array()
	_rest = PackedFloat32Array()
	index = 0


## True when there is no point left to walk to.
func is_finished() -> bool:
	return index >= points.size()


## True when the path has points.
func has_points() -> bool:
	return not points.is_empty()


## The last point, or `fallback` when there is none.
func end(fallback := Vector3.INF) -> Vector3:
	return points[points.size() - 1] if not points.is_empty() else fallback


## The link that starts at point `at` (its instance id), or 0.
func link_at(at: int) -> int:
	return link_ids[at] if at >= 0 and at < link_ids.size() else 0


## Moves `index` past every point the body at `at` has reached (the last one only within
## `last_reach`); returns how many it passed.
func advance(at: Vector3, desired: float, last_reach := INF) -> int:
	var passed := 0
	while index < points.size():
		var point := points[index]
		if absf(point.y - at.y) > HEIGHT_REACH:
			break
		var reach := desired if index < points.size() - 1 else minf(desired, last_reach)
		var near := flat(point - at).length() < reach
		var beyond := false
		if index + 1 < points.size() and link_at(index) == 0:
			var after := points[index + 1]
			beyond = flat(after - at).length() < flat(after - point).length()
		if not near and not beyond:
			break
		index += 1
		passed += 1
	return passed


## What is left to walk from `at`: to the next point, then along the rest (metres).
func left(at: Vector3) -> float:
	if index >= points.size():
		return 0.0
	return at.distance_to(points[index]) + _rest[index]


## What is left of the path from the next point on (metres).
func left_from_next() -> float:
	return _rest[index] if index < points.size() else 0.0


## The length of the whole path.
func length() -> float:
	return _rest[0] if not _rest.is_empty() else 0.0


## The point to steer to from `at`: the first point from `index` on more than `look_ahead` away
## on the ground, never past the start of a link or a change of height of a storey.
func steer_point(at: Vector3, look_ahead: float) -> Vector3:
	if index >= points.size():
		return end(at)
	var chosen := index
	while chosen < points.size() - 1:
		var point := points[chosen]
		if link_at(chosen) != 0 or flat(point - at).length() > look_ahead:
			break
		if absf(points[chosen + 1].y - at.y) > HEIGHT_REACH:
			break
		chosen += 1
	return points[chosen]


## The angle (radians) the path turns at point `at`, 0 at the ends.
func turn_at(at: int) -> float:
	if at <= 0 or at >= points.size() - 1:
		return 0.0
	var into := flat(points[at] - points[at - 1])
	var out := flat(points[at + 1] - points[at])
	if into.length_squared() < 0.0001 or out.length_squared() < 0.0001:
		return 0.0
	return into.angle_to(out)


## `vector` with no height.
static func flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)
