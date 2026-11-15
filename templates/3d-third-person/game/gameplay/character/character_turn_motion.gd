class_name CharacterTurnMotion
extends RefCounted
## The reversals and the pivots of a `Character` on its feet, inside its step, moved by their clip's
## own root (gdstudio #1442): a body running at a jog or a sprint that is asked to go back the way
## it came (`CharacterTuning.reversal_angle`) or to cut off at a run (`pivot_angle`) follows the
## clip's travel and turn curves of `locomotion.json` (`GaitClips`) tick by tick, at the clip's own
## pace. Its velocity is the travel curve's change over the tick, turned into the frame the body
## ran in when the clip began; its facing is where it began facing plus the turn curve. So the body
## keeps going the old way while it brakes over the plant, the hips swing round, and only then does
## it speed up the new way, as the clip's feet carry it; facing and travel are read separately (a
## braking body faces one way and still moves the other).
##
## The command picks the clip as it begins (the side by the way the stick asks the body to turn)
## and the body is committed to it until its turn is made (`release`: the frame its turn curve
## reaches its last yaw, or the record's `free` event if that comes first); the stick's direction
## is not read in between. Then the body's own steering takes over, blended in from the clip's
## velocity over `CharacterTuning.turn_hand_back` (the rest of the clip is the gait's run-out). The
## stick let go, a jump, a crouch, the aim, a hit, lying down, a slide or leaving the ground end it
## at once, and the body's own steering takes over from the velocity it has. With the curve's
## speed scaled to the tuning's gait speed (`run_speed` or `sprint_speed` over the clip's own at its
## first frame), the body leaves at the speed it came in at.
##
## Simulation, not cosmetics: the server and a predicting client step it from the same command and
## the same record, and `save_step_state()` keeps it in `CharacterState`, so a body put back with
## `Character.restore()` turns on the same path. `GaitTransitions` plays the clip from `clip` and
## `elapsed` (a new one each time `serial` rises), so the drawn feet are the ones the body moves by.
## A body drawn from the network never steps and never drives one (see the clips page).

## No clip.
const _NO_CLIP := &""

## The curves of each clip, worked out once and shared: `{clip: Curves}`.
static var _curves: Dictionary = {}

## The clip being followed, or the last one followed (kept after the release, for the animation);
## `&""` before any.
var clip: StringName = _NO_CLIP
## Seconds into `clip`.
var elapsed := 0.0
## Rises by one each time a clip begins: the animation starts the clip again on a change.
var serial := 0
## True once a step has asked this motion anything (a body that steps, not a puppet): the
## animation then plays a reversal or a pivot only when this motion starts one.
var driven := false

# The heading (radians about the up axis) the body ran along as the clip began: the clip's forward.
var _origin := 0.0
# The tuning's gait speed over the clip's own at its first frame.
var _scale := 1.0
# Seconds into the clip at which the body is handed back to its own steering.
var _release := 0.0
var _active := false


## The curves of one clip, as arrays a tick reads without making anything.
class Curves:
	extends RefCounted
	var travel_frames := PackedFloat32Array()
	var forward := PackedFloat32Array()
	var left := PackedFloat32Array()
	var turn_frames := PackedFloat32Array()
	var yaw := PackedFloat32Array()
	## Seconds the clip lasts.
	var length := 0.0
	## Metres a second along its forward at its first frame.
	var entry_speed := 0.0
	## Seconds into the clip from which the body steers itself again.
	var release := 0.0
	## Seconds into the clip of its `free` event (the game may cut to new input), or its length.
	var free := 0.0


## True while a clip moves the body, its hand-back included.
func is_active() -> bool:
	return _active


## True while the body is committed to the clip: it follows its curves and the stick's direction
## is not read (before `release_time()`).
func is_committed() -> bool:
	return _active and elapsed < _release


## Seconds into the clip at which the body is handed back to its own steering.
func release_time() -> float:
	return _release


## The clip of `table` for `gait` (`run`, `sprint`) and `side`, sided (`gds/Jog_Turn_180_L`),
## when its record has travel and turn curves; `&""` otherwise.
static func pick(
	table: Dictionary[StringName, StringName], gait: StringName, side: String
) -> StringName:
	var base: StringName = table.get(gait, _NO_CLIP)
	if base == _NO_CLIP:
		return _NO_CLIP
	var sided := StringName("%s_%s" % [base, side.to_upper()])
	return sided if curves_of(sided) != null else _NO_CLIP


