@tool
class_name PlayerAnimation
extends Node
## Plays the clip for what the `Player` is doing, through an `AnimationTree` it builds: a state
## machine for the body (`ground` blends idle, walk, run and sprint by ground speed; `crouch`
## blends the crouch idle and walk; `jump`, `fall`, `land` and `push` are clips of their own), a
## pistol layer on the upper body (the arm holds the pistol, comes up to aim by the camera's
## pitch, and recoils for a shot) and a one-shot layer on the whole body for actions (interact,
## hit, and any clip a game asks for with `play_clip()`).
##
## The clips come from the Universal Animation Library 1 and 2, added to the `AnimationPlayer`
## as the libraries `ual1` and `ual2`. Pick another clip for a state in the inspector;
## `CharacterClips` names them all.
##
## It is a `@tool` script so the editor shows the tree too: opening the player scene builds the
## same tree, so the AnimationTree panel shows its graph and the node has no warning. Only the
## building runs in the editor, never the driving (no signals, no `_process`), and the built tree
## is taken off the node while the scene is saved, so no `.tscn` holds a generated resource.
##
## It follows the `PlayerModel` too: when the character's model is replaced, it points the
## `AnimationPlayer` at the new model and builds the tree again, so a swap in the editor needs
## nothing set by hand (the editor empties the player's Root Node when the node it pointed at is
## deleted).

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
const CROUCH := &"crouch"

const _MACHINE := "Locomotion"
const _ACTION := "Action"
const _ACTION_CLIP := "ActionClip"
const _ACTION_SCALE := "ActionScale"
const _ARMED := "Armed"
const _PISTOL_IDLE := "PistolIdle"
const _AIM_POSE := "AimPose"
const _SHOOT_CLIP := "ShootClip"
const _SHOOT_SCALE := "ShootScale"
const _SHOOT := "Shoot"
const _AIM := "Aim"

@export_group("Nodes")
## The player that is animated.
@export var player: Player
## The slot that holds the character's model; the clips are played on the model it finds.
@export var model: PlayerModel
## The `AnimationPlayer` that holds the clip libraries.
@export var animation_player: AnimationPlayer
## The tree that is built and driven.
@export var tree: AnimationTree

@export_group("Clips")
## Standing still.
@export var idle_clip: StringName = CharacterClips.IDLE:
	set(value):
		idle_clip = value
		_rebuild()
## Walking: the blend space puts it at the walk speed.
@export var walk_clip: StringName = CharacterClips.WALK:
	set(value):
		walk_clip = value
		_rebuild()
## Running: the blend space puts it at the run speed.
@export var run_clip: StringName = CharacterClips.RUN:
	set(value):
		run_clip = value
		_rebuild()
## Sprinting: the blend space puts it at the sprint speed.
@export var sprint_clip: StringName = CharacterClips.SPRINT:
	set(value):
		sprint_clip = value
		_rebuild()
## The push off the ground.
@export var jump_clip: StringName = CharacterClips.JUMP_START:
	set(value):
		jump_clip = value
		_rebuild()
## In the air, rising or falling.
@export var air_clip: StringName = CharacterClips.AIR:
	set(value):
		air_clip = value
		_rebuild()
## Touching down.
@export var land_clip: StringName = CharacterClips.LAND:
	set(value):
		land_clip = value
		_rebuild()
## Crouched and standing still.
@export var crouch_idle_clip: StringName = CharacterClips.CROUCH_IDLE:
	set(value):
		crouch_idle_clip = value
		_rebuild()
## Crouch walking: the blend space puts it at the crouch speed.
@export var crouch_walk_clip: StringName = CharacterClips.CROUCH_WALK:
	set(value):
		crouch_walk_clip = value
		_rebuild()
## Walking into a prop.
@export var push_clip: StringName = CharacterClips.PUSH:
	set(value):
		push_clip = value
		_rebuild()
## Using a door or a lever.
@export var interact_clip: StringName = CharacterClips.INTERACT:
	set(value):
		interact_clip = value
		_rebuild()
## Being hit.
@export var hit_clip: StringName = CharacterClips.HIT:
	set(value):
		hit_clip = value
		_rebuild()

@export_group("Pistol")
## The pose of the upper body while the character holds the pistol and is not aiming.
@export var pistol_idle_clip: StringName = CharacterClips.PISTOL_IDLE:
	set(value):
		pistol_idle_clip = value
		_rebuild()
## Aiming level; the aim blends to the clips below by the camera's pitch.
@export var aim_clip: StringName = CharacterClips.PISTOL_AIM:
	set(value):
		aim_clip = value
		_rebuild()
