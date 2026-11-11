class_name DrawnPoseProbe
extends SkeletonModifier3D
## The last modifier on a skeleton in a test: each time the modifiers run (a drawn frame), it
## records where one bone is drawn in the world, against where its physical body is drawn, so a
## test sees the pose the skin gets, which the skeleton forgets after the frame.

## The bone to record and the body that moves it.
var bone := -1
var body: PhysicalBone3D
## Each drawn frame outside the physics step: the bone's drawn world position, the body's drawn
## bone position (its interpolated transform through its offset), and the interpolation fraction.
var drawn := PackedVector3Array()
var expected := PackedVector3Array()
var fractions := PackedFloat32Array()


## Puts a probe last on `skeleton`, recording `body`'s bone.
static func attach(skeleton: Skeleton3D, with_body: PhysicalBone3D) -> DrawnPoseProbe:
	var probe := DrawnPoseProbe.new()
	probe.body = with_body
	probe.bone = with_body.get_bone_id()
	skeleton.add_child(probe)
	return probe


func clear() -> void:
	drawn.clear()
	expected.clear()
	fractions.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bone < 0 or Engine.is_in_physics_frame():
		return
	var pose := skeleton.get_bone_global_pose(bone)
	drawn.append((skeleton.get_global_transform_interpolated() * pose).origin)
	var shown := body.get_global_transform_interpolated() * body.body_offset.affine_inverse()
	expected.append(shown.origin)
	fractions.append(Engine.get_physics_interpolation_fraction())
