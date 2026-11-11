class_name MannequinTwist
extends SkeletonModifier3D
## Turns the six twist bones of the prototype mannequin rig (kit #1149), which no clip keys.
##
## A limb that rolls about its own length wrings its skin thin at the joint where the roll
## starts. The rig's twist bones take the roll: `upperarm_twist_01` and `thigh_twist_01` sit at
## the shoulder and the hip and turn the limb's roll back out, so the skin there stays with the
## trunk; `lowerarm_twist_01` sits at the wrist and takes the hand's roll, so the forearm's skin
## turns little by little from the elbow to the wrist. The skin's weights run along each limb
## between the limb bone and its twist bone.
##
## The import script (`mannequin_import.gd`) adds this node under the model's `Skeleton3D`. It is
## cosmetic: without it the twist bones ride their parents and the body skins as a rig with no
## twist bones does, so a dedicated server and a far character do not need it.

const _SIDES := ["l", "r"]

## Beyond this distance (m) from the viewport's camera the bones are left at rest; 0 never skips.
@export var skip_beyond := 9.0

# [twist bone, source bone, counter the source's own roll (true) or copy its roll (false)].
var _jobs: Array = []
var _resolved: Skeleton3D
var _rested := false


func _resolve(skeleton: Skeleton3D) -> void:
	_resolved = skeleton
	_jobs.clear()
	for side: String in _SIDES:
		for limb: String in ["upperarm", "thigh"]:
			_add(skeleton, "%s_twist_01_%s" % [limb, side], "%s_%s" % [limb, side], true)
		_add(skeleton, "lowerarm_twist_01_%s" % side, "hand_%s" % side, false)


func _add(skeleton: Skeleton3D, twist: String, source: String, counter: bool) -> void:
	var twist_bone := skeleton.find_bone(twist)
	var source_bone := skeleton.find_bone(source)
	if twist_bone < 0 or source_bone < 0:
		return
	_jobs.append(
		[
			twist_bone,
			source_bone,
			counter,
			skeleton.get_bone_rest(source_bone).basis.get_rotation_quaternion(),
			skeleton.get_bone_rest(twist_bone).basis.get_rotation_quaternion()
		]
	)


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if skeleton != _resolved:
		_resolve(skeleton)
	if skip_beyond > 0.0 and _is_far(skeleton):
		if not _rested:
			for job: Array in _jobs:
				skeleton.set_bone_pose_rotation(job[0], job[4])
			_rested = true
		return
	_rested = false
	for job: Array in _jobs:
		var rest: Quaternion = job[3]
		var pose := skeleton.get_bone_pose_rotation(job[1])
		if job[2]:
			# The limb's turn from its rest, in its own axes; its roll about Y is taken back out.
			var roll := twist_about_y(rest.inverse() * pose)
			skeleton.set_bone_pose_rotation(job[0], job[4] * roll.inverse())
		else:
			# The hand's turn from its rest, in the forearm's axes; the wrist end takes its roll.
			var roll := twist_about_y(pose * rest.inverse())
			skeleton.set_bone_pose_rotation(job[0], roll * job[4])


func _is_far(skeleton: Skeleton3D) -> bool:
	var viewport := skeleton.get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return false
	return (
		camera.global_position.distance_squared_to(skeleton.global_position)
		> skip_beyond * skip_beyond
	)


## The part of `turn` that is a roll about the bone's length (its Y axis): the swing-twist split.
static func twist_about_y(turn: Quaternion) -> Quaternion:
	var roll := Quaternion(0.0, turn.y, 0.0, turn.w)
	if roll.length_squared() < 1e-12:
		return Quaternion.IDENTITY
	return roll.normalized()
