class_name UseLayer
extends RefCounted
## Where an upper-body action clip plays (using an item: `CharacterAnimation.play_clip()` with
## `upper_body` on). It takes the spine, the head and the left arm, the bones from
## `CharacterAnimation.upper_body_bone` down less the right arm (`KEPT_ARM` down), so the legs keep
## walking and the right hand keeps the weapon layer's carry while the left hand does the work
## (the hold lets it off the weapon: `FreeHand`). It shares the action one-shot with the hit
## (`HitLayer`): the one-shot's filter is on for either, and the right arm's tracks pass the
## clip again for every action that is not an upper-body one. The hips stay the legs', so a
## `UseTurn` on the skeleton turns the chest back to where the clip has it.

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


## Starts the upper-body side of `clip` on `animation`'s character, stretched to `duration`
## seconds: the right arm kept and the chest turned as the clip's hips would have it. With
## `upper_body` off (any other action) the right arm passes the clip again and the turn ends.
static func begin(
	animation: CharacterAnimation,
	arm_paths: Array[NodePath],
	clip: StringName,
	duration: float,
	upper_body: bool
) -> void:
	keep_arm(animation.tree, arm_paths, upper_body)
	var turn := turn_of(animation, upper_body)
	if turn == null:
		return
	if not upper_body:
		turn.end()
		return
	var skeleton := turn.get_skeleton()
	var rig := animation.animation_player.get_node_or_null(animation.animation_player.root_node)
	var path := rig.get_path_to(skeleton)
	turn.begin(
		animation.animation_player.get_animation(clip), path, duration, animation.action_blend_time
	)


## The action was stopped early: the chest's turn eases out with it.
static func end(animation: CharacterAnimation) -> void:
	var turn := turn_of(animation, false)
	if turn != null:
		turn.end()


## The `UseTurn` on `animation`'s skeleton; made first among its modifiers when `make` is on.
static func turn_of(animation: CharacterAnimation, make: bool) -> UseTurn:
	if animation == null or animation.animation_player == null:
		return null
	var rig := animation.animation_player.get_node_or_null(animation.animation_player.root_node)
	if rig == null:
		return null
	var skeletons := rig.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var skeleton := skeletons[0] as Skeleton3D
	for child in skeleton.get_children(true):
		if child is UseTurn:
			return child
	if not make:
		return null
	var turn := UseTurn.new()
	turn.name = &"UseTurn"
	skeleton.add_child(turn, false, Node.INTERNAL_MODE_FRONT)
	return turn
