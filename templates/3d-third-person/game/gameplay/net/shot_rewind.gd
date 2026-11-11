class_name ShotRewind
extends RefCounted
## The AI as one shooter's screen drew it, for that shooter's shots (gdstudio #1198): lag
## compensation for a player's shot on an AI character. A client draws each character behind the
## server (its playout buffer and a send's glide), so the server meets the shot with each
## character's capsule where the shooter saw it: the history's tick of the command's `view_tick`,
## less the glide of that character's send rate for that client. A hitscan shot meets that capsule
## at once; a projectile meets it for its first `flight_seconds`, the drawn tick moving on with its
## flight (what the shooter's screen shows as the round flies), and past that the characters as
## they are now. A character met is hit where it is now, the point moved by what the character
## moved since: its hit zones answer as if the shot had come then.
##
## Only the volume a shot meets is rewound: the AI's brain, senses, navigation and its body in the
## physics world stay where they are. The characters near the shot's path are taken out of its
## physics query (`excluded`, a projectile's collision exceptions) and met here instead, so a
## character is never hit twice or where the shooter did not see it.
##
## `NetServer` makes one for a command with a shot block and gives it to the body's `Weapon` for
## that step (`Weapon.rewind`); the weapon makes one for each shot (`for_shot`).

## Metres beyond a shot's path within which a character is looked at: what a running character
## moves in the longest rewind (0.6 s at 6 m/s) and its capsule.
const NEAR_MARGIN := 4.5

var history: AiHitHistory
## The server tick the shooter's screen drew (its command's `view_tick`, made whole).
var view_tick := 0
## `func(body: AiCharacter) -> int`: the ticks behind `view_tick` the shooter's screen draws
## `body` (a send's glide at that character's rate); empty is none.
var behind := Callable()
## Seconds of a projectile's flight met with the drawn characters.
var flight_seconds := 0.5

# One shot's candidates: the characters near its path, the tick each is met at when it leaves.
var _ids := PackedInt32Array()
var _ticks := PackedInt32Array()
var _bodies: Array[AiCharacter] = []
var _skipped: Dictionary[int, bool] = {}
var _flight_ticks := 0


## A whole server tick from the low 16 bits a command carries (`low`), the one nearest `near`.
static func whole_tick(low: int, near: int) -> int:
	var back := posmod((near & 0xFFFF) - (low & 0xFFFF), 0x10000)
	if back >= 0x8000:
		back -= 0x10000
	return near - back


## The rewind of one shot that leaves `start` along `heading` and reaches `reach` metres (a
## projectile's flight over `flight_seconds`), falling `sag` metres at most below its line: the
## characters near that path, each with the tick it is met at.
func for_shot(start: Vector3, heading: Vector3, reach: float, sag := 0.0) -> ShotRewind:
	var shot := ShotRewind.new()
	shot.history = history
	shot.view_tick = view_tick
	shot.behind = behind
	shot.flight_seconds = flight_seconds
	shot._flight_ticks = roundi(flight_seconds * NetLimits.TICK_RATE)
	shot._pick(start, start + heading.normalized() * reach, NEAR_MARGIN + sag)
	return shot


## The characters this shot meets here (the bodies to leave out of its physics query).
func bodies() -> Array[AiCharacter]:
	return _bodies


## Their bodies' RIDs, for a ray's `exclude`.
func excluded() -> Array[RID]:
	var out: Array[RID] = []
	for body in _bodies:
		if is_instance_valid(body):
			out.append(body.get_rid())
	return out


## The tick `body` is met at when the shot leaves, or -1 when it is not near the shot's path.
func tick_of(body: Object) -> int:
	var index := _ids_index(body)
	return _ticks[index] if index >= 0 else -1


## Whether a projectile `age` ticks into its flight meets the characters as they are now.
func is_over(age: int) -> bool:
	return age >= _flight_ticks


## Leaves `collider` out of the next `meet` (a shot that passed between its parts flies on).
func skip(collider: Object) -> void:
	var id := _ids_index(collider)
	if id >= 0:
		_skipped[id] = true


