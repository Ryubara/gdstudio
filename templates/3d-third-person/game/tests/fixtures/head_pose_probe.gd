class_name HeadPoseProbe
extends SkeletonModifier3D
## The last modifier on a skeleton in a test (kit #1334): each drawn frame it records the head's
## turn against the neck it sits on, as the skin gets it, so a test can see a head rolled or
## pitched off the neck's line, or one that shifts from frame to frame while nothing moves.
##
## The turn is read against the rest pose: in the rest pose the head sits on the neck's line, so
## the head's turn on the neck now, less its turn there at rest, is how far it is off that line.
## `pitch` is about the neck's side axis (positive tips the face down), `roll` about its forward
## axis (positive leans the head to the character's right), `yaw` about its up axis, in degrees.

## Each drawn frame outside the physics step: the head's (pitch, roll, yaw) off the neck's line.
var turns := PackedVector3Array()
## The same for the neck on the chest (`spine_03`).
var neck_turns := PackedVector3Array()
## The head's turn off its rest in the model's space (how it sits in the world, the body's facing
## taken out).
var model_turns := PackedVector3Array()
## The chest's (`spine_03`) turn off its rest in the model's space.
var chest_turns := PackedVector3Array()
## With a layer: each frame, degrees between the way the head faces and the way from it to the
## layer's aim point.
var misses := PackedFloat32Array()
## With a layer and a weapon whose head goes to its sights (`WeaponDef.AimHead.SIGHT`): each
## frame, metres between the head's eye and the weapon's sight line.
var eye_offs := PackedFloat32Array()
## The aim layer whose aim point `misses` reads, or null.
var layer: AimLayer
## The head's whole turn on the neck each frame (for the frame-to-frame change).
var rotations: Array[Quaternion] = []

var _head := -1
var _neck := -1
var _chest := -1
var _rest := Quaternion.IDENTITY
var _neck_rest := Quaternion.IDENTITY


## Puts a probe last on `skeleton`, on its `Head` and `neck_01`.
static func attach(skeleton: Skeleton3D) -> HeadPoseProbe:
	var probe := HeadPoseProbe.new()
	probe.name = &"HeadPoseProbe"
	skeleton.add_child(probe)
	return probe


func clear() -> void:
	eye_offs.clear()
	turns.clear()
	neck_turns.clear()
	model_turns.clear()
	chest_turns.clear()
	misses.clear()
	rotations.clear()


## The largest of `turns` by its absolute pitch (x) and roll (y), from frame `from` on.
func largest(from := 0) -> Vector2:
	var most := Vector2.ZERO
	for index in range(from, turns.size()):
		most.x = maxf(most.x, absf(turns[index].x))
		most.y = maxf(most.y, absf(turns[index].y))
	return most


## The largest change of the head's turn on the neck between two drawn frames, in degrees.
func largest_step(from := 0) -> float:
	var most := 0.0
	for index in range(maxi(from, 1), rotations.size()):
		most = maxf(most, rad_to_deg(rotations[index - 1].angle_to(rotations[index])))
	return most


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or Engine.is_in_physics_frame():
		return
	if _head < 0:
		_head = skeleton.find_bone(&"Head")
		_neck = skeleton.find_bone(&"neck_01")
		if _head < 0 or _neck < 0:
			return
		var rest_head := skeleton.get_bone_global_rest(_head).basis.get_rotation_quaternion()
		var rest_neck := skeleton.get_bone_global_rest(_neck).basis.get_rotation_quaternion()
		_rest = rest_neck.inverse() * rest_head
		_chest = skeleton.get_bone_parent(_neck)
		var rest_chest := skeleton.get_bone_global_rest(_chest).basis.get_rotation_quaternion()
		_neck_rest = rest_chest.inverse() * rest_neck
	var head := _global(skeleton, _head)
	var neck := _global(skeleton, _neck)
	var chest := _global(skeleton, _chest)
	var on_neck := neck.inverse() * head
	rotations.append(on_neck)
	turns.append(_angles(skeleton, _neck, on_neck * _rest.inverse()))
	neck_turns.append(_angles(skeleton, _chest, chest.inverse() * neck * _neck_rest.inverse()))
	var rest_head := skeleton.get_bone_global_rest(_head).basis.get_rotation_quaternion()
	model_turns.append(_axes(Basis(head * rest_head.inverse())))
	var rest_chest := skeleton.get_bone_global_rest(_chest).basis.get_rotation_quaternion()
	chest_turns.append(_axes(Basis(chest * rest_chest.inverse())))
	if layer != null:
		var place := skeleton.global_transform * skeleton.get_bone_global_pose(_head)
		var facing := skeleton.global_basis * (Basis(head * rest_head.inverse()) * Vector3.BACK)
		var toward := layer.aim_point(Engine.get_physics_interpolation_fraction()) - place.origin
		misses.append(rad_to_deg(facing.angle_to(toward)))
		# With a weapon whose head goes to its sights: how far the eye is off the sight line.
		var looking := layer.head_modifier()
		if looking != null and looking.eye != null and is_instance_valid(looking.eye):
			var sights := skeleton.global_transform.affine_inverse() * looking.eye.global_transform
			var off := looking.eye_place(skeleton) - sights.origin
			var line := -sights.basis.z.normalized()
			eye_offs.append((off - line * off.dot(line)).length())


func _global(skeleton: Skeleton3D, bone: int) -> Quaternion:
	return skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()


# A turn in `parent`'s frame as (pitch, roll, yaw) in the model's axes (+Y up, +Z ahead, +X the
# character's left), read by putting the parent back at its rest turn.
func _angles(skeleton: Skeleton3D, parent: int, turn: Quaternion) -> Vector3:
	var rest := skeleton.get_bone_global_rest(parent).basis.get_rotation_quaternion()
	return _axes(Basis(rest * turn * rest.inverse()))


func _axes(turned: Basis) -> Vector3:
	# Yaw about up first, then the pitch about the turned side axis, then the roll about the
	# turned forward axis (Euler YXZ), so a head turned to the side and tipped reads no roll.
	var euler := turned.get_euler(EULER_ORDER_YXZ)
	return Vector3(rad_to_deg(euler.x), rad_to_deg(euler.z), rad_to_deg(euler.y))
