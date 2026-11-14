class_name ChargePull
extends Resource
## The charging handle's pull in a long gun's reload (kit #1266): after the new magazine is seated
## the left hand comes off it with its fingers open, goes up the gun's left side to the handle,
## hooks its fingers on the latch, pulls the `Bolt` node back by `travel`, lets it go (the bolt
## runs home alone, where the bolt's sound plays) and goes back under the hand guard. `TwoHandHold`
## asks it, by the weapon's reload progress, where the left hand's bone is (`hand_place()`), how
## the fingers lie (`finger_weights()`, with `third` on the `HandPoseModifier` closed on the handle)
## and how far back the bolt is (`bolt_pull()`). The hand's place on the handle is the hold's
## `ChargeHand` marker and its fingers the hold's `charge_pose`, both solved on each body by
## `tools/hold/solve_rifle_hold.py` (a `HoldFit` holds another body's). The last leg, from under
## the hand guard onto it, is the hold's own (`TwoHandHold.reload_return`). Only a reload of an
## empty magazine has it (kit #1402, `ChargeBolt.pulls()`): with rounds left the bolt stays home and
## the hand goes straight back from the magazine by `straight_return`. Cosmetic, never sent.

## How far the bolt runs back, in the gun's space (the model's README: along +X).
@export var travel := Vector3(0.06, 0.0, 0.0)
## Where the hand is before it closes on the handle, from its place there, in the gun's space:
## out to the left, so the open fingers come onto the latch from beside the stock.
@export var approach := Vector3(0.0, 0.0, 0.08)
## Where the hand goes as it lets go, from its place at the end of the pull: out to the left, off
## the latch, before it goes forward to the hand guard.
@export var let_go := Vector3(0.0, -0.01, 0.06)
## The share of the way from there to under the hand guard at which the hand passes beside the
## magazine (where it went up from): the way forward stays out to the left of the gun, where a
## straight line went 13 to 29 mm through the receiver's side.
@export_range(0.05, 0.95, 0.01) var home_beside := 0.6

@export_group("Shares of the reload")
## Between these the hand comes off the seated magazine (the way it came on) and opens.
@export var leave := Vector2(0.63, 0.69)
## Between these it goes up the gun's left side to beside the handle.
@export var reach := Vector2(0.69, 0.77)
## Between these it comes onto the handle and its fingers close on the latch.
@export var grip := Vector2(0.77, 0.8)
## Between these it pulls the handle back by `travel`.
@export var pull := Vector2(0.8, 0.86)
## Between these it lets go and opens; the bolt runs home within `slam` of the first.
@export var release := Vector2(0.86, 0.88)
@export_range(0.001, 0.1, 0.001) var slam := 0.015
## A reload with rounds left (no pull): between these the hand goes from the magazine straight
## back under the hand guard and onto it, in place of the hold's `reload_return`, which is where
## the pull's way ends.
@export var straight_return := Vector2(0.66, 0.86)


## Whether the hand is on the pull's way (from the magazine until it is under the hand guard,
## where the hold's own way back takes it at `home`, the hold's `reload_return.x`).
func holds_way(progress: float, home: float) -> bool:
	return progress >= leave.x and progress < home


## How far along the hold's own way from the hand guard to the magazine the hand counts as, for
## the hold's fingers and its last leg (`way`: the shares of that way where the fingers are open,
## where the hand is beside the magazine and where it is under the hand guard): on the magazine
## until the hand lets go of the handle, then from open to beside the magazine and on to under the
## hand guard by `home_rest.x`, as the hand passes those places, then onto it by `home_rest.y`
## (the hold's `reload_return`). Below 0 before the pull's way.
func to_magazine(progress: float, way: Vector3, home_rest: Vector2) -> float:
	var home := home_rest.x
	var rest := home_rest.y
	if progress < leave.x:
		return -1.0
	if progress < release.y:
		return 1.0
	var middle := lerpf(release.y, home, home_beside)
	if progress < middle:
		return lerpf(way.x, way.y, smoothstep(release.y, middle, progress))
	if progress < home:
		return lerpf(way.y, way.z, smoothstep(middle, home, progress))
	return way.z * (1.0 - smoothstep(home, rest, progress))


## The left hand bone's place in the gun's space on the pull's way: `on_magazine` the seated
## magazine's marker, `beside` beside it, `handle` the `ChargeHand` marker, `below` under the hand
## guard where the hold's own way back starts at `home`.
func hand_place(
	progress: float,
	on_magazine: Transform3D,
	beside: Transform3D,
	handle: Transform3D,
	below: Transform3D,
	home: float
) -> Transform3D:
	var pulled := Transform3D(
		handle.basis, handle.origin + travel * smoothstep(pull.x, pull.y, progress)
	)
	var near := handle.translated(approach)
	var off := pulled.translated(let_go)
	var middle := lerpf(release.y, home, home_beside)
	# Each leg: where it starts, where it ends, and its shares.
	var legs: Array = [
		[on_magazine, beside, leave],
		[beside, near, reach],
		[near, handle, grip],
		[pulled, pulled, pull],
		[pulled, off, release],
		[off, beside, Vector2(release.y, middle)],
		[beside, below, Vector2(middle, home)],
	]
	var leg: Array = legs[-1]
	for each: Array in legs:
		if progress < (each[2] as Vector2).y:
			leg = each
			break
	var shares: Vector2 = leg[2]
	var start: Transform3D = leg[0]
	return start.interpolate_with(leg[1], smoothstep(shares.x, shares.y, progress))


## The left hand's finger weights through the pull's first part (pose: the support pose, `second`
## the magazine's, `open` the opened hand, `third` the hand closed on the handle): on the magazine,
## opened as one off it, closed on the latch and opened again. `own` is the hold's own (`second`,
## `open`, `open_together` as 0 or 1, `third`), given back with `third` 0 outside the first part.
func finger_weights(progress: float, own: Vector4) -> Vector4:
	if progress < leave.x or progress >= release.y:
		return Vector4(own.x, own.y, own.z, 0.0)
	var closed := (
		smoothstep(grip.x, grip.y, progress) * (1.0 - smoothstep(release.x, release.y, progress))
	)
	return Vector4(1.0, smoothstep(leave.x, leave.y, progress), 1.0, closed)


## Whether the hand's fingers are closed on the handle at a share of the reload.
func is_gripping(progress: float) -> bool:
	return progress >= grip.y - 0.0001 and progress <= release.x + 0.0001


## How far back the bolt is along `travel`, 0 to 1: with the hand until it lets go, then home
## within `slam`.
func bolt_pull(progress: float) -> float:
	if progress < 0.0:
		return 0.0
	if progress <= release.x:
		return smoothstep(pull.x, pull.y, progress)
	return clampf(1.0 - (progress - release.x) / maxf(slam, 0.0001), 0.0, 1.0)
