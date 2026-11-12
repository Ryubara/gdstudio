class_name MeleeBlow
extends RefCounted
## The time of one weapon's melee blow (gdstudio #1254): how long since it started, whether it has
## landed, the way it goes and where it starts from the shooter. The `Weapon` owns one, starts it
## (`start`), moves it on its own tick (`advance`) and casts the blow's ray on the ticks inside the
## hit window. It is step state (`save` and `load`): a server and a predicting client throw and
## land a blow on the same tick.

## Seconds since the blow started; negative with none running.
var age := -1.0
## Seconds left before the next blow may start.
var cooldown := 0.0
## True once the blow has met something (it lands once).
var landed := false
## Blows started since the weapon was given its definition (picks the clip, blow by blow).
var count := 0
## The way the blow goes (world space, length 1), fixed at its start.
var heading := Vector3.FORWARD
## Where the blow starts, from the shooter's place: it moves with the body through the window.
var offset := Vector3.ZERO
## The AI as the attacker's screen drew it at the press, for a server (`ShotRewind`); null
## offline, on a client and after a restore.
var rewind: ShotRewind

# The window, read from the definition when the blow started.
var _hit_start := 0.0
var _hit_end := 0.0


## True while a blow runs or cools down: no other blow, shot or reload starts.
func busy() -> bool:
	return cooldown > 0.0


## True while the blow is between its press and the end of its window, not yet landed.
func can_land() -> bool:
	return age >= 0.0 and not landed and age <= _hit_end + 0.0001


## Starts a blow: its cooldown, window, way and start from the shooter.
func start(
	seconds: float, hit_start: float, hit_end: float, way: Vector3, from_shooter: Vector3
) -> void:
	age = 0.0
	cooldown = seconds
	landed = false
	count += 1
	heading = way
	offset = from_shooter
	_hit_start = hit_start
	_hit_end = maxf(hit_end, hit_start)
	rewind = null


## Moves the blow on by `delta` seconds and says whether the window lies in what passed (the span
## after the age before, up to the age now; a press tick of a window that starts at 0 included), so
## a body stepped several ticks at once still casts once inside a short window.
func advance(delta: float) -> bool:
	cooldown = maxf(cooldown - delta, 0.0)
	if age < 0.0:
		return false
	var before := age
	age += delta
	var in_window := not landed and age + 0.0001 >= _hit_start and before <= _hit_end + 0.0001
	if age > _hit_end + 0.0001 and not in_window:
		age = -1.0
		rewind = null
	return in_window


## Ends the window (the blow landed, or the weapon was put away or given another definition).
func finish() -> void:
	landed = true
	age = -1.0
	rewind = null


## Forgets any blow (another definition): no cooldown, no blow, the count from 0.
func reset() -> void:
	age = -1.0
	cooldown = 0.0
	landed = false
	count = 0
	rewind = null


## The step state, appended to `kept` (`Weapon.save_step_state`).
func save(kept: Array) -> void:
	kept.append_array([age, cooldown, landed, count, heading, offset, _hit_start, _hit_end])


## Puts back what `save` wrote, from `kept[at]` on.
func load(kept: Array, at: int) -> void:
	if kept.size() < at + 8:
		return
	age = kept[at]
	cooldown = kept[at + 1]
	landed = kept[at + 2]
	count = kept[at + 3]
	heading = kept[at + 4]
	offset = kept[at + 5]
	_hit_start = kept[at + 6]
	_hit_end = kept[at + 7]
	rewind = null
