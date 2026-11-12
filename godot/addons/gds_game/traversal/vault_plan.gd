class_name VaultPlan
extends RefCounted
## One crossing of one obstacle, as `VaultProbe.measure()` found it: whether it is a vault, a
## mantle or nothing (and why not), what was measured, and the path the feet take, warped to this
## obstacle. `position_at(share)` gives where the feet are a share of the way through, so a body
## that follows it is moved by numbers alone and two bodies with the same plan move the same way.
##
## The path is a few key points the clip's contact times line up with (`times`): for a vault the
## start, the hand plant over the near edge, the feet past the far edge and the landing; for a
## mantle the start, the feet at the top's height against the face, and standing on the top. Each
## stretch moves straight across and eases up or down (`eases`), so one clip fits any height: the
## clip plays at the speed that makes its own contact times meet these.

## What the plan does.
enum Kind {
	NONE,  ## Nothing: `refusal` says why.
	VAULT,  ## Over the obstacle, landing on the far side.
	MANTLE,  ## Up onto the obstacle, standing on its top.
}

## How a stretch of the path moves up or down (the move across is always even).
enum Ease {
	EVEN,  ## The same rate all the way.
	OUT,  ## Fast first, slowing at the end (a rise that tops out).
	IN,  ## Slow first, faster at the end (a fall).
	BOTH,  ## Slow at both ends.
}

## Why a probe refused (with `Kind.NONE`).
const NOTHING_AHEAD := &"nothing_ahead"
const NOT_VAULTABLE := &"not_vaultable"
const NOT_A_WALL := &"not_a_wall"
const TOO_OBLIQUE := &"too_oblique"
const FACE_NOT_ALLOWED := &"face_not_allowed"
const TOO_LOW := &"too_low"
const TOO_HIGH := &"too_high"
const TOP_NOT_FLAT := &"top_not_flat"
const NO_LANDING := &"no_landing"
const NO_ROOM := &"no_room"
const TOO_DEEP := &"too_deep"
const TOO_SLOW := &"too_slow"

## What the plan does.
var kind := Kind.NONE
## Why there is no plan (one of the constants above), or empty.
var refusal: StringName = &""
## The body that was crossed (the physics engine's collider), or null.
var collider: Object
## Its `Vaultable`, or null.
var vaultable: Vaultable
## The obstacle's height over the floor the character stood on, metres.
var height := 0.0
## Its depth (thickness) along the crossing, metres; `INF` when it was deeper than a vault looks.
var depth := 0.0
## The way across, flat and of length 1 (square to the face crossed).
var forward := Vector3.FORWARD
## Where the obstacle's face was touched by the probe.
var face_point := Vector3.ZERO
## The height (y) of the obstacle's top.
var top := 0.0
## Seconds the crossing takes.
var duration := 0.0
## True when it is high enough for the high clip.
var high := false
## The key points of the feet, and the share of `duration` each is reached at (the first is 0, the
## last 1), and the ease of the stretch that ends at each (the first is unused).
var points := PackedVector3Array()
var times := PackedFloat32Array()
var eases := PackedInt32Array()
## How far before the obstacle's front face the feet were when the crossing began, metres.
var near := 0.0
## For a vault timed by a `VaultClip`: the clip time it starts at, and how fast the clip plays
## (1 its own pace). A rate of 0 is a crossing with no such clip (timed by the settings' shares).
var clip_start := 0.0
var clip_rate := 0.0


## True when there is a crossing to do.
func is_valid() -> bool:
	return kind != Kind.NONE


## Where the last key point is: the landing of a vault, the stand on a mantle's top.
func end_point() -> Vector3:
	return points[points.size() - 1] if not points.is_empty() else Vector3.ZERO


## Where the feet are `share` (0 to 1) of the way through the crossing.
func position_at(share: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var at := clampf(share, 0.0, 1.0)
	for index in range(1, points.size()):
		if at <= times[index] or index == points.size() - 1:
			var span := maxf(times[index] - times[index - 1], 0.000001)
			var part := clampf((at - times[index - 1]) / span, 0.0, 1.0)
			var from := points[index - 1]
			var to := points[index]
			var across := from.lerp(to, part)
			across.y = lerpf(from.y, to.y, _ease(part, eases[index]))
			return across
	return points[points.size() - 1]


## True when the vault is timed by a `VaultClip` (`root_at()` then says where the model is).
func has_clip_timing() -> bool:
	return kind == Kind.VAULT and clip_rate > 0.0


## The time in the clip that is playing `share` (0 to 1) of the way through the crossing.
func clip_time(share: float) -> float:
	return clip_start + clampf(share, 0.0, 1.0) * duration * clip_rate


## Where the model's root is `share` of the way through a vault timed by `clip`: forward through
## the clip's own places (the hand lands where the clip put it), level, and lifted by the
## difference to the clip's reference height while a hand is on the top. The feet path
## (`position_at()`) goes up over the top instead, so the capsule never enters the obstacle; the
## two meet at the start and at the landing.
func root_at(clip: VaultClip, share: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var start := points[0]
	var landing := end_point()
	var time := clip_time(share)
	var past := (landing - start).dot(forward) - near
	var at := start + forward * (near + clip.forward_at(time, clip_start, near, past))
	var lift := height - clip.obstacle_height
	at.y = (
		start.y
		+ lift * clip.raised(time, clip_start, lift < 0.0)
		+ (landing.y - start.y) * clip.fallen(time)
	)
	return at


## A refusal: no crossing, for `reason`.
static func refused(reason: StringName) -> VaultPlan:
	var plan := VaultPlan.new()
	plan.refusal = reason
	return plan


## Everything the path needs to be followed again, as plain values (a body's saved step state).
func to_array() -> Array:
	return [
		kind,
		height,
		forward,
		top,
		duration,
		high,
		points,
		times,
		eases,
		near,
		clip_start,
		clip_rate
	]


## Fills the plan from `to_array()`'s values. The collider and the component are not kept.
func from_array(values: Array) -> VaultPlan:
	kind = values[0]
	height = values[1]
	forward = values[2]
	top = values[3]
	duration = values[4]
	high = values[5]
	points = values[6]
	times = values[7]
	eases = values[8]
	if values.size() > 11:
		near = values[9]
		clip_start = values[10]
		clip_rate = values[11]
	return self


static func _ease(part: float, ease_kind: int) -> float:
	match ease_kind:
		Ease.OUT:
			return 1.0 - (1.0 - part) * (1.0 - part)
		Ease.IN:
			return part * part
		Ease.BOTH:
			return smoothstep(0.0, 1.0, part)
	return part
