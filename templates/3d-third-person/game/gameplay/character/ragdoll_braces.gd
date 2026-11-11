class_name RagdollBraces
extends RefCounted
## The extra joints that hold a `CharacterRagdoll`'s limbs in their limits: copies of each bone's
## own joint (the same frames and limits between the same two bodies), made on the physics server.
##
## Jolt solves every joint `velocity_steps` times a step for the whole project (10, then 2
## position steps), too few for a light limb under a falling trunk, and Godot 4.7.2 keeps Jolt's
## per-joint step override out of reach of scripts. A copy of a joint is solved again in every
## step, so N joints hold the limb like N times the steps would, for these joints only. The
## copies are made round by round over the whole body, not limb after limb: Jolt solves joints in
## the order they were made and the last one solved wins, so a body braced limb after limb holds
## its last limbs and lets the first give way (docs/engines/godot/ragdoll.md#limits).
##
## `build` works out every copy once (its bodies, its frames and its limits, in the order they are
## made) and `remake` makes them from that: a set of bones the `RagdollPool` hands to another
## character makes its copies again from the plan, in a third of the time working them out takes.

## How many of the joints are hinges (elbows, knees) and cones (the rest).
var hinges := 0
var cones := 0
var _joints: Array[RID] = []
# The plan, one entry a copy in the order they are made: the two bodies, the joint's frame in each,
# whether it is a hinge, and its two limits (a hinge's upper and lower, a cone's swing and twist).
var _parents: Array[RID] = []
var _children: Array[RID] = []
var _in_parents: Array[Transform3D] = []
var _in_children: Array[Transform3D] = []
var _is_hinge: Array[bool] = []
var _first := PackedFloat64Array()
var _second := PackedFloat64Array()


func is_empty() -> bool:
	return _joints.is_empty()


## True when there is a plan to `remake` the copies from.
func has_plan() -> bool:
	return not _parents.is_empty()


## Makes `hinge_passes - 1` copies of every hinge and `cone_passes - 1` of every cone of
## `CharacterRagdoll.BODIES`. `bones` are the bodies by bone, `posed` where each body was when its
## joint was made (the skeleton's space), `parents` the body each bone hangs from (empty for the
## root), `joint_range` the ragdoll's share of a person's range.
func build(
	bones: Dictionary[StringName, PhysicalBone3D],
	posed: Dictionary[StringName, Transform3D],
	parents: Dictionary[StringName, StringName],
	hinge_passes: int,
	cone_passes: int,
	joint_range: float
) -> void:
	_clear_plan()
	for round_index in maxi(hinge_passes, cone_passes) - 1:
		for entry: Dictionary in CharacterRagdoll.BODIES:
			var up: StringName = parents.get(entry.bone, &"")
			if up == &"":
				continue
			var hinge: bool = entry.joint == &"hinge" and round_index < hinge_passes - 1
			var cone: bool = entry.joint == &"cone" and round_index < cone_passes - 1
			if not hinge and not cone:
				continue
			var child := bones[entry.bone]
			# The joint's frame in each body, at the pose it was made in.
			var in_child := child.joint_offset
			_parents.append(bones[up].get_rid())
			_children.append(child.get_rid())
			_in_children.append(in_child)
			_in_parents.append(posed[up].affine_inverse() * posed[entry.bone] * in_child)
			_is_hinge.append(hinge)
			if hinge:
				# Made at the middle of its range, so its limits are the same each way.
				var bend: float = (entry.range.y - entry.range.x) / 2.0 * joint_range
				var half := deg_to_rad(minf(bend, 170.0))
				_first.append(half)
				_second.append(-half)
			else:
				# The swing span on both axes and the twist each way, in radians.
				_first.append(deg_to_rad(minf(entry.swing * joint_range, 175.0)))
				_second.append(deg_to_rad(minf(entry.twist * joint_range, 175.0)))
	remake()


## Makes the copies from the plan `build` worked out (between the same bodies).
func remake() -> void:
	free_all()
	for index in _parents.size():
		var joint := PhysicsServer3D.joint_create()
		if _is_hinge[index]:
			PhysicsServer3D.joint_make_hinge(
				joint, _parents[index], _in_parents[index], _children[index], _in_children[index]
			)
			PhysicsServer3D.hinge_joint_set_flag(
				joint, PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT, true
			)
			PhysicsServer3D.hinge_joint_set_param(
				joint, PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER, _first[index]
			)
			PhysicsServer3D.hinge_joint_set_param(
				joint, PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER, _second[index]
			)
			hinges += 1
		else:
			PhysicsServer3D.joint_make_cone_twist(
				joint, _parents[index], _in_parents[index], _children[index], _in_children[index]
			)
			PhysicsServer3D.cone_twist_joint_set_param(
				joint, PhysicsServer3D.CONE_TWIST_JOINT_SWING_SPAN, _first[index]
			)
			PhysicsServer3D.cone_twist_joint_set_param(
				joint, PhysicsServer3D.CONE_TWIST_JOINT_TWIST_SPAN, _second[index]
			)
			cones += 1
		_joints.append(joint)


## Frees every copy (the plan stays); call it before the bodies go.
func free_all() -> void:
	for joint: RID in _joints:
		PhysicsServer3D.free_rid(joint)
	_joints.clear()
	hinges = 0
	cones = 0


func _clear_plan() -> void:
	_parents.clear()
	_children.clear()
	_in_parents.clear()
	_in_children.clear()
	_is_hinge.clear()
	_first.clear()
	_second.clear()
