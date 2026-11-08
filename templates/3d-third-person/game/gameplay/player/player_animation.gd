class_name PlayerAnimation
extends Node
## Plays the clip for what the `Player` is doing, through an `AnimationTree` it builds: a state
## machine for the body (`ground` blends idle, walk, run and sprint by ground speed; `jump`,
## `fall`, `land` and `push` are clips of their own) and a one-shot layer on top for actions
## (interact, hit, and any clip a game asks for with `play_clip()`).
##
## The clips come from the Universal Animation Library 1 and 2, added to the `AnimationPlayer`
## as the libraries `ual1` and `ual2`. Pick another clip for a state in the inspector;
## `CharacterClips` names them all.

## An action clip started; `clip` is its name.
signal action_started(clip: StringName)
## The action clip that was playing ended.
signal action_finished(clip: StringName)

## The states of the tree's body machine, as `Player.State` maps onto them.
const GROUND := &"ground"
const JUMP := &"jump"
const FALL := &"fall"
const LAND := &"land"
const PUSH := &"push"

const _MACHINE := "Locomotion"
const _ACTION := "Action"
const _ACTION_CLIP := "ActionClip"
const _ACTION_SCALE := "ActionScale"

@export_group("Nodes")
## The player that is animated.
@export var player: Player
## The `AnimationPlayer` that holds the clip libraries.
@export var animation_player: AnimationPlayer
## The tree that is built and driven.
@export var tree: AnimationTree

@export_group("Clips")
## Standing still.
@export var idle_clip: StringName = CharacterClips.IDLE
## Walking: the blend space puts it at the walk speed.
@export var walk_clip: StringName = CharacterClips.WALK
## Running: the blend space puts it at the run speed.
@export var run_clip: StringName = CharacterClips.RUN
## Sprinting: the blend space puts it at the sprint speed.
@export var sprint_clip: StringName = CharacterClips.SPRINT
## The push off the ground.
@export var jump_clip: StringName = CharacterClips.JUMP_START
## In the air, rising or falling.
@export var air_clip: StringName = CharacterClips.AIR
## Touching down.
@export var land_clip: StringName = CharacterClips.LAND
## Walking into a prop.
@export var push_clip: StringName = CharacterClips.PUSH
## Using a door or a lever.
@export var interact_clip: StringName = CharacterClips.INTERACT
## Being hit.
@export var hit_clip: StringName = CharacterClips.HIT

@export_group("Blending")
## Seconds the body states take to blend into each other.
@export_range(0.0, 1.0, 0.01, "suffix:s") var blend_time := 0.15
## Seconds an action clip takes to blend in and out.
@export_range(0.0, 1.0, 0.01, "suffix:s") var action_blend_time := 0.1

var _machine: AnimationNodeStateMachine
var _action_clip_node: AnimationNodeAnimation
var _action_scale_node: AnimationNodeTimeScale
var _playback: AnimationNodeStateMachinePlayback
var _action_clip: StringName = &""
var _action_was_active := false


func _ready() -> void:
	if player == null or animation_player == null or tree == null:
		return
	tree.anim_player = tree.get_path_to(animation_player)
	tree.tree_root = _build_root()
	tree.active = true
	_playback = tree.get(&"parameters/%s/playback" % _MACHINE)
	_playback.start(GROUND)
	player.state_changed.connect(_on_state_changed)
	player.interacted.connect(_on_interacted)
	player.took_hit.connect(_on_hit)


func _process(_delta: float) -> void:
	if tree == null or not tree.active or _playback == null:
		return
	var speed := player.ground_speed()
	tree.set(&"parameters/%s/%s/blend_position" % [_MACHINE, GROUND], speed)
	var active: bool = tree.get(&"parameters/%s/active" % _ACTION)
	if _action_was_active and not active:
		action_finished.emit(_action_clip)
	_action_was_active = active


## The body state the tree is in now (`ground`, `jump`, `fall`, `land` or `push`).
func body_state() -> StringName:
	return _playback.get_current_node() if _playback != null else &""


