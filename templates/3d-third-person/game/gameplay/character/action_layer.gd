class_name ActionLayer
extends RefCounted
## The action one-shot of the `CharacterAnimation`'s tree, the last layer before the output: any
## clip of the libraries played once over the whole body (interact, a vault, going prone, a clip a
## game asks for with `CharacterAnimation.play_clip()`), or over the upper body alone (a hit
## crouched, lying or sliding: `HitLayer`; using an item: `UseLayer`). Its clip runs through a time
## scale (a clip stretched to a duration) and a seek (a vault held to the body's own time:
## `VaultAnimation`). The animation owns one and says when an action starts and ends.

## The tree's nodes of the layer.
const NODE := "Action"
const CLIP := "ActionClip"
const SCALE := "ActionScale"

const _P_ACTIVE := StringName("parameters/%s/active" % NODE)
const _P_REQUEST := StringName("parameters/%s/request" % NODE)
const _P_SCALE := StringName("parameters/%s/scale" % SCALE)

## The clip that played last.
var clip: StringName = &""
## True when the clip that plays now (or played last) is on the upper body alone.
var upper_only := false
## True while an action played on the frame before (its end is said once).
var was_active := false

var _clip_node: AnimationNodeAnimation


## Adds the clip, its scale and seek and the one-shot to `root`; the one-shot's inputs are joined
## by the caller once the layers under it are there.
func add_to(animation: CharacterAnimation, root: AnimationNodeBlendTree) -> void:
	var player := animation.animation_player
	_clip_node = TreeParts.clip(animation.interact_clip)
	var scale := AnimationNodeTimeScale.new()
	root.add_node(CLIP, _clip_node, Vector2(0, 200))
	root.add_node(SCALE, scale, Vector2(200, 200))
	# A vault holds its clip to the body's own time through the seek (`VaultAnimation`).
	root.add_node(VaultAnimation.SEEK, AnimationNodeTimeSeek.new(), Vector2(100, 200))
	root.connect_node(VaultAnimation.SEEK, 0, CLIP)
	root.connect_node(SCALE, 0, VaultAnimation.SEEK)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = animation.action_blend_time
	action.fadeout_time = animation.action_blend_time
	var arms := TreeParts.bone_paths(player, [&"clavicle_l", &"clavicle_r"])
	var upper := TreeParts.bone_paths(player, [animation.upper_body_bone])
	var kept := TreeParts.bone_paths(player, [UseLayer.KEPT_ARM])
	var hips := TreeParts.bone_paths(player, [&"root", &"pelvis"])
	animation.hits.prepare(action, hips, upper, arms, kept)
	root.add_node(NODE, action, Vector2(1400, 0))


## Plays `clip_name` once on `animation`'s tree, sped up or slowed to take `duration` seconds when
## that is above zero, on the upper body alone with `upper_body` (`UseLayer`).
func play(
	animation: CharacterAnimation, clip_name: StringName, duration: float, upper_body: bool
) -> void:
	var tree := animation.tree
	# Only an upper-body action, or the first one after it, touches the filter (80 us a call).
	if upper_body or upper_only:
		var arm := TreeParts.bone_paths(animation.animation_player, [UseLayer.KEPT_ARM])
		UseLayer.begin(animation, arm, clip_name, duration, upper_body)
	upper_only = upper_body
	clip = clip_name
	_clip_node.animation = clip_name
	var length := animation.animation_player.get_animation(clip_name).length
	var scale := length / duration if duration > 0.0 else 1.0
	tree.set(_P_SCALE, scale)
	tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Stops the action clip on `animation`'s tree early.
func stop(animation: CharacterAnimation) -> void:
	if animation.tree != null:
		animation.tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		UseLayer.end(animation)


## True while the action clip plays on `tree`.
func is_active(tree: AnimationTree) -> bool:
	return tree != null and tree.get(_P_ACTIVE)
