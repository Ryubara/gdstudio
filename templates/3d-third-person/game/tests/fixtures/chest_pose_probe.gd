class_name ChestPoseProbe
extends SkeletonModifier3D
## The last modifier on a skeleton in a test (kit #1351): each drawn frame it records how far the
## chest leans off upright, as the skin gets it, so a test can see an upper body bent double over
## a crouch while the character aims.
##
## The chest's line is the way from the chest bone (`spine_03`) to the neck (`neck_01`) in the
## model's space: its angle off the model's up is how far the chest leans, whatever the bones'
## own axes. The trunk's line runs from the hips (the parent of `spine_01`) to the neck.

## Each drawn frame outside the physics step: the chest's lean off upright, in degrees.
var chest_leans := PackedFloat32Array()
## The same for the trunk (the hips to the neck).
var trunk_leans := PackedFloat32Array()
## Each drawn frame: the chest's lean forward (positive) or back along the model's facing, in
## degrees.
var chest_pitches := PackedFloat32Array()

var _chest := -1
var _neck := -1
var _hips := -1


## Puts a probe last on `skeleton`.
static func attach(skeleton: Skeleton3D) -> ChestPoseProbe:
	var probe := ChestPoseProbe.new()
	probe.name = &"ChestPoseProbe"
	skeleton.add_child(probe)
	return probe


func clear() -> void:
	chest_leans.clear()
	trunk_leans.clear()
	chest_pitches.clear()


## The largest chest lean recorded, in degrees.
func largest() -> float:
	var most := 0.0
	for lean in chest_leans:
		most = maxf(most, lean)
	return most


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or Engine.is_in_physics_frame():
		return
	if _neck < 0:
		_chest = skeleton.find_bone(&"spine_03")
		_neck = skeleton.find_bone(&"neck_01")
		_hips = skeleton.get_bone_parent(skeleton.find_bone(&"spine_01"))
		if _chest < 0 or _neck < 0 or _hips < 0:
			_neck = -1
			return
	var neck := skeleton.get_bone_global_pose(_neck).origin
	var chest := neck - skeleton.get_bone_global_pose(_chest).origin
	var trunk := neck - skeleton.get_bone_global_pose(_hips).origin
	chest_leans.append(rad_to_deg(chest.angle_to(Vector3.UP)))
	trunk_leans.append(rad_to_deg(trunk.angle_to(Vector3.UP)))
	# The model faces +Z: a chest leaning forward has its neck ahead of it.
	chest_pitches.append(rad_to_deg(atan2(chest.z, chest.y)))
