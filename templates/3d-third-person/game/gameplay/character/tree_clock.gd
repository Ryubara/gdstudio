class_name TreeClock
extends RefCounted
## Who moves the `CharacterAnimation`'s tree on: the tree itself every frame (the default, and
## always for the player), or a caller (the `AiAnimationThrottle`) through
## `CharacterAnimation.set_throttled()` and `advance()`. Throttled, the tree and the skeleton's
## modifiers move only when advanced. The animation owns one.
##
## The tree keeps its callback mode and only its own processing stops: setting
## `callback_mode_process` turns the tree off and on again, which starts its state machine over
## from the first state, a jump of the whole pose.

## True while the caller decides when the tree moves on.
var throttled := false

var _skeleton_mode := Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
var _skeleton: Skeleton3D


## Hands the clock of `animation`'s tree (and with `skeleton_too` its skeleton's modifiers) to the
## caller (`on`) or gives it back.
func hand_over(animation: CharacterAnimation, on: bool, skeleton_too: bool) -> void:
	var tree := animation.tree
	throttled = on
	animation.set_process(not on)
	runs_itself(tree, not on)
	if on:
		# A tree that has not run yet starts its state machine on its first update, and that
		# update's time is lost: start it now, so the first advance keeps all the time it is given.
		if tree.active:
			tree.advance(0.0)
		var model := animation.model
		_skeleton = model.skeleton() if skeleton_too and model != null else null
		if _skeleton != null:
			_skeleton_mode = _skeleton.modifier_callback_mode_process
			_skeleton.modifier_callback_mode_process = (
				Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
			)
		return
	if _skeleton != null and is_instance_valid(_skeleton):
		_skeleton.modifier_callback_mode_process = _skeleton_mode
	_skeleton = null


## Moves the throttled `tree`, and the skeleton's modifiers, on by `delta` seconds, once the
## parameters of the frame are set.
func step(tree: AnimationTree, delta: float) -> void:
	tree.advance(delta)
	if _skeleton != null and is_instance_valid(_skeleton):
		_skeleton.advance(delta)


## Turns `tree`'s own processing, in its callback mode, on or off (with its mode and state kept).
static func runs_itself(tree: AnimationTree, on: bool) -> void:
	var mode := tree.callback_mode_process
	var running := on and tree.active
	var idle := running and mode == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	var physics := running and mode == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	if tree.is_processing_internal() != idle:
		tree.set_process_internal(idle)
	if tree.is_physics_processing_internal() != physics:
		tree.set_physics_process_internal(physics)
