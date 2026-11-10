extends SkeletonModifier3D
## Turns the spine about the model's up axis after the clip, split evenly over `spine_01`,
## `spine_02` and `spine_03`; a negative angle brings the left shoulder forward, the stance a
## two-handed long gun needs so the left arm reaches the fore-end. Used by the rifle hold study
## (`rifle_hold_study.gd`); a weapon system can do the same with its own modifier.

const BONES: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]

## The whole turn, in degrees, about the model's up axis.
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var degrees := -30.0


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var turn := Basis(Vector3.UP, deg_to_rad(degrees / BONES.size()))
	for bone_name in BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
		var turned := Transform3D(turn * pose.basis, pose.origin)
		skeleton.set_bone_pose(bone, parent.affine_inverse() * turned)
