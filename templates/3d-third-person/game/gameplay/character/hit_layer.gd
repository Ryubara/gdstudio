class_name HitLayer
extends RefCounted
## Where a hit's clip plays on the body. The hit clip (`CharacterClips.HIT`) is made standing, so it
## holds the whole body only in a standing body state; crouched, lying or sliding it plays on the
## upper body alone (the bones from `CharacterAnimation.upper_body_bone` down) and the hips and legs
## keep the state's pose, so a crouched body under fire stays down (gdstudio #1292). It is the
## action one-shot's filter, turned on for a hit in a low state and off for every other action.

## The body states whose hit plays on the upper body only.
const UPPER_BODY_STATES: Array[StringName] = [
	CharacterAnimation.CROUCH,
	CharacterAnimation.PRONE,
	CharacterAnimation.SLIDE_START,
	CharacterAnimation.SLIDE,
	CharacterAnimation.SLIDE_EXIT,
]


## True when a hit in the body state `state` plays on the upper body only.
static func upper_body_only(state: StringName) -> bool:
	return UPPER_BODY_STATES.has(state)


## Gives the action one-shot `action` the upper body's filter `paths` (the bones' tracks), off
## until a hit in a low state turns it on.
static func prepare(action: AnimationNodeOneShot, paths: Array[NodePath]) -> void:
	for path in paths:
		action.set_filter_path(path, true)
	action.filter_enabled = false


## Turns the filter of `tree`'s action one-shot on while a hit plays (`hit`) in a low body state
## `state`, and off otherwise: called when a hit lands and every frame after, so a body that
## crouches or stands up during the stun gets the share of the clip its new state takes.
static func follow(tree: AnimationTree, hit: bool, state: StringName) -> void:
	var root := tree.tree_root as AnimationNodeBlendTree if tree != null else null
	if root == null or not root.has_node(&"Action"):
		return
	var action := root.get_node(&"Action") as AnimationNodeOneShot
	var upper := hit and upper_body_only(state)
	if action != null and action.filter_enabled != upper:
		action.filter_enabled = upper
