class_name HoldBlow
extends RefCounted
## A `TwoHandHold` through a melee blow (gdstudio #1288): the rifle's blows are clips with both
## hands on the rifle (`assets/animation/melee/`, `Melee_Rifle_*`), so while one plays the hold
## takes itself off by as much of the upper body as the clip holds (`MeleeLayer.share`, its fades
## too) the way `MeleeLayer` takes the pistol's support hand off: the rifle rides the clip's right
## hand on the body's own seat (`RightHandTarget`) in place of the shoulder's pocket, the chest's
## turn and the left shoulder's reach ease off, and each arm keeps the clip's own elbow
## (`HoldArm.keep_elbow`). The arms still reach the rifle's places, so on the body the clip was
## keyed on they are where the clip has them, and on the other body (its own hold, a `HoldFit`)
## the left hand meets its own place on the hand guard. A blow raises no aim (`MeleeLayer.aim_of`),
## so the rifle stays at the low ready under it and the finger off the trigger.

## How much of the upper body the blow's clip holds now (0 none, 1 all of it).
var amount := 0.0

var _animation: CharacterAnimation


## Reads the blow of `body`'s animation (its `Animation` child) for this frame.
func step(body: Character) -> void:
	if _animation == null or not is_instance_valid(_animation):
		_animation = body.get_node_or_null(^"Animation") as CharacterAnimation
	amount = 0.0
	if _animation != null and _animation.tree != null:
		amount = _animation.melee.share(_animation.tree)


## How far `body`'s weapon is aimed for the hold: its `aim_amount`, or 0 while that aim is up only
## for a blow.
func aim(body: Character) -> float:
	if _animation != null and is_instance_valid(_animation):
		return _animation.melee.aim_of(body)
	return body.aim_amount


## The pivot's place `held` (the shoulder's pocket, in the hold's space) moved toward the place
## that puts the gun on the clip's right hand by `share`: the hand bone `hand` of `skeleton` (its
## pose from the local ones up the parents), `to_here` the skeleton's space to the hold's,
## `right` the right hand's place in the gun's space and `gun_in_pivot` the gun in the pivot's.
static func carried(
	held: Transform3D,
	share: float,
	skeleton: Skeleton3D,
	hand: int,
	to_here: Transform3D,
	right: Transform3D,
	gun_in_pivot: Transform3D
) -> Transform3D:
	if share <= 0.0 or hand < 0:
		return held
	var hand_here := to_here * HandPoseModifier.global_pose(skeleton, hand)
	hand_here.basis = hand_here.basis.orthonormalized()
	var pivot := hand_here * right.affine_inverse() * gun_in_pivot.affine_inverse()
	var turn := held.basis.get_rotation_quaternion().slerp(
		pivot.basis.get_rotation_quaternion(), share
	)
	return Transform3D(Basis(turn), held.origin.lerp(pivot.origin, share))
