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
