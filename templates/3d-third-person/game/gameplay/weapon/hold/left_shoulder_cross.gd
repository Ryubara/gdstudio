class_name LeftShoulderCross
extends SkeletonModifier3D
## Moves the right hand, and the pistol it carries, across to the left for a left peek lean
## (gdstudio #1435, made by `LeftShoulder`): the hand goes `shift` and turns about the muzzle so
## the muzzle points at `target` again, and the `HoldArm` right after this reaches the arm there
## (its `offset`, in the skeleton's space). It runs after the aim layer's turn and before the
## support arm, so the left hand closes on the pistol where it went.

## The hand that carries the weapon.
var hand_bone: StringName = &"hand_r"
## The muzzle in the hand bone's space.
var muzzle_in_hand := Transform3D.IDENTITY
## How far the hand goes, in the skeleton's space (metres).
var shift := Vector3.ZERO
## The point the muzzle is turned back onto, in the skeleton's space.
var target := Vector3.ZERO
## The arm that reaches the hand's new place.
var arm: HoldArm

var _hand := -2


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_hand = -2


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or arm == null:
		return
	if _hand == -2:
		_hand = skeleton.find_bone(hand_bone)
	if _hand < 0:
		return
	var hand := HandPoseModifier.global_pose(skeleton, _hand)
	var muzzle := hand * muzzle_in_hand.origin
	var moved := muzzle + shift
	var turn := Basis.IDENTITY
	var from := target - muzzle
	var to := target - moved
	if from.length_squared() > 1e-6 and to.length_squared() > 1e-6:
		turn = Basis(Quaternion(from.normalized(), to.normalized()))
	arm.offset = Transform3D(turn * hand.basis, moved + turn * (hand.origin - muzzle))