## True while an action clip plays over the body.
func is_acting() -> bool:
	return tree != null and tree.get(&"parameters/%s/active" % _ACTION)


## The action clip that played last.
func last_action() -> StringName:
	return _action_clip


## Plays any clip of the libraries over the body once (`CharacterClips.SWORD_ATTACK`). With a
## `duration` above zero the clip is sped up or slowed to take that long.
func play_clip(clip: StringName, duration: float = 0.0) -> void:
	if tree == null or not animation_player.has_animation(clip):
		push_warning("PlayerAnimation: no clip called %s" % clip)
		return
	_action_clip = clip
	_action_clip_node.animation = clip
	var length := animation_player.get_animation(clip).length
	var scale := length / duration if duration > 0.0 else 1.0
	tree.set(&"parameters/%s/scale" % _ACTION_SCALE, scale)
	tree.set(&"parameters/%s/request" % _ACTION, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	action_started.emit(clip)


## Stops an action clip early.
func stop_clip() -> void:
	if tree != null:
		tree.set(&"parameters/%s/request" % _ACTION, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func _on_state_changed(state: Player.State) -> void:
	match state:
		Player.State.IDLE, Player.State.WALK, Player.State.RUN:
			_travel(GROUND)
		Player.State.JUMP:
			_travel(JUMP)
		Player.State.FALL:
			_travel(FALL)
		Player.State.LAND:
			_travel(LAND)
		Player.State.PUSH:
			_travel(PUSH)


func _on_interacted(_target: Node3D) -> void:
	play_clip(interact_clip, player.tuning.interact_time)


func _on_hit(_amount: float, _source: Node3D) -> void:
	play_clip(hit_clip, player.tuning.hit_stun_time)


func _travel(state: StringName) -> void:
	if _playback != null:
		_playback.travel(state)


func _build_root() -> AnimationNodeBlendTree:
	var root := AnimationNodeBlendTree.new()
	root.add_node(_MACHINE, _build_machine(), Vector2(0, 0))
	_action_clip_node = _clip(interact_clip)
	_action_scale_node = AnimationNodeTimeScale.new()
	root.add_node(_ACTION_CLIP, _action_clip_node, Vector2(0, 200))
	root.add_node(_ACTION_SCALE, _action_scale_node, Vector2(200, 200))
	root.connect_node(_ACTION_SCALE, 0, _ACTION_CLIP)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = action_blend_time
	action.fadeout_time = action_blend_time
	root.add_node(_ACTION, action, Vector2(400, 0))
	root.connect_node(_ACTION, 0, _MACHINE)
	root.connect_node(_ACTION, 1, _ACTION_SCALE)
	root.connect_node(&"output", 0, _ACTION)
	return root


func _build_machine() -> AnimationNodeStateMachine:
	_machine = AnimationNodeStateMachine.new()
	_machine.add_node(GROUND, _build_ground(), Vector2(200, 0))
	_machine.add_node(JUMP, _clip(jump_clip), Vector2(400, -100))
	_machine.add_node(FALL, _clip(air_clip), Vector2(600, 0))
	_machine.add_node(LAND, _clip(land_clip), Vector2(400, 100))
	_machine.add_node(PUSH, _clip(push_clip), Vector2(200, 160))
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	_machine.add_transition(&"Start", GROUND, start)
	var states := [GROUND, JUMP, FALL, LAND, PUSH]
	for from: StringName in states:
		for to: StringName in states:
			if from != to:
				_link(from, to)
	return _machine


func _link(from: StringName, to: StringName) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = blend_time
	_machine.add_transition(from, to, transition)


func _build_ground() -> AnimationNodeBlendSpace1D:
	var tuning := player.tuning
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = tuning.sprint_speed
	space.sync = true
	space.add_blend_point(_clip(idle_clip), 0.0, -1, &"idle")
	space.add_blend_point(_clip(walk_clip), tuning.walk_speed, -1, &"walk")
	space.add_blend_point(_clip(run_clip), tuning.run_speed, -1, &"run")
	space.add_blend_point(_clip(sprint_clip), tuning.sprint_speed, -1, &"sprint")
	return space


func _clip(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node
