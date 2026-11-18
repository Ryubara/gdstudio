class_name CharacterGait
extends RefCounted
## What `CharacterAnimation` does to fit its gaits to the body's real motion (gdstudio #1158),
## kept apart so the tree's script stays one size: the speed matching of the ground and crouch
## blend spaces (`GaitBlend`), the transitions (`GaitTransitions`), the momentum blend between body
## states (`MomentumBlend`) and the lean (`GaitLean`), each switched and tuned by
## `CharacterAnimation.gait_settings` (`GaitSettings`; `gait_settings.tres` for the template's
## characters). Cosmetic: worked out on each machine from the body it draws, never sent.

## The defaults, for a node with no settings.
const DEFAULTS := preload("res://gameplay/character/gait_settings.tres")

## Frames more the momentum blend starts again on into the crouch (`extra_settle()`).
const CROUCH_SETTLE := 2

var blend := GaitBlend.new()
var transitions := GaitTransitions.new()
var jump := JumpAnimation.new()  # the take-off, the air and the landing (gdstudio #1371)
var lean := GaitLean.new()
var momentum: MomentumBlend
# The body state the momentum blend last started for (`extra_settle()`).
var _settled_from: StringName = &""


## The settings in use: `animation`'s, else the template's defaults.
static func settings_of(animation: CharacterAnimation) -> GaitSettings:
	var own := animation.gait_settings if animation != null else null
	return own if own != null else DEFAULTS


## Builds the ground state's blend space on `idle` (the idle point).
func build_ground(
	animation: CharacterAnimation, idle: AnimationRootNode
) -> AnimationNodeBlendSpace1D:
	_take(animation)
	return blend.build_ground(animation, idle)


func build_crouch(animation: CharacterAnimation) -> AnimationNodeBlendSpace1D:
	_take(animation)
	return blend.build_crouch(animation)


## Seconds a body state cross-fades into another: none when the momentum blend carries the change.
func xfade(animation: CharacterAnimation) -> float:
	return 0.0 if settings_of(animation).momentum_blend else animation.blend_time


## Adds what the built tree `root` needs beyond the states: the transition state in `machine`, the
## lean between the machine and the weapon layer, and (in the game) the momentum blend on the
## skeleton.
func decorate(
	animation: CharacterAnimation, root: AnimationNodeBlendTree, machine: AnimationNodeStateMachine
) -> void:
	_take(animation)
	transitions.stop()
	machine.add_node(GaitTransitions.STATE, transitions.build_state(), Vector2(400, 260))
	for state: StringName in [CharacterAnimation.GROUND, CharacterAnimation.CROUCH]:
		for pair: Array in [[state, GaitTransitions.STATE], [GaitTransitions.STATE, state]]:
			var link := AnimationNodeStateMachineTransition.new()
			link.xfade_time = xfade(animation)
			machine.add_transition(pair[0], pair[1], link)
	lean.add_to(root, &"Locomotion", &"Armed", animation.animation_player, animation.idle_clip)
	if Engine.is_editor_hint():
		return
	_attach_momentum(animation)


## After the tree is set to `root`: the parameters set once, and the helper bones' tracks
## switched off or on (`HelperTracks`, by `GaitSettings.helper_tracks`).
func after_build(animation: CharacterAnimation) -> void:
	if animation.tree != null and animation.tree.tree_root != null:
		transitions.hold(animation.tree, animation.animation_player)
	if settings_of(animation).helper_tracks:
		HelperTracks.unmute(animation.animation_player)
	else:
		HelperTracks.mute(animation.animation_player)


## One frame: the spaces' speed and paces, the transitions, the jump and the lean.
func drive(
	animation: CharacterAnimation,
	playback: AnimationNodeStateMachinePlayback,
	speed: float,
	delta: float
) -> void:
	blend.drive(animation, speed, delta)
	if playback != null:
		transitions.step(animation, blend, playback, delta)
		jump.step(animation, blend, playback)
	lean.drive(animation.tree, animation.character, delta)


## The state `CharacterAnimation` should travel to when it asks for `state`.
func route(state: StringName) -> StringName:
	return jump.route(transitions.route(state), blend)


## Adds the jump's states (`JumpAnimation`: the take-off, the air, the landing) to `machine`.
func add_jump(animation: CharacterAnimation, machine: AnimationNodeStateMachine) -> void:
	_take(animation)
	jump.add_states(animation, machine)


## What the momentum blend watches: it starts from the drawn pose each time this changes.
func pose_key(animation: CharacterAnimation) -> Vector2i:
	var state := animation.body_state()
	return Vector2i(hash(state), transitions.serial)


## Whether the momentum blend carries the drawn pose's speed into the state it starts for (false
## for a take-off: `JumpAnimation.carries_speed()`).
func carries_speed(animation: CharacterAnimation) -> bool:
	return jump.carries_speed(animation.body_state())


## Frames more than `MomentumBlend.SETTLE_FRAMES` the momentum blend starts again after a change
## (`JumpAnimation.extra_settle()`), and `CROUCH_SETTLE` more into the crouch and from it to the
## ground: those poses reach the skeleton a frame or two later than the blend's own frames; a stop
## cut by a crouch moved a toe 0.25 m in one frame (gdstudio #1565), and standing up from a crouch
## walk into a jog a hand 0.20 m on the fourth frame (gdstudio #1576). Not into lying down: each
## start holds the drawn pose back, and the to-prone clip's arms then caught up 0.25 m in a frame.
## Called once a change.
func extra_settle(animation: CharacterAnimation) -> int:
	var state := animation.body_state()
	var crouch := state == CharacterAnimation.CROUCH
	crouch = (
		crouch
		or (_settled_from == CharacterAnimation.CROUCH and state == CharacterAnimation.GROUND)
	)
	_settled_from = state
	return jump.extra_settle(state) + (CROUCH_SETTLE if crouch else 0)


func _take(animation: CharacterAnimation) -> void:
	var settings := settings_of(animation)
	blend.settings = settings
	transitions.settings = settings
	jump.settings = settings
	lean.settings = settings


# The momentum blend as the skeleton's first modifier, made once a skeleton and switched by the
# settings (gone when they turn it off).
func _attach_momentum(animation: CharacterAnimation) -> void:
	var settings := settings_of(animation)
	var skeleton := animation.model.skeleton() if is_instance_valid(animation.model) else null
	if momentum != null and is_instance_valid(momentum) and momentum.get_parent() != skeleton:
		momentum.queue_free()
		momentum = null
	if not settings.momentum_blend or skeleton == null:
		if momentum != null and is_instance_valid(momentum):
			momentum.queue_free()
		momentum = null
		return
	if momentum == null or not is_instance_valid(momentum):
		momentum = MomentumBlend.new()
		momentum.name = &"MomentumBlend"
		skeleton.add_child(momentum, false, Node.INTERNAL_MODE_FRONT)
	momentum.animation = animation
	momentum.half_life = settings.momentum_half_life
	momentum.speed_limit = deg_to_rad(settings.momentum_speed_limit)
