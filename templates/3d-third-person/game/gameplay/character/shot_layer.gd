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
# The one-shot's own name in the tree is `CharacterAnimation`'s (`Shoot`).
const _P_REQUEST := &"parameters/Shoot/request"


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


## Plays the shot's clip once for a shot of the weapon `hold`. A weapon with no shot clip plays
## nothing: the layer's clip node then holds the idle clip only so the tree has one, and playing
## it put the idle's upper body over a run, a sprint and a slide for the idle's whole length after
## every shot (kit #1333, the rifle before it had its own `Rifle_Shoot`).
static func fire(tree: AnimationTree, hold: WeaponDef) -> void:
	if hold == null or hold.shoot_clips.is_empty() or hold.shoot_clips[0] == &"":
		return
	tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Stops a shot's clip at once: the weapon in the hands changed, and the next one starts with no
## shot of the last one on the body.
static func stop(tree: AnimationTree) -> void:
	if tree != null and tree.tree_root != null:
		tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
