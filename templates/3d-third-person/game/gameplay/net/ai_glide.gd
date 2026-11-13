class_name AiGlide
extends RefCounted
## Where one AI character is drawn on a client, between the server's rows (`AiReplica` keeps one a
## character). Rows wait in a playout buffer until the replica's clock, a few sends behind the
## newest TICK, reaches their tick; each released row is walked to over the ticks since the row
## before (a glide: as even at 30 sends a second as at 60, one row behind), so a row every second
## TICK, or every eighth for a farther character, moves it evenly. The first row, a row more than
## `max_jump` away (a teleport, a new life) or one after a gap longer than `MAX_GAP_TICKS` sets it
## down at once. When the glide is done and the next row has not come, it goes on at the row's
## speed for at most `extrapolate_ticks`, and never through what `space` holds in `mask`. Plain
## code; one `step` a physics tick.

## Server ticks between two rows past which the character is set down, not walked: two seconds,
## past the slowest send rate (1 a second).
const MAX_GAP_TICKS := 2 * NetLimits.TICK_RATE
## Metres ahead of the body a guess ahead checks for a wall (about its radius).
const GUESS_REACH := 0.35
## Metres up from the feet the guess's ray runs.
const GUESS_HEIGHT := 0.5
## Below this speed (m/s) a character is not guessed ahead.
const GUESS_MIN_SPEED := 0.05
## Metres a second below which the way the rows head is too slow to tell: a body asked to move
## keeps the way it had (a reversal's speed passes through 0, and the stepped body's goal never
## does), or faces it from standing (`PlayerPuppet.GOAL_HOLD_BELOW`).
const GOAL_HOLD_BELOW := 0.5

## Metres past which a row sets the character down.
var max_jump := 4.0
## Ticks a character may be guessed ahead after its glide ends (100 ms at 60 a second).
var extrapolate_ticks := 6
## The place, heading and velocity (m/s) drawn now.
var position := Vector3.ZERO
var yaw := 0.0
var velocity := Vector3.ZERO
## The newest row released (null before the first).
var row: AiRow
## Whether a row has been released (the character is drawn).
var placed := false
## Rows that set the character down after the first (a jump), and ticks guessed ahead.
var jumps := 0
var guessed := 0
## The tick the newest released row is of.
var row_tick := -1

var _queue: Array[AiRow] = []
var _ticks := PackedInt32Array()
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _yaw_from := 0.0
var _yaw_to := 0.0
var _done := 0
var _total := 0
var _guess_left := 0


## Adds the row of server tick `tick` to the playout buffer (one no newer than the newest is
## ignored).
func push(tick: int, entry: AiRow) -> void:
	if not _ticks.is_empty() and tick <= _ticks[-1]:
		return
	if _ticks.is_empty() and tick <= row_tick:
		return
	_queue.append(entry)
	_ticks.append(tick)


## Rows waiting in the buffer.
func waiting() -> int:
	return _queue.size()


## Whether it is walking to a row now.
func is_gliding() -> bool:
	return _total > 0


## The velocity (m/s) the rows head for: from the newest row released to the newest one waiting,
## a few sends ahead of the moment drawn; the glide's own velocity when none waits.
func heading() -> Vector3:
	if row == null or _ticks.is_empty() or _ticks[-1] <= row_tick:
		return velocity
	var newest: AiRow = _queue[-1]
	if newest.is_dead() or newest.position.distance_to(row.position) > max_jump:
		return velocity
	return (newest.position - row.position) * (float(NetLimits.TICK_RATE) / (_ticks[-1] - row_tick))


## The goal a puppet's starts and stops read (`Character.motion_goal`, gdstudio #1452): none when
## the row says the body is asked for no speed (`AiRow.speed`, the server body's goal speed), else
## that speed along where the rows head (`heading`), or along `kept`, the goal it had, while they
## head too slowly to tell a way, or along the way it faces from standing.
func goal(kept: Vector3) -> Vector3:
	if row == null or row.is_dead() or row.speed < GUESS_MIN_SPEED:
		return Vector3.ZERO
	var way := heading()
	way.y = 0.0
	if way.length() < GOAL_HOLD_BELOW:
		way = Vector3(kept.x, 0.0, kept.z)
	if way.is_zero_approx():
		way = Vector3.BACK.rotated(Vector3.UP, row.yaw)
	return way.normalized() * row.speed


## One physics tick with the clock at server tick `drawn`: the rows due are released, then the
## glide (or the guess ahead) moves one tick.
func step(drawn: int, space: PhysicsDirectSpaceState3D = null, mask := 0) -> void:
	while not _ticks.is_empty() and _ticks[0] <= drawn:
		var tick := _ticks[0]
		var entry: AiRow = _queue.pop_front()
		_ticks.remove_at(0)
		_release(tick, entry)
	if _total > 0:
		_done += 1
		var share := minf(float(_done) / float(_total), 1.0)
		position = _from.lerp(_to, share)
		yaw = lerp_angle(_yaw_from, _yaw_to, share)
		if _done >= _total:
			_total = 0
		return
	_guess(space, mask)


func _release(tick: int, entry: AiRow) -> void:
	var gap := tick - row_tick
	row_tick = tick
	row = entry
	_guess_left = extrapolate_ticks
	if (
		not placed
		or entry.is_dead()
		or gap <= 0
		or gap > MAX_GAP_TICKS
		or position.distance_to(entry.position) > max_jump
	):
		if placed:
			jumps += 1
		placed = true
		position = entry.position
		yaw = entry.yaw
		velocity = Vector3.ZERO
		_total = 0
		return
	_from = position
	_to = entry.position
	_yaw_from = yaw
	_yaw_to = entry.yaw
	_done = 0
	_total = gap
	velocity = (_to - _from) * (float(NetLimits.TICK_RATE) / gap)


# Past the end of the glide: on at the row's speed, the way it was going, for a few ticks, and
# never into a wall.
func _guess(space: PhysicsDirectSpaceState3D, mask: int) -> void:
	if row == null or row.is_dead() or _guess_left <= 0 or row.speed < GUESS_MIN_SPEED:
		velocity = Vector3.ZERO
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < GUESS_MIN_SPEED * GUESS_MIN_SPEED:
		velocity = Vector3.ZERO
		return
	var way := flat.normalized()
	var move := way * row.speed / NetLimits.TICK_RATE
	if space != null:
		var from := position + Vector3.UP * GUESS_HEIGHT
		var query := PhysicsRayQueryParameters3D.create(from, from + move + way * GUESS_REACH, mask)
		if not space.intersect_ray(query).is_empty():
			_guess_left = 0
			velocity = Vector3.ZERO
			return
	_guess_left -= 1
	guessed += 1
	position += move
	velocity = way * row.speed
