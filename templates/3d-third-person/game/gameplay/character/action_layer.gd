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

# Seconds within which a clip counts as ending (a frame's time adds up to the clip's length only
# to rounding).
const _END_SLACK := 0.0001
# Frames a carried clip that has run out holds its last frame after the body machine has left the
# state the clip began in (the machine draws a new state a frame or two after it reports it), and
# the most frames it holds at all.
const _HOLD_AFTER := 3
const _HOLD_MOST := 12

## The clip that played last.
var clip: StringName = &""
## True when the clip that plays now (or played last) is on the upper body alone.
var upper_only := false
## True while an action played on the frame before (its end is said once).
var was_active := false
## True when the clip that plays now (or played last) came in with no cross-fade, the momentum
## blend carrying the drawn pose into its first frame (`play_carried()`: lying down, getting up).
var carried := false
## Counts every clip played and every one stopped or ended by this layer: the momentum blend starts
## again from the drawn pose when it moves while a carried clip is involved (`carried_key()`).
var serial := 0

# Seconds the clip that plays now has left, as `tick()` counts them.
var _left := 0.0
# The body state the clip began in, the frames it has held its last frame and the frames since the
# machine left that state while it held (`_waits()`).
var _from_state: StringName = &""
var _held := 0
var _since := 0
var _clip_node: AnimationNodeAnimation
var _one_shot: AnimationNodeOneShot


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
	_one_shot = action


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
	_fade_in(animation, false)
	_clip_node.animation = clip_name
	var length := animation.animation_player.get_animation(clip_name).length
	var scale := length / duration if duration > 0.0 else 1.0
	tree.set(_P_SCALE, scale)
	tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_left = duration if duration > 0.0 else length
	_from_state = animation.body_state()
	_held = 0
	_since = _HOLD_AFTER + 1
	serial += 1


## Plays `clip_name` once over the whole body in `duration` seconds, at full weight from its first
## frame: the one-shot's fade-in would show the state under it first (the prone idle under the
## to-prone clip, upright to lying in a frame: gdstudio #1568), so `MomentumBlend` carries the
## drawn pose into the clip instead (`carried`). For a clip that starts on the pose the body is in
## or near (going down from a crouch, getting up from lying).
func play_carried(animation: CharacterAnimation, clip_name: StringName, duration: float) -> void:
	play(animation, clip_name, duration, false)
	_fade_in(animation, true)


## Stops the action clip on `animation`'s tree early.
func stop(animation: CharacterAnimation) -> void:
	if animation.tree != null:
		animation.tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		UseLayer.end(animation)
		serial += 1
	_left = 0.0


## Counts `delta` seconds off the clip that plays (called before the tree moves on by them) and,
## for a carried clip that would end within them, ends it now and returns its name (else `&""`):
## its last frame hands over to the state under it through the momentum blend as its first did
## (gdstudio #1576), never through the one-shot's fade-out, which drew the crouch idle at the end of
## getting up rising into the standing idle in 0.1 s. While the state under it is still the one the
## clip began in (the prone idle under getting up: the machine changes on the tick the clip ends
## and draws the change a frame or two later), the clip holds its last frame instead: a hand-off
## to the lying pose for those frames moved a toe 0.18 m in a frame. With `followed` another clip
## takes over at once (`StanceAnimation.follows()`), so nothing under it shows and it never holds.
func tick(animation: CharacterAnimation, delta: float, followed := false) -> StringName:
	if _left <= 0.0:
		return &""
	_left -= delta
	if not carried or upper_only or _left > _END_SLACK:
		return &""
	if not followed and _waits(animation):
		_left = _END_SLACK * 2.0
		animation.tree.set(_P_SCALE, 0.0)
		return &""
	stop(animation)
	return clip


## A key of the carried clip that plays now (its play's `serial`), -1 when none does: it changes
## as a carried clip starts, is replaced or ends, for the momentum blend (`MomentumBlend`).
func carried_key() -> int:
	return serial if carried and _left > 0.0 and not upper_only else -1


## True while the action clip plays on `tree`.
func is_active(tree: AnimationTree) -> bool:
	return tree != null and tree.get(_P_ACTIVE)


# True while a carried clip that has run out holds its last frame for the state under it.
func _waits(animation: CharacterAnimation) -> bool:
	_held += 1
	if _held > _HOLD_MOST:
		return false
	if animation.body_state() == _from_state:
		_since = 0
		return true
	_since += 1
	return _since <= _HOLD_AFTER


# The one-shot's fades: none for a carried clip (the momentum blend carries both ends),
# `action_blend_time` for the rest.
func _fade_in(animation: CharacterAnimation, carry: bool) -> void:
	carried = carry
	if _one_shot != null:
		_one_shot.fadein_time = 0.0 if carry else animation.action_blend_time
		_one_shot.fadeout_time = 0.0 if carry else animation.action_blend_time
