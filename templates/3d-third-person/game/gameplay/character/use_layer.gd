class_name UseLayer
extends RefCounted
## Where an upper-body action clip plays (using an item: `CharacterAnimation.play_clip()` with
## `upper_body` on). It takes the spine, the head and the left arm, the bones from
## `CharacterAnimation.upper_body_bone` down less the right arm (`KEPT_ARM` down), so the legs keep
## walking and the right hand keeps the weapon layer's carry while the left hand does the work
## (the hold lets it off the weapon: `FreeHand`). It shares the action one-shot with the hit
## (`HitLayer`): the one-shot's filter is on for either, and the right arm's tracks pass the
## clip again for every action that is not an upper-body one.

## The first bone of the arm that keeps the weapon layer's pose during an upper-body action.
const KEPT_ARM := &"clavicle_r"


## Lets the right arm's tracks (`arm_paths`) through the action one-shot of `tree` (`upper_body`
## off) or keeps them on the layers under it (`upper_body` on).
static func keep_arm(tree: AnimationTree, arm_paths: Array[NodePath], upper_body: bool) -> void:
	var root := tree.tree_root as AnimationNodeBlendTree if tree != null else null
	if root == null or not root.has_node(&"Action"):
		return
	var action := root.get_node(&"Action") as AnimationNodeOneShot
	if action == null:
		return
	for path in arm_paths:
		action.set_filter_path(path, not upper_body)
