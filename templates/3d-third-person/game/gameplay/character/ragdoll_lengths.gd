class_name RagdollLengths
extends SkeletonModifier3D
## Holds every bone a flinch simulates at its rest distance from its parent, its turn left as the
## body gives it. A flinch hands a few limbs to their physical bodies while the clip goes on with
## the rest, and some bones between two bodies have none of their own (the clavicles, the neck):
## the clip moves them, but the joint holds the next body where the rest pose had it, so the skin
## between them stretched by as much as the clip moved them, 10 to 15 cm in a hit clip (gdstudio
## #1338). A turn is what a flinch shows; a bone's length never changes in a person.
##
## `HitReaction` puts it right after the ragdoll's simulator (and its drawing) when a flinch
## starts, names the flinch's bones and turns it on, and turns it off when the flinch ends. It
## does nothing while the whole body is limp: a death has every body and keeps the bones apart
## by its joints alone.

## The name of the node, on the skeleton after the ragdoll's simulator.
const NODE_NAME := &"RagdollLengths"

## The skeleton bones held at their rest distance (the flinch's).
var bones := PackedInt32Array()


## Puts `current` (made again when null, or freed with an old skeleton) on `simulator`'s skeleton
## after the simulator and its drawing, and returns it; null when `simulator` has no skeleton.
## `current` is untyped: a typed argument refuses a freed object before the check could see it.
static func place(current: Variant, simulator: PhysicalBoneSimulator3D) -> RagdollLengths:
	var lengths: RagdollLengths = current if is_instance_valid(current) else null
	var skeleton := simulator.get_parent() as Skeleton3D if simulator != null else null
	if skeleton == null:
		return lengths
	if lengths == null:
		lengths = RagdollLengths.new()
		lengths.name = NODE_NAME
		lengths.active = false
	if lengths.get_parent() != skeleton:
		if lengths.get_parent() != null:
			lengths.get_parent().remove_child(lengths)
		skeleton.add_child(lengths)
	var after := simulator.get_index()
	var drawing := skeleton.get_node_or_null(NodePath(String(RagdollDrawing.NODE_NAME)))
	if drawing != null:
		after = maxi(after, drawing.get_index())
	if lengths.get_index() != after + 1:
		skeleton.move_child(lengths, after + (1 if lengths.get_index() > after else 0))
	return lengths


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in bones:
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_rest(bone).origin)