## The curves of `name`, or null when it has no record with both curves.
static func curves_of(name: StringName) -> Curves:
	if _curves.has(name):
		return _curves[name]
	var record := GaitClips.record(name)
	var made: Curves = null
	var travel: Array = record.get("travel", [])
	var turn: Array = record.get("turn", [])
	if travel.size() >= 2 and turn.size() >= 2:
		made = Curves.new()
		for key: Array in travel:
			made.travel_frames.append(float(key[0]))
			made.forward.append(float(key[1]))
			made.left.append(float(key[2]))
		for key: Array in turn:
			made.turn_frames.append(float(key[0]))
			made.yaw.append(float(key[1]))
		made.length = float(record.get("seconds", made.travel_frames[-1] / GaitClips.FPS))
		var span := maxf(made.travel_frames[1] - made.travel_frames[0], 0.001)
		made.entry_speed = (made.forward[1] - made.forward[0]) / span * GaitClips.FPS
		made.free = made.length
		for event: Dictionary in record.get("events", []):
			if event.get("name", "") == "free":
				made.free = minf(made.free, float(event.get("frame", 0.0)) / GaitClips.FPS)
		made.release = _release_of(made)
	_curves[name] = made
	return made


# The first frame at which the turn curve has reached its last yaw, or the `free` event if that
# comes first: after it, the rest of the clip is the gait's run-out.
static func _release_of(c: Curves) -> float:
	var last_yaw := c.yaw[-1]
	for index in c.turn_frames.size():
		if absf(c.yaw[index] - last_yaw) < 0.01:
			return minf(c.turn_frames[index] / GaitClips.FPS, c.free)
	return c.free


# The travel curve at `time` seconds: (forward, left) metres on the reference body.
static func _place(c: Curves, time: float) -> Vector2:
	var frame := time * GaitClips.FPS
	var frames := c.travel_frames
	var last := frames.size() - 1
	if frame <= frames[0]:
		return Vector2(c.forward[0], c.left[0])
	if frame >= frames[last]:
		return Vector2(c.forward[last], c.left[last])
	var index := frames.bsearch(frame, true) - 1
	index = clampi(index, 0, last - 1)
	var share := (frame - frames[index]) / maxf(frames[index + 1] - frames[index], 0.0001)
	return Vector2(
		lerpf(c.forward[index], c.forward[index + 1], share),
		lerpf(c.left[index], c.left[index + 1], share)
	)


# The turn curve at `time` seconds, degrees to the left.
static func _yaw(c: Curves, time: float) -> float:
	var frame := time * GaitClips.FPS
	var frames := c.turn_frames
	var last := frames.size() - 1
	if frame <= frames[0]:
		return c.yaw[0]
	if frame >= frames[last]:
		return c.yaw[last]
	var index := clampi(frames.bsearch(frame, true) - 1, 0, last - 1)
	var share := (frame - frames[index]) / maxf(frames[index + 1] - frames[index], 0.0001)
	return lerpf(c.yaw[index], c.yaw[index + 1], share)


## One tick of `body`, before its own steering: starts a clip when `wish` (the stick's world
## direction) asks for one, and moves the body along the running one. True while a clip set the
## body's velocity and facing this tick (the body's steering is skipped).
func drive(body: Character, wish: Vector3, delta: float) -> bool:
	driven = true
	if _active:
		if _must_end(body, wish):
			_active = false
			return false
		if elapsed >= _release:
			_hand_back(body, wish, delta)
		else:
			_tick(body, delta)
		return true
	var picked := _wanted(body, wish)
	if picked == _NO_CLIP:
		return false
	_begin(body, picked)
	_tick(body, delta)
	return true


## True when `body`'s step moves its reversals and pivots by their clips (the animation then plays
## only the ones this starts): it steps, the tuning has it on and its controller allows it.
func follows(body: Character) -> bool:
	return driven and body.tuning.turn_root_motion and _allowed(body)


## True when the lean tick (`CharacterLean`, an AI's walk) may take `body`'s step: no clip runs and
## none would start.
func lets_lean(body: Character, wish: Vector3) -> bool:
	driven = true
	return not _active and _wanted(body, wish) == _NO_CLIP


## Ends the clip at once (the body was put somewhere, died, got up).
func cancel() -> void:
	_active = false


## What the next tick reads, as plain values (`CharacterState.turn`).
func save_step_state(into: Array) -> void:
	into.clear()
	into.append(_active)
	into.append(clip)
	into.append(elapsed)
	into.append(_origin)
	into.append(_scale)
	into.append(serial)


