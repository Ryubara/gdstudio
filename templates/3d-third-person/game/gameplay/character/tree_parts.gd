class_name TreeParts
extends RefCounted
## The small pieces every part of the `CharacterAnimation`'s tree is built from: a clip node, and
## the filter paths of a set of bones and every bone below them. Static: it keeps nothing.


## A clip node that plays `clip`.
static func clip(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


## The filter paths of the given bones and every bone below each of them, as the clips' tracks name
## them (`Armature/Skeleton3D:spine_01`), on the rig `player` plays its clips on; a name the
## skeleton does not have is left out.
static func bone_paths(player: AnimationPlayer, roots: Array) -> Array[NodePath]:
	var found: Array[NodePath] = []
	var rig := player.get_node_or_null(player.root_node)
	if rig == null:
		return found
	var skeletons := rig.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return found
	var skeleton := skeletons[0] as Skeleton3D
	var starts := PackedInt32Array()
	for root: StringName in roots:
		var start := skeleton.find_bone(root)
		if start >= 0:
			starts.append(start)
	var where := rig.get_path_to(skeleton)
	for bone in skeleton.get_bone_count():
		var cursor := bone
		while cursor >= 0 and not starts.has(cursor):
			cursor = skeleton.get_bone_parent(cursor)
		if cursor >= 0:
			found.append(NodePath("%s:%s" % [where, skeleton.get_bone_name(bone)]))
	return found