## The first character on the segment `from`-`to` as drawn `age` ticks after the shot left, its
## capsule widened by `widen` (a projectile's radius): `collider` (the character), `share` (how
## far along the segment), `position` and `normal` (on its capsule where it is now), `centre` (the
## segment's point at the touch, moved as the character moved: a projectile's middle), or empty.
func meet(from: Vector3, to: Vector3, age := 0, widen := 0.0) -> Dictionary:
	var path := to - from
	var length := path.length()
	if length < 0.0001 or _ids.is_empty():
		return {}
	var way := path / length
	var best := length
	var found := {}
	for index in _ids.size():
		if _skipped.has(index):
			continue
		var body := _bodies[index]
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var id := _ids[index]
		var tick := _ticks[index] + age
		var size := history.size_at(id, tick)
		if size.y <= 0.0:
			continue
		var feet := history.position_at(id, tick)
		var radius := size.x + widen
		var low := feet + Vector3.UP * size.x
		var high := feet + Vector3.UP * maxf(size.y - size.x, size.x)
		var along := ray_capsule(from, way, low, high, radius)
		if along < 0.0 or along > best:
			continue
		best = along
		var touch := from + way * along
		var moved := body.global_position - feet
		found = {
			"collider": body,
			"share": along / length,
			"position": touch + moved - capsule_normal(touch, low, high) * widen,
			"normal": capsule_normal(touch, low, high),
			"centre": touch + moved,
		}
	return found


## `found` (a ray's hit along `start`-`end`, or empty) or the character this shot meets first on
## that ray, whichever is nearer, as a ray's result (`collider`, `position`, `normal`, and
## `centre` for a character).
func nearer(start: Vector3, end: Vector3, found: Dictionary) -> Dictionary:
	var reach := end
	if not found.is_empty():
		reach = found["position"]
	var met := meet(start, reach)
	return met if not met.is_empty() else found


## How far along the ray from `origin` along `way` (normalized) it first meets the capsule whose
## axis runs `low`-`high`, of `radius`; 0 when it starts inside, -1 when it misses.
static func ray_capsule(
	origin: Vector3, way: Vector3, low: Vector3, high: Vector3, radius: float
) -> float:
	var axis := high - low
	var from_low := origin - low
	var axis_sq := axis.dot(axis)
	if axis_sq < 0.000001:
		return ray_sphere(origin, way, low, radius)
	var on_axis := clampf(from_low.dot(axis) / axis_sq, 0.0, 1.0)
	if (origin - (low + axis * on_axis)).length_squared() <= radius * radius:
		return 0.0
	var axis_way := axis.dot(way)
	var axis_from := axis.dot(from_low)
	var a := axis_sq - axis_way * axis_way
	if a > 0.000001:
		var b := axis_sq * way.dot(from_low) - axis_from * axis_way
		var c := (
			axis_sq * from_low.dot(from_low) - axis_from * axis_from - radius * radius * axis_sq
		)
		var h := b * b - a * c
		if h < 0.0:
			return -1.0
		var t := (-b - sqrt(h)) / a
		var y := axis_from + t * axis_way
		if y > 0.0 and y < axis_sq:
			return t if t >= 0.0 else -1.0
	# The ends: the sphere at each end of the axis, the nearer touch.
	var first := ray_sphere(origin, way, low, radius)
	var second := ray_sphere(origin, way, high, radius)
	if first < 0.0:
		return second
	if second < 0.0:
		return first
	return minf(first, second)


## How far along the ray it first meets the sphere at `centre` of `radius`, or -1.
static func ray_sphere(origin: Vector3, way: Vector3, centre: Vector3, radius: float) -> float:
	var offset := origin - centre
	var b := offset.dot(way)
	var c := offset.dot(offset) - radius * radius
	var h := b * b - c
	if h < 0.0:
		return -1.0
	var t := -b - sqrt(h)
	return t if t >= 0.0 else -1.0


## The outward normal of the capsule `low`-`high` at `point` on it.
static func capsule_normal(point: Vector3, low: Vector3, high: Vector3) -> Vector3:
	var axis := high - low
	var share := 0.0
	if axis.length_squared() > 0.000001:
		share = clampf((point - low).dot(axis) / axis.length_squared(), 0.0, 1.0)
	var out := point - (low + axis * share)
	return out.normalized() if out.length_squared() > 0.0 else Vector3.UP


func _pick(start: Vector3, end: Vector3, margin: float) -> void:
	if history == null:
		return
	var newest := history.newest()
	for id in history.ids():
		var body := history.body_of(id)
		if body == null:
			continue
		var spot := Geometry3D.get_closest_point_to_segment(body.global_position, start, end)
		if spot.distance_to(body.global_position) > margin:
			continue
		var back: int = behind.call(body) if behind.is_valid() else 0
		_ids.append(id)
		_ticks.append(mini(view_tick - back, newest))
		_bodies.append(body)


func _ids_index(collider: Object) -> int:
	for index in _bodies.size():
		if _bodies[index] == collider:
			return index
	return -1