## Aiming up (the camera looks `aim_pitch_range` degrees up).
@export var aim_up_clip: StringName = CharacterClips.PISTOL_AIM_UP:
	set(value):
		aim_up_clip = value
		_rebuild()
## Aiming down (the camera looks `aim_pitch_range` degrees down).
@export var aim_down_clip: StringName = CharacterClips.PISTOL_AIM_DOWN:
	set(value):
		aim_down_clip = value
		_rebuild()
## The recoil of a shot, played on the upper body.
@export var shoot_clip: StringName = CharacterClips.PISTOL_SHOOT:
	set(value):
		shoot_clip = value
		_rebuild()
## The bone where the upper body starts: it and everything below it in the skeleton (spine, arms,
## head, fingers) take the pistol layer; the legs do not.
@export var upper_body_bone: StringName = &"spine_01":
	set(value):
		upper_body_bone = value
		_rebuild()
## How far the camera looks up or down for the full aim up or aim down pose.
@export_range(5.0, 80.0, 0.5, "suffix:deg") var aim_pitch_range := 45.0:
	set(value):
		aim_pitch_range = value
		_rebuild()
## How fast the recoil plays (1 is the clip's own speed).
@export_range(0.2, 4.0, 0.05) var shoot_speed := 1.6

@export_group("Blending")
## Seconds the body states take to blend into each other.
@export_range(0.0, 1.0, 0.01, "suffix:s") var blend_time := 0.15:
	set(value):
		blend_time = value
		_rebuild()
## Seconds an action clip takes to blend in and out.
@export_range(0.0, 1.0, 0.01, "suffix:s") var action_blend_time := 0.1:
	set(value):
		action_blend_time = value
		_rebuild()

var _machine: AnimationNodeStateMachine
var _ground: AnimationNodeBlendSpace1D
var _crouch: AnimationNodeBlendSpace1D
var _ground_speeds: Array = []
var _shoot_scale_node: AnimationNodeTimeScale
var _action_clip_node: AnimationNodeAnimation
var _action_scale_node: AnimationNodeTimeScale
var _playback: AnimationNodeStateMachinePlayback
var _action_clip: StringName = &""
var _action_was_active := false


func _ready() -> void:
	if player == null or animation_player == null or tree == null:
		return
	if model != null:
		model.rig_changed.connect(_on_rig_changed)
		_follow_rig()
	_build()
	if player.tuning != null:
		player.tuning.changed.connect(_sync_ground_speeds)
	if Engine.is_editor_hint():
		return
	tree.active = true
	_playback = tree.get(&"parameters/%s/playback" % _MACHINE)
	_playback.start(GROUND)
	player.state_changed.connect(_on_state_changed)
	player.interacted.connect(_on_interacted)
	player.took_hit.connect(_on_hit)
	if player.weapon != null:
		player.weapon.fired.connect(_on_shot)


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	# The tree is built in code, so a scene file must not keep a copy: take it off the node
	# while the scene (this one, or one that instances it) is written, and build it again after.
	if what == NOTIFICATION_EDITOR_PRE_SAVE and tree != null:
		tree.tree_root = null
		tree.anim_player = NodePath()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_rebuild()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or tree == null or not tree.active or _playback == null:
		return
	_sync_ground_speeds()
	var speed := player.ground_speed()
	tree.set(&"parameters/%s/%s/blend_position" % [_MACHINE, GROUND], speed)
	tree.set(&"parameters/%s/%s/blend_position" % [_MACHINE, CROUCH], speed)
	_drive_pistol()
	var active: bool = tree.get(&"parameters/%s/active" % _ACTION)
	if _action_was_active and not active:
		action_finished.emit(_action_clip)
	_action_was_active = active


## The body state the tree is in now (`ground`, `crouch`, `jump`, `fall`, `land` or `push`).
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


## How much of the upper body the pistol holds (0 none, 1 all of it): the holding pose, then the
## aim over it.
func pistol_weights() -> Vector2:
	if tree == null:
		return Vector2.ZERO
	return Vector2(
		tree.get(&"parameters/%s/blend_amount" % _ARMED),
		tree.get(&"parameters/%s/blend_amount" % _AIM)
	)


## Where the aim pose is on its pitch axis, in degrees (negative looks down).
func aim_pitch() -> float:
	return tree.get(&"parameters/%s/blend_position" % _AIM_POSE) if tree != null else 0.0