## Puts back what `save_step_state()` kept; an empty array is no clip.
func load_step_state(kept: Array) -> void:
	if kept.size() < 6:
		_active = false
		return
	_active = kept[0]
	clip = kept[1]
	elapsed = kept[2]
	_origin = kept[3]
	_scale = kept[4]
	serial = kept[5]
	var c := curves_of(clip)
	_release = c.release if c != null else 0.0
	_active = _active and c != null


# The clip the body asks for this tick, or `&""`.
func _wanted(body: Character, wish: Vector3) -> StringName:
	var tuning := body.tuning
	if not tuning.turn_root_motion or wish.is_zero_approx() or not _allowed(body):
		return _NO_CLIP
	if not body._grounded or body._action_lock > 0.0 or body.crouching or body.aiming:
		return _NO_CLIP
	if body.state != Character.State.RUN or body._prone.is_prone() or body._slide.active:
		return _NO_CLIP
	var moving := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := moving.length()
	if speed <= tuning.walk_speed + tuning.run_above_walk:
		return _NO_CLIP
	var angle := rad_to_deg(moving.angle_to(wish))
	if angle < tuning.pivot_angle:
		return _NO_CLIP
	var gait := &"run"
	if body.last_command.sprint and speed > (tuning.run_speed + tuning.sprint_speed) * 0.5:
		gait = &"sprint"
	# A reversal and a pivot are both named for the side the body turns to (`_L`: to its left).
	var side := "r" if moving.cross(wish).y < 0.0 else "l"
	var table := tuning.reversal_clips if angle >= tuning.reversal_angle else tuning.pivot_clips
	return pick(table, gait, side)


static func _allowed(body: Character) -> bool:
	return body.controller == null or body.controller.turn_clips


func _begin(body: Character, picked: StringName) -> void:
	var c := curves_of(picked)
	var tuning := body.tuning
	var moving := Vector3(body.velocity.x, 0.0, body.velocity.z)
	clip = picked
	elapsed = 0.0
	serial += 1
	_active = true
	_origin = atan2(moving.x, moving.z)
	var gait_speed := (
		tuning.sprint_speed if c.entry_speed > tuning.run_speed + 0.5 else tuning.run_speed
	)
	_scale = gait_speed / c.entry_speed if c.entry_speed > 0.01 else 1.0
	_release = c.release


func _must_end(body: Character, wish: Vector3) -> bool:
	return (
		elapsed >= _release + body.tuning.turn_hand_back
		or elapsed >= (_curves[clip] as Curves).length
		or wish.is_zero_approx()
		or not body._grounded
		or body._jump_buffer > 0.0
		or body._action_lock > 0.0
		or body.crouching
		or body._wants_crouch
		or body.aiming
		or body._prone.is_prone()
		or body._slide.active
	)


# The body's velocity over the tick from the clip's travel, and its facing from the turn.
func _tick(body: Character, delta: float) -> void:
	var c: Curves = _curves[clip]
	var after := minf(elapsed + delta, c.length)
	var moved := (_place(c, after) - _place(c, elapsed)) * _scale
	var ahead := Vector3(sin(_origin), 0.0, cos(_origin))
	var to_left := Vector3(ahead.z, 0.0, -ahead.x)
	var velocity := (ahead * moved.x + to_left * moved.y) / maxf(delta, 0.0001)
	body.velocity.x = velocity.x
	body.velocity.z = velocity.z
	body.facing = wrapf(_origin + deg_to_rad(_yaw(c, after)), -PI, PI)
	body._present_facing()
	elapsed = after


# After the release: the body steers itself from the stick, its velocity blended from the clip's
# (which keeps playing) into the steering's, all the steering's by the end of the hand-back.
func _hand_back(body: Character, wish: Vector3, delta: float) -> void:
	var c: Curves = _curves[clip]
	var after := minf(elapsed + delta, c.length)
	var moved := (_place(c, after) - _place(c, elapsed)) * _scale
	var ahead := Vector3(sin(_origin), 0.0, cos(_origin))
	var to_left := Vector3(ahead.z, 0.0, -ahead.x)
	var from_clip := (ahead * moved.x + to_left * moved.y) / maxf(delta, 0.0001)
	body._steer(wish, delta)
	var span := maxf(body.tuning.turn_hand_back, 0.0001)
	var share := smoothstep(0.0, 1.0, clampf((after - _release) / span, 0.0, 1.0))
	body.velocity.x = lerpf(from_clip.x, body.velocity.x, share)
	body.velocity.z = lerpf(from_clip.z, body.velocity.z, share)
	elapsed = after
