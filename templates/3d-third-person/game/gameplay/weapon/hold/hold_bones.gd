class_name HoldBones
extends RefCounted
## The bone poses a `TwoHandHold` works out in the skeleton's update, from the local ones up the
## parents (kit #1347): the parents read once from the skeleton, and the pose of the spine's top
## bone that the stance has from its turn, so the chest and the left shoulder under it are
## worked out from there and not from every pose up to the root again. The web build pays for
## each step up in GDScript.

## Every bone's parent (below 0 for a root), read by `read()`.
var parents := PackedInt32Array()
## The bone whose pose `top_pose` is, this update (below 0: none is known).
var top := -1
var top_pose := Transform3D.IDENTITY


## Reads the parents of the skeleton's bones (when the model is put in).
func read(skeleton: Skeleton3D) -> void:
	parents.resize(skeleton.get_bone_count())
	for bone in parents.size():
		parents[bone] = skeleton.get_bone_parent(bone)
	top = -1


## `HandPoseModifier.global_pose()` with the parents read once: the same products in the same order.
func global_pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var posed := skeleton.get_bone_pose(bone)
	var parent := parents[bone]
	while parent >= 0:
		posed = skeleton.get_bone_pose(parent) * posed
		parent = parents[parent]
	return posed


## The pose of `bone` in the skeleton's space: from `top_pose` and the local poses under `top` when
## the bone is under it, else from every pose up to the root.
func from_top(skeleton: Skeleton3D, bone: int) -> Transform3D:
	if top >= 0:
		var posed := Transform3D.IDENTITY
		var cursor := bone
		while cursor >= 0 and cursor != top:
			posed = skeleton.get_bone_pose(cursor) * posed
			cursor = parents[cursor]
		if cursor == top:
			return top_pose * posed
	return global_pose(skeleton, bone)


## Turns the collarbone `clavicle` (by `max_turn` radians at most, times `share`) so the shoulder
## (the joint of `upper`, an upper arm under it) comes toward `target` (in the skeleton's space),
## as far as an arm of `length` needs to reach it: a shooter's shoulder comes forward to the
## fore-end. The turn is about the collarbone's root, toward the place. True when it turned.
func reach(
	skeleton: Skeleton3D,
	clavicle: int,
	upper: int,
	target: Vector3,
	length: float,
	max_turn: float,
	share: float
) -> bool:
	var above := parents[clavicle]
	var parent := from_top(skeleton, above) if above >= 0 else Transform3D()
	var root := parent * skeleton.get_bone_pose(clavicle)
	# The upper arm's joint, from the collarbone down (a shoulder bone may lie between them).
	var shoulder := skeleton.get_bone_pose(upper)
	var cursor := parents[upper]
	while cursor >= 0 and cursor != clavicle:
		shoulder = skeleton.get_bone_pose(cursor) * shoulder
		cursor = parents[cursor]
	if cursor != clavicle:
		return false
	var from := root * shoulder.origin - root.origin
	if (root.origin + from).distance_to(target) <= length:
		return false
	var toward := target - root.origin
	var axis := from.cross(toward)
	if axis.length_squared() < 1e-10:
		return false
	axis = axis.normalized()
	# The least turn that brings the shoulder within reach: turned by `a` toward the place, the
	# shoulder's distance to it squared is `both - twice * cos(whole - a)`, least at `whole`.
	var whole := from.angle_to(toward)
	var both := from.length_squared() + toward.length_squared()
	var twice := 2.0 * from.length() * toward.length()
	var high := minf(max_turn, whole)
	var reached := (both - length * length) / maxf(twice, 1e-9)
	if reached < 1.0:
		high = minf(high, maxf(whole - acos(maxf(reached, -1.0)), 0.0))
	var angle := high * share
	var turned := Transform3D(Basis(axis, angle) * root.basis, root.origin)
	skeleton.set_bone_pose(clavicle, parent.affine_inverse() * turned)
	return angle > 0.0


## How far a place `off` from the shoulder must come back along the unit `back` for an arm of
## `length` to reach it: 0 when it reaches, else the nearest point of that line the arm reaches.
static func pull(off: Vector3, back: Vector3, length: float) -> float:
	if off.length() <= length:
		return 0.0
	var along := off.dot(back)
	var beside := off.length_squared() - along * along
	return -along - sqrt(maxf(length * length - beside, 0.0))


## A node's transform in the space of `ancestor`, one of its parents, from the transforms between:
## no global transform is asked for while the skeleton updates (the pistol's attachment follows the
## skeleton a frame late).
static func between(node: Node3D, ancestor: Node) -> Transform3D:
	var xf := node.transform
	var above := node.get_parent() as Node3D
	while above != null and above != ancestor:
		xf = above.transform * xf
		above = above.get_parent() as Node3D
	return xf


## Where an elbow points, in `holder`'s space: its `pole` marker, moved toward `left` (the right
## elbow's `RightPoleLeft`, a child of `holder`) by `side`, the gun's share on the left shoulder.
static func pole(holder: Node3D, pole: Node3D, left: Node3D, side: float) -> Vector3:
	var at := pole.position if pole.get_parent() == holder else between(pole, holder).origin
	return at if side <= 0.0 or left == null else at.lerp(left.position, side)