## Stops an action clip early.
func stop_clip() -> void:
	if tree != null:
		tree.set(&"parameters/%s/request" % _ACTION, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


# Points the animation player at the model the slot holds: the clips' tracks
# (`Armature/Skeleton3D:<bone>`) are paths from the model's root. A model that has no such path
# gets no root at all, so the engine logs one warning for the player instead of one for every
# bone of every clip (and the tree is switched off in the game).
func _follow_rig() -> void:
	if animation_player == null or model == null:
		return
	var rig := model.rig()
	if rig == null or not rig.is_inside_tree():
		return
	var path := animation_player.get_path_to(rig) if _fits(rig) else NodePath()
	if animation_player.root_node != path:
		animation_player.root_node = path


# The model was swapped: new root for the clips, and the tree (its root and the upper body's
# bones) is built again from the new skeleton.
func _on_rig_changed(_rig: Node3D) -> void:
	if tree == null or animation_player == null or player == null:
		return
	update_configuration_warnings()
	if _rig == null:
		# Between the old model and the new one: the editor has emptied the paths already, and a
		# tree built now would resolve every track of every clip from nothing.
		if not Engine.is_editor_hint():
			tree.active = false
		return
	_follow_rig()
	tree.anim_player = NodePath()
	if not Engine.is_editor_hint():
		tree.active = _fits(model.rig())
	_rebuild()


func _fits(rig: Node3D) -> bool:
	return rig != null and rig.get_node_or_null("Armature/Skeleton3D") != null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if model == null:
		warnings.append("Set `model` to the PlayerModel that holds the character.")
	elif model.rig() != null and not _fits(model.rig()):
		warnings.append(
			"The clips name `Armature/Skeleton3D` under the model, and this one has none."
		)
	return warnings


func _build() -> void:
	tree.anim_player = tree.get_path_to(animation_player)
	tree.tree_root = _build_root()


# Builds the tree again from the exports: in the editor so the graph shows the change, and in
# the game so a clip or a blend time changed while it runs takes effect (the body goes on from the
# state it was in).
func _rebuild() -> void:
	if not is_node_ready() or tree == null or animation_player == null or player == null:
		return
	var current := body_state()
	_build()
	if Engine.is_editor_hint():
		return
	_playback = tree.get(&"parameters/%s/playback" % _MACHINE)
	_playback.start(current if current != &"" else GROUND)


# Moves the walk, run and sprint points of the ground blend space (and the crouch walk point) to
# the tuning's speeds (the tuning has no `changed` for them, so the game checks every frame).
func _sync_ground_speeds() -> void:
	if _ground == null or player == null or player.tuning == null:
		return
	var tuning := player.tuning
	var speeds := [tuning.walk_speed, tuning.run_speed, tuning.sprint_speed, tuning.crouch_speed]
	if speeds == _ground_speeds:
		return
	_ground_speeds = speeds
	_ground.max_space = tuning.sprint_speed
	for index in 3:
		_ground.set_blend_point_position(index + 1, speeds[index])
	_crouch.max_space = tuning.crouch_speed
	_crouch.set_blend_point_position(1, tuning.crouch_speed)


# The pistol layer follows the player: held (or not), how far the arm is up, and the camera's pitch
# for the aim pose.
func _drive_pistol() -> void:
	var armed := 1.0 if player.weapon != null else 0.0
	tree.set(&"parameters/%s/blend_amount" % _ARMED, armed)
	tree.set(&"parameters/%s/blend_amount" % _AIM, player.aim_amount * armed)
	tree.set(&"parameters/%s/scale" % _SHOOT_SCALE, shoot_speed)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var up := rad_to_deg(asin(clampf(-camera.global_basis.z.y, -1.0, 1.0)))
		tree.set(
			&"parameters/%s/blend_position" % _AIM_POSE,
			clampf(up, -aim_pitch_range, aim_pitch_range)
		)


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
		Player.State.CROUCH:
			_travel(CROUCH)


func _on_interacted(_target: Node3D) -> void:
	play_clip(interact_clip, player.tuning.interact_time)


func _on_hit(_amount: float, _source: Node3D) -> void:
	play_clip(hit_clip, player.tuning.hit_stun_time)


func _on_shot(_projectile: Projectile) -> void:
	tree.set(&"parameters/%s/request" % _SHOOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


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
	root.add_node(_ACTION, action, Vector2(1000, 0))
	_add_pistol_layer(root)
	root.connect_node(_ACTION, 0, _AIM)
	root.connect_node(_ACTION, 1, _ACTION_SCALE)
	root.connect_node(&"output", 0, _ACTION)
	return root


# The pistol layer, on the upper body only: `Armed` blends the holding pose over the locomotion,
# `Aim` blends the aim pose (with a recoil one-shot over it) over that.
func _add_pistol_layer(root: AnimationNodeBlendTree) -> void:
	var upper := _upper_body_paths()
	var armed := AnimationNodeBlend2.new()
	armed.filter_enabled = true
	var aim := AnimationNodeBlend2.new()
	aim.filter_enabled = true
	var shoot := AnimationNodeOneShot.new()
	shoot.fadein_time = 0.03
	shoot.fadeout_time = 0.12
	shoot.filter_enabled = true
	for path in upper:
		armed.set_filter_path(path, true)
		aim.set_filter_path(path, true)
		shoot.set_filter_path(path, true)
	var pose := AnimationNodeBlendSpace1D.new()
	pose.min_space = -aim_pitch_range
	pose.max_space = aim_pitch_range
	pose.sync = true
	pose.add_blend_point(_clip(aim_down_clip), -aim_pitch_range, -1, &"down")
	pose.add_blend_point(_clip(aim_clip), 0.0, -1, &"level")
	pose.add_blend_point(_clip(aim_up_clip), aim_pitch_range, -1, &"up")
	_shoot_scale_node = AnimationNodeTimeScale.new()
	root.add_node(_PISTOL_IDLE, _clip(pistol_idle_clip), Vector2(200, 400))
	root.add_node(_ARMED, armed, Vector2(400, 0))
	root.add_node(_AIM_POSE, pose, Vector2(200, 600))
	root.add_node(_SHOOT_CLIP, _clip(shoot_clip), Vector2(200, 800))
	root.add_node(_SHOOT_SCALE, _shoot_scale_node, Vector2(400, 800))
	root.add_node(_SHOOT, shoot, Vector2(600, 600))
	root.add_node(_AIM, aim, Vector2(800, 0))
	root.connect_node(_SHOOT_SCALE, 0, _SHOOT_CLIP)
	root.connect_node(_ARMED, 0, _MACHINE)
	root.connect_node(_ARMED, 1, _PISTOL_IDLE)
	root.connect_node(_SHOOT, 0, _AIM_POSE)
	root.connect_node(_SHOOT, 1, _SHOOT_SCALE)
	root.connect_node(_AIM, 0, _ARMED)
	root.connect_node(_AIM, 1, _SHOOT)


# The filter paths of the upper body: `upper_body_bone` and every bone below it, as the clips'
# tracks name them (`Armature/Skeleton3D:spine_01`).
func _upper_body_paths() -> Array[NodePath]:
	var found: Array[NodePath] = []
	var rig := animation_player.get_node_or_null(animation_player.root_node)
	if rig == null:
		return found
	var skeletons := rig.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return found
	var skeleton := skeletons[0] as Skeleton3D
	var start := skeleton.find_bone(upper_body_bone)
	if start < 0:
		return found
	var where := rig.get_path_to(skeleton)
	for bone in skeleton.get_bone_count():
		var cursor := bone
		while cursor >= 0 and cursor != start:
			cursor = skeleton.get_bone_parent(cursor)
		if cursor == start:
			found.append(NodePath("%s:%s" % [where, skeleton.get_bone_name(bone)]))
	return found


func _build_machine() -> AnimationNodeStateMachine:
	_machine = AnimationNodeStateMachine.new()
	_machine.add_node(GROUND, _build_ground(), Vector2(200, 0))
	_machine.add_node(JUMP, _clip(jump_clip), Vector2(400, -100))
	_machine.add_node(FALL, _clip(air_clip), Vector2(600, 0))
	_machine.add_node(LAND, _clip(land_clip), Vector2(400, 100))
	_machine.add_node(PUSH, _clip(push_clip), Vector2(200, 160))
	_machine.add_node(CROUCH, _build_crouch(), Vector2(0, 160))
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	_machine.add_transition(&"Start", GROUND, start)
	var states := [GROUND, JUMP, FALL, LAND, PUSH, CROUCH]
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
	var tuning := player.tuning if player.tuning != null else PlayerTuning.new()
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = tuning.sprint_speed
	space.sync = true
	space.add_blend_point(_clip(idle_clip), 0.0, -1, &"idle")
	space.add_blend_point(_clip(walk_clip), tuning.walk_speed, -1, &"walk")
	space.add_blend_point(_clip(run_clip), tuning.run_speed, -1, &"run")
	space.add_blend_point(_clip(sprint_clip), tuning.sprint_speed, -1, &"sprint")
	_ground = space
	_ground_speeds = [tuning.walk_speed, tuning.run_speed, tuning.sprint_speed, tuning.crouch_speed]
	return space


func _build_crouch() -> AnimationNodeBlendSpace1D:
	var tuning := player.tuning if player.tuning != null else PlayerTuning.new()
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = tuning.crouch_speed
	space.sync = true
	space.add_blend_point(_clip(crouch_idle_clip), 0.0, -1, &"idle")
	space.add_blend_point(_clip(crouch_walk_clip), tuning.crouch_speed, -1, &"walk")
	_crouch = space
	return space


func _clip(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node
