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

## How many of the joints are hinges (elbows, knees) and cones (the rest).
var hinges := 0
var cones := 0
var _joints: Array[RID] = []


func is_empty() -> bool:
	return _joints.is_empty()


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
	for round_index in maxi(hinge_passes, cone_passes) - 1:
		for entry: Dictionary in CharacterRagdoll.BODIES:
			var up: StringName = parents.get(entry.bone, &"")
			if up == &"":
				continue
			var parent := bones[up]
			var child := bones[entry.bone]
			# The joint's frame in each body, at the pose it was made in.
			var in_child := child.joint_offset
			var in_parent: Transform3D = posed[up].affine_inverse() * posed[entry.bone] * in_child
			if entry.joint == &"hinge" and round_index < hinge_passes - 1:
				_joints.append(_hinge(entry, parent, in_parent, child, in_child, joint_range))
				hinges += 1
			elif entry.joint == &"cone" and round_index < cone_passes - 1:
				_joints.append(_cone(entry, parent, in_parent, child, in_child, joint_range))
				cones += 1


## Frees every copy; call it before the bodies go.
func free_all() -> void:
	for joint: RID in _joints:
		PhysicsServer3D.free_rid(joint)
	_joints.clear()
	hinges = 0
	cones = 0


# A hinge made at the middle of its range, so its limits are the same each way.
static func _hinge(
	entry: Dictionary,
	parent: PhysicalBone3D,
	in_parent: Transform3D,
	child: PhysicalBone3D,
	in_child: Transform3D,
	joint_range: float
) -> RID:
	var half := deg_to_rad(minf((entry.range.y - entry.range.x) / 2.0 * joint_range, 170.0))
	var joint := PhysicsServer3D.joint_create()
	PhysicsServer3D.joint_make_hinge(joint, parent.get_rid(), in_parent, child.get_rid(), in_child)
	PhysicsServer3D.hinge_joint_set_flag(joint, PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT, true)
	PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER, half)
	PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER, -half)
	return joint


# A cone made at its centre: the swing span on both axes and the twist each way, in radians.
static func _cone(
	entry: Dictionary,
	parent: PhysicalBone3D,
	in_parent: Transform3D,
	child: PhysicalBone3D,
	in_child: Transform3D,
	joint_range: float
) -> RID:
	var joint := PhysicsServer3D.joint_create()
	PhysicsServer3D.joint_make_cone_twist(
		joint, parent.get_rid(), in_parent, child.get_rid(), in_child
	)
	PhysicsServer3D.cone_twist_joint_set_param(
		joint,
		PhysicsServer3D.CONE_TWIST_JOINT_SWING_SPAN,
		deg_to_rad(minf(entry.swing * joint_range, 175.0))
	)
	PhysicsServer3D.cone_twist_joint_set_param(
		joint,
		PhysicsServer3D.CONE_TWIST_JOINT_TWIST_SPAN,
		deg_to_rad(minf(entry.twist * joint_range, 175.0))
	)
	return joint
