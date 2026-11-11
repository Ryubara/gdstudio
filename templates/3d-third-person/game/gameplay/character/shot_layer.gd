class_name ShotLayer
extends RefCounted
## The part of `CharacterAnimation`'s weapon layer that plays a shot's clip, either over the pose
## under it (a punch) or added to it (`WeaponDef.shoot_additive`, the pistol's and the rifle's
## recoil): added, the clip counts as its difference from its own first frame, which is the aim
## pose it was made on, so the same recoil rocks the body wherever the character aims.

const BASE := "ShootBase"
const BASE_SCALE := "ShootBaseScale"
const DELTA := "ShootDelta"
const _P_BASE_SCALE := StringName("parameters/%s/scale" % BASE_SCALE)
const _P_DELTA := StringName("parameters/%s/sub_amount" % DELTA)


## Connects the shot's clip (the node `scale`, the clip under its time scale) to the one-shot
## `shoot` of `root`. With `added`, the one-shot adds, and what it adds is the clip less `first`
## (the same clip, held on its first frame). Returns `added`.
static func wire(
	root: AnimationNodeBlendTree,
	shoot: AnimationNodeOneShot,
	shoot_name: StringName,
	scale: StringName,
	first: AnimationNodeAnimation,
	added: bool
) -> bool:
	if not added:
		root.connect_node(shoot_name, 1, scale)
		return false
	shoot.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
	root.add_node(BASE, first, Vector2(400, 900))
	root.add_node(BASE_SCALE, AnimationNodeTimeScale.new(), Vector2(600, 900))
	root.add_node(DELTA, AnimationNodeSub2.new(), Vector2(700, 800))
	root.connect_node(BASE_SCALE, 0, BASE)
	root.connect_node(DELTA, 0, scale)
	root.connect_node(DELTA, 1, BASE_SCALE)
	root.connect_node(shoot_name, 1, DELTA)
	return true


## Holds the first frame still and takes all of it off the shot, on a tree wired with `added`.
static func drive(tree: AnimationTree, added: bool) -> void:
	if added:
		tree.set(_P_BASE_SCALE, 0.0)
		tree.set(_P_DELTA, 1.0)


## The filter paths of the given bones and every bone below each of them, as the clips' tracks
## name them (`Armature/Skeleton3D:spine_01`), on the first skeleton under `rig`; a name the
## skeleton does not have is left out. Kept here so the tree's script stays within its size.
static func bone_paths(rig: Node, roots: Array) -> Array[NodePath]:
	var found: Array[NodePath] = []
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
