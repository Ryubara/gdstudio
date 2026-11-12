@tool
class_name CharacterAnimation
extends Node
## Plays the clip for what the `Character` is doing, through an `AnimationTree` it builds: a state
## machine for the body (`ground` blends idle, walk, run and sprint by ground speed; `crouch`
## blends the crouch idle and walk; `prone` blends the prone idle and the crawl, with a clip
## for going down and one for getting up; `jump`, `fall`, `land` and `push` are clips of their
## own; a slide plays `slide_start` into the `slide` loop and, standing up, `slide_exit`), a
## weapon layer built from the held `WeaponDef`'s clips (the weapon sits in one hand while the arms
## and the spine follow the locomotion clip; aiming or firing brings the arm up to aim by its look,
## a shot kicks or a blow is thrown (`ShotLayer`), a reload plays stretched to the reload's time,
## and a switch lowers the arm and brings the next weapon up) and a one-shot layer on the whole body
## for actions (interact, hit, and any clip a game asks for with `play_clip()`). Dead, the tree is
## off and the ragdoll holds the skeleton; on getting up it starts again from the ground.
##
## The clips come from the Universal Animation Library 1 and 2 and the template's own clips, the
## `AnimationPlayer`'s libraries `ual1`, `ual2`, `prone`, `vault` and `gds`. Pick another clip for a
## state in the inspector; `CharacterClips` names them all. A model whose body needs prone or vault
## clips of its own gets them from `prone_libraries` and `vault_libraries`.
##
## It is a `@tool` script so the editor shows the tree too: opening the character scene builds the
## same tree, so the AnimationTree panel shows its graph and the node has no warning. Only the
## building runs in the editor, never the driving (no signals, no `_process`), and the built tree
## is taken off the node while the scene is saved, so no `.tscn` holds a generated resource.
##
## It follows the `CharacterModel` too: a replaced model gets the `AnimationPlayer` pointed at it
## and the tree built again, so a swap in the editor needs nothing set by hand (the editor empties
## the character's Root Node when the node it pointed at is deleted).

## An action clip started; `clip` is its name.
signal action_started(clip: StringName)
## The action clip that was playing ended.
signal action_finished(clip: StringName)

## How the weapon is carried while the character is not aiming or firing.
enum Carry {
	## The arms and the spine follow the locomotion clip; only the gripping hand takes the grip
	## clip, so the pistol sits in one hand and swings with the arm.
	HAND_ONLY,
	## The grip clip holds the whole upper body (both arms out in front, a weapon at the ready).
	HELD_POSE,
}

## The states of the tree's body machine, as `Character.State` maps onto them.
const GROUND := &"ground"
const JUMP := &"jump"
const FALL := &"fall"
const LAND := &"land"
const PUSH := &"push"
const CROUCH := &"crouch"
const PRONE := &"prone"
const SLIDE_START := &"slide_start"
const SLIDE := &"slide"
const SLIDE_EXIT := &"slide_exit"

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
const _RELOAD_CLIP := "ReloadClip"
const _RELOAD_SCALE := "ReloadScale"
const _RELOAD := "Reload"

# The tree's parameters the game sets or reads, made once (a path formatted every frame was seven
# strings and seven name lookups a character a frame).
const _P_PLAYBACK := StringName("parameters/%s/playback" % _MACHINE)
const _P_GROUND_SPEED := StringName("parameters/%s/" % _MACHINE + "%s/blend_position" % GROUND)
const _P_CROUCH_SPEED := StringName("parameters/%s/" % _MACHINE + "%s/blend_position" % CROUCH)
const _P_ACTION_ACTIVE := StringName("parameters/%s/active" % _ACTION)
const _P_ACTION_REQUEST := StringName("parameters/%s/request" % _ACTION)
const _P_ACTION_SCALE := StringName("parameters/%s/scale" % _ACTION_SCALE)
const _P_ARMED := StringName("parameters/%s/blend_amount" % _ARMED)
const _P_AIM := StringName("parameters/%s/blend_amount" % _AIM)
const _P_AIM_POSE := StringName("parameters/%s/blend_position" % _AIM_POSE)
const _P_SHOOT_SCALE := StringName("parameters/%s/scale" % _SHOOT_SCALE)
const _P_SHOOT_ACTIVE := StringName("parameters/%s/active" % _SHOOT)
const _P_PRONE_MOVE := StringName("parameters/%s/" % _MACHINE + "%s/Move/blend_amount" % PRONE)
const _P_CRAWL_PACE := StringName("parameters/%s/" % _MACHINE + "%s/CrawlPace/scale" % PRONE)
const _P_PRONE_IDLE_PACE := StringName("parameters/%s/" % _MACHINE + "%s/IdlePace/scale" % PRONE)
const _P_RELOAD_ACTIVE := StringName("parameters/%s/active" % _RELOAD)
const _P_RELOAD_REQUEST := StringName("parameters/%s/request" % _RELOAD)
const _P_RELOAD_SCALE := StringName("parameters/%s/scale" % _RELOAD_SCALE)
const _P_RELOAD_FADING_IN := StringName("parameters/%s/fade_in_remaining" % _RELOAD)
const _P_RELOAD_FADING_OUT := StringName("parameters/%s/fade_out_remaining" % _RELOAD)
const _P_RELOAD_INSIDE := StringName("parameters/%s/internal_active" % _RELOAD)
const _P_RELOAD_AT := StringName("parameters/%s/current_position" % _RELOAD_CLIP)
const _P_RELOAD_LENGTH := StringName("parameters/%s/current_length" % _RELOAD_CLIP)
const _RELOAD_FADE_IN := 0.15
const _RELOAD_FADE_OUT := 0.2

@export_group("Nodes")
## The character that is animated.
@export var character: Character
## The slot that holds the character's model; the clips are played on the model it finds.
@export var model: CharacterModel
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
## Dropping into a slide; the slide loop follows when it ends.
@export var slide_start_clip: StringName = CharacterClips.SLIDE_START:
	set(value):
		slide_start_clip = value
		_rebuild()
## Sliding.
@export var slide_clip: StringName = CharacterClips.SLIDE:
	set(value):
		slide_clip = value
		_rebuild()
## Getting up out of a slide that ends standing; the ground state follows when it ends.
@export var slide_exit_clip: StringName = CharacterClips.SLIDE_EXIT:
	set(value):
		slide_exit_clip = value
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
## Being hit: on the whole body standing, on the upper body crouched, lying or sliding (`HitLayer`).
@export var hit_clip: StringName = CharacterClips.HIT:
	set(value):
		hit_clip = value
		_rebuild()

@export_group("Traversal")
## The vault over a low obstacle (one hand); what it was keyed on is `VaultSettings.low_clip`.
@export var vault_clip: StringName = CharacterClips.VAULT_LOW
## The vault from `VaultSettings.high_vault_above` up (two hands; keyed on `high_clip`).
@export var vault_high_clip: StringName = CharacterClips.VAULT_HIGH
## The step out of a vault's landing, played straight after either vault. Empty: none.
@export var vault_land_clip: StringName = CharacterClips.VAULT_LAND
## Vault clips a model plays instead of the `vault` library, by its scene file (`prone_libraries`).
@export var vault_libraries: Dictionary[String, AnimationLibrary] = {}
## The climb onto an obstacle; played to last the mantle's time.
@export var mantle_clip: StringName = CharacterClips.CLIMB_UP
## The climb onto an obstacle from `VaultSettings.high_mantle_above` up.
@export var mantle_high_clip: StringName = CharacterClips.CLIMB_UP
## The slowest and fastest a traversal clip is played against its own speed, so no crossing shows
## it crawling or blurred (the body's path keeps its time; the clip ends early or is cut).
@export var traversal_speed_range := Vector2(0.5, 2.0)

@export_group("Prone")
## Lying still: the template's own prone idle (gdstudio #1009), a slow breath on the forearms.
@export var prone_idle_clip: StringName = CharacterClips.PRONE_IDLE:
	set(value):
		prone_idle_clip = value
		_rebuild()
## How fast the prone idle plays (1 its own pace, 0 held on its first pose).
@export_range(0.0, 2.0, 0.05) var prone_idle_pace := 1.0
## Crawling on the forearms, in place; the game moves the body. Played backwards to back up.
@export var crawl_clip: StringName = CharacterClips.CRAWL:
	set(value):
		crawl_clip = value
		_rebuild()
## The ground speed the crawl clip's stride covers at its own pace, m/s (the clip's README: a
## planted elbow travels 0.30 m in 52 % of the cycle): it plays at `ground speed /
## crawl_clip_speed` of its pace, backwards when the body moves away from its facing, so the
## planted elbows, fists and feet keep their place on the ground at any crawl speed.
@export_range(0.1, 5.0, 0.001, "suffix:m/s") var crawl_clip_speed := 0.618
## Going down, played over the whole body for the tuning's `enter_time`, from the crouch idle's
## first pose to the prone idle's. Empty: no clip (the blend into the prone idle shows the change).
@export var to_prone_clip: StringName = CharacterClips.TO_PRONE
## Getting up to crouch, played over the whole body for the tuning's `exit_time`, from the prone
## idle's first pose to the crouch idle's. Empty: no clip.
@export var to_crouch_clip: StringName = CharacterClips.TO_CROUCH
## Prone clips a model plays instead of the `AnimationPlayer`'s own `prone` library, by the model's
## scene file (`res://assets/characters/mannequin/mannequin_male.glb`): a body whose limbs differ
## lies on the floor with clips solved on it. The library must hold the same clip names. Swapped
## in the game when the model is set or replaced, never in the editor (the scene keeps the shared
## library).
@export var prone_libraries: Dictionary[String, AnimationLibrary] = {}

@export_group("Weapon")
## How the weapon is carried while the character is not aiming or firing. The clips are the held
## weapon's (`WeaponDef`: grip, aim level, up and down, shots, reload).
@export var carry := Carry.HAND_ONLY:
	set(value):
		carry = value
		_rebuild()
## The bone where the upper body starts: it and everything below it in the skeleton (spine, arms,
## head, fingers) take the pistol layer; the legs do not.
@export var upper_body_bone: StringName = &"spine_01":
	set(value):
		upper_body_bone = value
		_rebuild()
## Holds the upper body's turn on the aim poses' stance while aiming on the ground state
## (`AimBrace`); off, the weapon points where the pelvis of the legs' clip is turned.
@export var aim_brace := true
## Holds the legs still under a standing aim: the idle on its steadiest pose (`AimStance`).
@export var aim_stance := true
## How far the character looks up or down for the full aim up or aim down pose.
@export_range(5.0, 80.0, 0.5, "suffix:deg") var aim_pitch_range := 45.0:
	set(value):
		aim_pitch_range = value
		_rebuild()
## How fast the recoil plays (1 is the clip's own speed).
@export_range(0.2, 4.0, 0.05) var shoot_speed := 1.6
## Seconds the arm stays up after a shot, so a shot fired without aiming (a tap of the fire
## button) is seen as one; the walk and the turn are normal as soon as the buttons are let go.
@export_range(0.0, 1.0, 0.01, "suffix:s") var shot_hold_time := 0.2

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
var _tuning: CharacterTuning  # its speeds are the blend spaces' (its `changed` is connected)
var _prone_look := ProneAnimation.new()  # the crawl, the weapon put away, a model's own clips
var _vault_look := VaultAnimation.new()  # a vault timed by its clip and its landing step
var _shoot_scale_node: AnimationNodeTimeScale
var _shoot_clip_node: AnimationNodeAnimation
var _shots := 0
var _shot_added := false
var _watched_hold: WeaponDef
var _action_clip_node: AnimationNodeAnimation
var _action_scale_node: AnimationNodeTimeScale
var _playback: AnimationNodeStateMachinePlayback
var _action_clip: StringName = &""
var _action_was_active := false
var _dead := false
var _clip_death := false
var _pitch_before := 0.0
var _pitch_now := 0.0
var _throttled := false
var _skeleton_mode := Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
var _throttled_skeleton: Skeleton3D
var _brace := AimBrace.Driver.new()


func _ready() -> void:
	if character == null or animation_player == null or tree == null:
		return
	if model != null:
		model.rig_changed.connect(_on_rig_changed)
		_follow_rig()
	_prone_look.use_model_clips(animation_player, _rig_or_null(), prone_libraries)
	_vault_look.use_model_clips(animation_player, _rig_or_null(), vault_libraries)
	_build()
	_follow_tuning()
	if Engine.is_editor_hint():
		return
	tree.active = true
	# Before the tree in the frame, so what a frame sets is in the pose drawn that frame.
	process_priority = tree.process_priority - 1
	_playback = tree.get(_P_PLAYBACK)
	_playback.start(GROUND)
	character.state_changed.connect(_on_state_changed)
	character.interacted.connect(_on_interacted)
	character.took_hit.connect(_on_hit)
	character.vault_motion.started.connect(_on_vault_started)
	character.prone_changed.connect(_on_prone_changed)
	if character.weapon != null:
		character.weapon.fired.connect(_on_shot)
		character.weapon.definition_changed.connect(_on_definition_changed)
		character.weapon.reload_started.connect(_on_reload_started)
		character.weapon.reload_cancelled.connect(stop_reload)


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


# Keeps the look of the last two steps for the aim pose. A child is processed after its parent,
# so this reads what the character's step of this tick left.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or character == null:
		return
	_pitch_before = _pitch_now
	_pitch_now = character.view_pitch


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or tree == null or not tree.active or _playback == null:
		return
	_drive(delta)


## True while something else (the `AiAnimationThrottle`) decides when the tree moves on.
func is_throttled() -> bool:
	return _throttled


## Hands the tree's clock to the caller (`on`) or gives it back. Throttled, the tree and the
## skeleton's modifiers (with `skeleton_too`) move only when `advance()` is called; given back,
## they run every frame as before. Nothing calls it for the player: off, the tree is exactly as it
## always was. A death gives it back at once (the ragdoll needs the skeleton every frame).
##
## The tree keeps its callback mode and only its own processing stops: setting
## `callback_mode_process` turns the tree off and on again, which starts its state machine over
## from the first state, a jump of the whole pose.
func set_throttled(on: bool, skeleton_too: bool = true) -> void:
	if Engine.is_editor_hint() or tree == null or on == _throttled:
		return
	_throttled = on
	set_process(not on)
	_tree_runs_itself(not on)
	if on:
		# A tree that has not run yet starts its state machine on its first update, and that
		# update's time is lost: start it now, so the first advance keeps all the time it is given.
		if tree.active:
			tree.advance(0.0)
		_throttled_skeleton = model.skeleton() if skeleton_too and model != null else null
		if _throttled_skeleton != null:
			_skeleton_mode = _throttled_skeleton.modifier_callback_mode_process
			_throttled_skeleton.modifier_callback_mode_process = (
				Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
			)
		return
	if _throttled_skeleton != null and is_instance_valid(_throttled_skeleton):
		_throttled_skeleton.modifier_callback_mode_process = _skeleton_mode
	_throttled_skeleton = null


## Moves a throttled tree on by `delta` seconds at once (the time since its last advance): the
## parameters are set from the character as a frame would set them, then the tree and the
## skeleton's modifiers run. Nothing while the tree is off (dead).
func advance(delta: float) -> void:
	if not _throttled or tree == null or not tree.active or _playback == null or delta <= 0.0:
		return
	# Switching the tree on again (a new model) lets it run itself: stop that first.
	_tree_runs_itself(false)
	_drive(delta)
	tree.advance(delta)
	if _throttled_skeleton != null and is_instance_valid(_throttled_skeleton):
		_throttled_skeleton.advance(delta)


# The tree's own processing, in its callback mode, on or off (with its mode and state kept).
func _tree_runs_itself(on: bool) -> void:
	var mode := tree.callback_mode_process
	var running := on and tree.active
	var idle := running and mode == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	var physics := running and mode == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	if tree.is_processing_internal() != idle:
		tree.set_process_internal(idle)
	if tree.is_physics_processing_internal() != physics:
		tree.set_physics_process_internal(physics)


# What a frame sets on the tree from the character, `delta` seconds after the last time.
func _drive(delta: float) -> void:
	_follow_tuning()
	var speed := _vault_look.follow(character, self, action_blend_time, delta)
	tree.set(_P_GROUND_SPEED, speed)
	tree.set(_P_CROUCH_SPEED, speed)
	_drive_prone(speed, delta)
	_drive_pistol(delta)
	var active: bool = tree.get(_P_ACTION_ACTIVE)
	HitLayer.follow(tree, active and _action_clip == hit_clip, body_state())
	if _action_was_active and not active:
		action_finished.emit(_action_clip)
	_action_was_active = active


## The body state the tree is in now (`ground`, `crouch`, `prone`, `jump`, `fall`, `land` or
## `push`).
func body_state() -> StringName:
	return _playback.get_current_node() if _playback != null else &""


## True while an action clip plays over the body.
func is_acting() -> bool:
	return tree != null and tree.get(_P_ACTION_ACTIVE)


## The action clip that played last.
func last_action() -> StringName:
	return _action_clip


## Plays any clip of the libraries over the body once (`CharacterClips.SWORD_ATTACK`). With a
## `duration` above zero the clip is sped up or slowed to take that long.
func play_clip(clip: StringName, duration: float = 0.0) -> void:
	if tree == null or not animation_player.has_animation(clip):
		push_warning("CharacterAnimation: no clip called %s" % clip)
		return
	_action_clip = clip
	_action_clip_node.animation = clip
	var length := animation_player.get_animation(clip).length
	var scale := length / duration if duration > 0.0 else 1.0
	tree.set(_P_ACTION_SCALE, scale)
	tree.set(_P_ACTION_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	action_started.emit(clip)


## How much of the upper body the pistol holds (0 none, 1 all of it): the holding pose, then the
## aim over it.
func pistol_weights() -> Vector2:
	if tree == null:
		return Vector2.ZERO
	return Vector2(tree.get(_P_ARMED), tree.get(_P_AIM))


## Where the aim pose is on its pitch axis, in degrees (negative looks down).
func aim_pitch() -> float:
	return tree.get(_P_AIM_POSE) if tree != null else 0.0


## True while a shot's clip (the recoil, a blow) plays over the upper body, fading in and out.
func is_shooting() -> bool:
	return tree != null and tree.tree_root != null and tree.get(_P_SHOOT_ACTIVE)


## True while the reload clip plays over the upper body.
func is_reloading() -> bool:
	return tree != null and tree.get(_P_RELOAD_ACTIVE)


## Where the reload clip is, for whatever follows it (the `WeaponHold`'s left hand): x how much of
## the upper body the clip holds now (0 none, 1 all of it: it fades in and out), y the share of the
## clip that has played (0 its start, 1 its end), however long the weapon's reload takes.
func reload_progress() -> Vector2:
	if not is_reloading():
		return Vector2.ZERO
	var weight := 1.0 - float(tree.get(_P_RELOAD_FADING_IN)) / _RELOAD_FADE_IN
	if not tree.get(_P_RELOAD_INSIDE):
		weight = float(tree.get(_P_RELOAD_FADING_OUT)) / _RELOAD_FADE_OUT
	var length: float = tree.get(_P_RELOAD_LENGTH)
	var share := float(tree.get(_P_RELOAD_AT)) / length if length > 0.0 else 1.0
	return Vector2(clampf(weight, 0.0, 1.0), clampf(share, 0.0, 1.0))


## Stops the reload clip (a switch or a death cut the reload short).
func stop_reload() -> void:
	if tree != null and tree.tree_root != null:
		tree.set(_P_RELOAD_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## The weapon definition whose clips the weapon layer plays, or null.
func held_definition() -> WeaponDef:
	if character == null or character.weapon == null:
		return null
	return character.weapon.definition


## Stops an action clip early.
func stop_clip() -> void:
	if tree != null:
		tree.set(_P_ACTION_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


# Points the animation player at the model the slot holds: the clips' tracks
# (`Armature/Skeleton3D:<bone>`) are paths from the model's root. A model that has no such path
# gets no root at all, so the engine logs one warning for the character instead of one for every
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
	if tree == null or animation_player == null or character == null:
		return
	update_configuration_warnings()
	if _rig == null:
		# Between the old model and the new one: the editor has emptied the paths already, and a
		# tree built now would resolve every track of every clip from nothing.
		if not Engine.is_editor_hint():
			tree.active = false
		return
	_follow_rig()
	_prone_look.use_model_clips(animation_player, _rig_or_null(), prone_libraries)
	_vault_look.use_model_clips(animation_player, _rig_or_null(), vault_libraries)
	tree.anim_player = NodePath()
	if not Engine.is_editor_hint():
		tree.active = _fits(model.rig()) and not _dead
	_rebuild()


func _rig_or_null() -> Node3D:
	return model.rig() if is_instance_valid(model) else null


func _fits(rig: Node3D) -> bool:
	return rig != null and rig.get_node_or_null("Armature/Skeleton3D") != null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if model == null:
		warnings.append("Set `model` to the CharacterModel that holds the character.")
	elif model.rig() != null and not _fits(model.rig()):
		warnings.append("The clips name `Armature/Skeleton3D` under the model; it has none.")
	return warnings


func _build() -> void:
	_watch_hold()
	tree.anim_player = tree.get_path_to(animation_player)
	tree.tree_root = _build_root()
	_brace.build(self)


# Builds the tree again when a clip of the held definition changes (tuned in the inspector).
func _watch_hold() -> void:
	var hold := held_definition()
	if hold == _watched_hold:
		return
	if _watched_hold != null and _watched_hold.changed.is_connected(_rebuild):
		_watched_hold.changed.disconnect(_rebuild)
	_watched_hold = hold
	if hold != null:
		hold.changed.connect(_rebuild)


# Builds the tree again from the exports: in the editor so the graph shows it, and in the game so
# a clip or a blend time changed while it runs takes effect (the body goes on from its state).
func _rebuild() -> void:
	if not is_node_ready() or tree == null or animation_player == null or character == null:
		return
	var current := body_state()
	_build()
	if Engine.is_editor_hint():
		return
	_playback = tree.get(_P_PLAYBACK)
	_playback.start(current if current != &"" else GROUND)


# Listens to the character's tuning, again when the character is given another one (one compare a
# frame), and puts its speeds on the blend spaces.
func _follow_tuning() -> void:
	var tuning := character.tuning if character != null else null
	if tuning == _tuning:
		return
	if _tuning != null and _tuning.changed.is_connected(_sync_ground_speeds):
		_tuning.changed.disconnect(_sync_ground_speeds)
	_tuning = tuning
	if tuning != null:
		tuning.changed.connect(_sync_ground_speeds)
	_sync_ground_speeds()


# Moves the walk, run and sprint points of the ground blend space (and the crouch walk point) to
# the tuning's speeds; the tuning says `changed` when one of them changes.
func _sync_ground_speeds() -> void:
	if _ground == null or character == null or character.tuning == null:
		return
	var tuning := character.tuning
	var speeds := [tuning.walk_speed, tuning.run_speed, tuning.sprint_speed]
	_ground.max_space = tuning.sprint_speed
	for index in 3:
		_ground.set_blend_point_position(index + 1, speeds[index])
	_crouch.max_space = tuning.crouch_speed
	_crouch.set_blend_point_position(1, tuning.crouch_speed)


# The pistol layer follows the character: held (or not), how far the arm is up, and how far up or
# down the character looks (`view_pitch`, never a camera) for the aim pose. The arm is up by
# the character's aim amount, or by the shot's own hold when that is more: after a shot it goes on
# rising for `shot_hold_time` and then comes down at the speed of the aim (`aim_pose_time`), so a
# tap of the fire button shows the arm up and never pops.
func _drive_pistol(delta: float) -> void:
	var hold := held_definition()
	var up_share := 1.0
	if character.loadout != null:
		up_share = 1.0 - character.loadout.lowered_amount()
	var lying := ProneAnimation.stow_share(character)
	var stow := maxf(lying, _vault_look.hands)
	var hidden := lying > 0.5 or _vault_look.away
	_prone_look.stow_view(model if is_instance_valid(model) else null, hold, hidden)
	var armed := up_share * (1.0 - stow) if hold != null and hold.grip_clip != &"" else 0.0
	var aims := up_share if hold != null and hold.aim_clip != &"" else 0.0
	var arm := _brace.arm(self, delta)
	tree.set(_P_ARMED, armed)
	tree.set(_P_AIM, arm * aims)
	_brace.drive(self, arm * aims, delta)
	tree.set(_P_SHOOT_SCALE, shoot_speed)
	ShotLayer.drive(tree, _shot_added)
	var up := _look_up_at(Engine.get_physics_interpolation_fraction())
	tree.set(_P_AIM_POSE, clampf(up, -aim_pitch_range, aim_pitch_range))


# How far up the character looks, in degrees, `fraction` of the way from the step before the last
# to the last one: the pose moves on every drawn frame, as the engine moves the body itself.
func _look_up_at(fraction: float) -> float:
	return rad_to_deg(lerpf(_pitch_before, _pitch_now, clampf(fraction, 0.0, 1.0)))


func _on_state_changed(state: Character.State) -> void:
	if state == Character.State.DEAD:
		# The ragdoll takes the skeleton over from the pose the tree left on it.
		_dead = true
		_brace.weigh(0.0)
		stop_clip()
		tree.active = false
		set_throttled(false)
		if character != null and character.died_by_clip:
			# No ragdoll for this death: the clip plays on the character itself and holds its last pose.
			_clip_death = animation_player.has_animation(CharacterClips.DEATH)
			if _clip_death:
				animation_player.play(CharacterClips.DEATH)
		return
	if _dead:
		_dead = false
		if _clip_death:
			_clip_death = false
			animation_player.stop()
		tree.active = _fits(model.rig()) if model != null else true
		_playback.start(GROUND)
	match state:
		Character.State.IDLE, Character.State.WALK, Character.State.RUN:
			var current := body_state()
			_travel(SLIDE_EXIT if current == SLIDE or current == SLIDE_START else GROUND)
		Character.State.JUMP:
			_travel(JUMP)
		Character.State.FALL:
			_travel(FALL)
		Character.State.LAND:
			_travel(LAND)
		Character.State.PUSH:
			_travel(PUSH)
		Character.State.CROUCH:
			_travel(CROUCH)
		Character.State.SLIDE:
			_travel(SLIDE_START)
		Character.State.PRONE:
			_travel(PRONE)


# The prone state follows the crawl (`ProneAnimation`): the crawl replaces the idle over
# `blend_time` as soon as the body moves and plays at the pace of its stride, backwards while the
# body moves away from the way it faces; the idle plays at its own pace.
func _drive_prone(speed: float, delta: float) -> void:
	tree.set(_P_PRONE_MOVE, _prone_look.step_crawl_share(speed, blend_time, delta))
	tree.set(_P_CRAWL_PACE, crawl_pace())
	tree.set(_P_PRONE_IDLE_PACE, prone_idle_pace)


## How fast and which way the crawl clip plays now (1 its own pace; below zero backwards).
func crawl_pace() -> float:
	return ProneAnimation.crawl_pace(character, crawl_clip_speed)


func _on_prone_changed(down: bool) -> void:
	var prone := character.prone_tuning
	var clip := to_prone_clip if down else to_crouch_clip
	if prone == null or clip == &"" or not animation_player.has_animation(clip):
		return
	play_clip(clip, prone.enter_time if down else prone.exit_time)


func _on_interacted(_target: Node3D) -> void:
	play_clip(interact_clip, character.tuning.interact_time)


func _on_hit(_amount: float, _source: Node3D) -> void:
	play_clip(hit_clip, character.tuning.hit_stun_time)
	HitLayer.follow(tree, true, body_state())


# A vault or a mantle plays its clip over the whole body (`VaultAnimation.start()`).
func _on_vault_started(plan: VaultPlan) -> void:
	_vault_look.start(self, plan, traversal_clip(plan))


## The clip a crossing plays: the obstacle's own override, else this node's low or high clip for
## its kind.
func traversal_clip(plan: VaultPlan) -> StringName:
	var mantle := plan.kind == VaultPlan.Kind.MANTLE
	if plan.vaultable != null:
		var own := plan.vaultable.mantle_clip if mantle else plan.vaultable.vault_clip
		if own != &"":
			return own
	if mantle:
		return mantle_high_clip if plan.high else mantle_clip
	return vault_high_clip if plan.high else vault_clip


func _on_shot(_projectile: Projectile) -> void:
	_brace.shot(self)
	var hold := held_definition()
	if hold != null and hold.shoot_clips.size() > 1 and _shoot_clip_node != null:
		# One clip after another shot by shot (a jab, then a cross).
		_shoot_clip_node.animation = hold.shoot_clips[_shots % hold.shoot_clips.size()]
	_shots += 1
	ShotLayer.fire(tree, hold)


func _on_definition_changed(_definition: WeaponDef) -> void:
	_shots = 0
	_rebuild()
	ShotLayer.stop(tree)


func _on_reload_started(seconds: float) -> void:
	var hold := held_definition()
	if hold == null or hold.reload_clip == &"":
		return
	if not animation_player.has_animation(hold.reload_clip):
		return
	var length := animation_player.get_animation(hold.reload_clip).length
	tree.set(_P_RELOAD_SCALE, length / maxf(seconds, 0.01))
	tree.set(_P_RELOAD_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


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
	# A vault holds its clip to the body's own time through the seek (`VaultAnimation`).
	root.add_node(VaultAnimation.SEEK, AnimationNodeTimeSeek.new(), Vector2(100, 200))
	root.connect_node(VaultAnimation.SEEK, 0, _ACTION_CLIP)
	root.connect_node(_ACTION_SCALE, 0, VaultAnimation.SEEK)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = action_blend_time
	action.fadeout_time = action_blend_time
	HitLayer.prepare(action, _bone_paths([upper_body_bone]))
	root.add_node(_ACTION, action, Vector2(1400, 0))
	_add_pistol_layer(root)
	root.connect_node(_ACTION, 0, _RELOAD)
	root.connect_node(_ACTION, 1, _ACTION_SCALE)
	root.connect_node(&"output", 0, _ACTION)
	return root


# The weapon layer, from the held definition's clips: `Armed` blends the grip pose over the
# locomotion, on the gripping hand only (or on the whole upper body in the `HELD_POSE` carry), `Aim`
# blends the aim pose over that on the upper body, `Shoot` plays a shot's clip over it or added to
# it (`ShotLayer`) and `Reload` the reload clip, both on the upper body. An empty clip is idle.
func _add_pistol_layer(root: AnimationNodeBlendTree) -> void:
	var hold := held_definition()
	var grip_bones: Array[StringName] = []
	if hold != null:
		grip_bones = hold.grip_bones
	var upper := _bone_paths([upper_body_bone])
	var held := _bone_paths(grip_bones) if carry == Carry.HAND_ONLY else upper
	var armed := AnimationNodeBlend2.new()
	armed.filter_enabled = true
	var aim := AnimationNodeBlend2.new()
	aim.filter_enabled = true
	var shoot := AnimationNodeOneShot.new()
	shoot.fadein_time = 0.03
	shoot.fadeout_time = 0.12
	shoot.filter_enabled = true
	var reload := AnimationNodeOneShot.new()
	reload.fadein_time = _RELOAD_FADE_IN
	reload.fadeout_time = _RELOAD_FADE_OUT
	reload.filter_enabled = true
	for path in held:
		armed.set_filter_path(path, true)
	for path in upper:
		aim.set_filter_path(path, true)
		shoot.set_filter_path(path, true)
		reload.set_filter_path(path, true)
	var pose := AnimationNodeBlendSpace1D.new()
	pose.min_space = -aim_pitch_range
	pose.max_space = aim_pitch_range
	pose.sync = true
	pose.add_blend_point(_hold_clip(hold, &"aim_down_clip"), -aim_pitch_range, -1, &"down")
	pose.add_blend_point(_hold_clip(hold, &"aim_clip"), 0.0, -1, &"level")
	pose.add_blend_point(_hold_clip(hold, &"aim_up_clip"), aim_pitch_range, -1, &"up")
	_shoot_scale_node = AnimationNodeTimeScale.new()
	var first_shot: StringName = &""
	if hold != null and not hold.shoot_clips.is_empty():
		first_shot = hold.shoot_clips[0]
	_shoot_clip_node = _clip(_or_idle(first_shot))
	root.add_node(_PISTOL_IDLE, _hold_clip(hold, &"grip_clip"), Vector2(200, 400))
	root.add_node(_ARMED, armed, Vector2(400, 0))
	root.add_node(_AIM_POSE, pose, Vector2(400, 600))
	root.add_node(_AIM, aim, Vector2(600, 0))
	root.add_node(_SHOOT_CLIP, _shoot_clip_node, Vector2(400, 800))
	root.add_node(_SHOOT_SCALE, _shoot_scale_node, Vector2(600, 800))
	root.add_node(_SHOOT, shoot, Vector2(800, 0))
	root.add_node(_RELOAD_CLIP, _hold_clip(hold, &"reload_clip"), Vector2(800, 1000))
	root.add_node(_RELOAD_SCALE, AnimationNodeTimeScale.new(), Vector2(1000, 1000))
	root.add_node(_RELOAD, reload, Vector2(1200, 0))
	root.connect_node(_ARMED, 0, _MACHINE)
	root.connect_node(_ARMED, 1, _PISTOL_IDLE)
	root.connect_node(_AIM, 0, _ARMED)
	root.connect_node(_AIM, 1, _AIM_POSE)
	root.connect_node(_SHOOT_SCALE, 0, _SHOOT_CLIP)
	root.connect_node(_SHOOT, 0, _AIM)
	var added := hold != null and hold.shoot_additive and first_shot != &""
	_shot_added = ShotLayer.wire(root, shoot, _SHOOT, _SHOOT_SCALE, _clip(first_shot), added)
	root.connect_node(_RELOAD_SCALE, 0, _RELOAD_CLIP)
	root.connect_node(_RELOAD, 0, _SHOOT)
	root.connect_node(_RELOAD, 1, _RELOAD_SCALE)


# The clip node of the hold's `property` (`aim_clip`), or of the idle clip when the hold leaves it
# empty (its layer then has no weight).
func _hold_clip(hold: WeaponDef, property: StringName) -> AnimationNodeAnimation:
	var clip: StringName = hold.get(property) if hold != null else &""
	return _clip(_or_idle(clip))


func _or_idle(clip: StringName) -> StringName:
	return clip if clip != &"" else idle_clip


# The filter paths of the given bones and every bone below each of them, as the clips' tracks name
# them (`Armature/Skeleton3D:spine_01`); a name the skeleton does not have is left out.
func _bone_paths(roots: Array) -> Array[NodePath]:
	var found: Array[NodePath] = []
	var rig := animation_player.get_node_or_null(animation_player.root_node)
	if rig == null:
		return found
	var skeletons := rig.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return found
	var skeleton := skeletons[0] as Skeleton3D
	var starts := PackedInt32Array()
	for root: StringName in roots:
		var start := skeleton.find_bone(root)
		if start >= 0:
			starts.append(start)
	var where := rig.get_path_to(skeleton)
	for bone in skeleton.get_bone_count():
		var cursor := bone
		while cursor >= 0 and not starts.has(cursor):
			cursor = skeleton.get_bone_parent(cursor)
		if cursor >= 0:
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
	_machine.add_node(PRONE, _build_prone(), Vector2(0, 320))
	_machine.add_node(SLIDE_START, _clip(slide_start_clip), Vector2(-200, 0))
	_machine.add_node(SLIDE, _clip(slide_clip), Vector2(-200, 160))
	_machine.add_node(SLIDE_EXIT, _clip(slide_exit_clip), Vector2(-200, -100))
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	_machine.add_transition(&"Start", GROUND, start)
	# A clip that plays once and goes on by itself: the slide's start into its loop, its exit
	# into the ground.
	var ends := {SLIDE_START: SLIDE, SLIDE_EXIT: GROUND}
	var states := [GROUND, JUMP, FALL, LAND, PUSH, CROUCH, PRONE, SLIDE_START, SLIDE, SLIDE_EXIT]
	for from: StringName in states:
		for to: StringName in states:
			if from == to:
				continue
			if ends.get(from, &"") == to:
				_link_at_end(from, to)
			else:
				_link(from, to)
	return _machine


func _link(from: StringName, to: StringName) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = blend_time
	_machine.add_transition(from, to, transition)


func _link_at_end(from: StringName, to: StringName) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = blend_time
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	_machine.add_transition(from, to, transition)


func _build_ground() -> AnimationNodeBlendSpace1D:
	var tuning := character.tuning if character.tuning != null else CharacterTuning.new()
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = tuning.sprint_speed
	space.sync = true
	space.add_blend_point(_brace.stance.idle_point(self, idle_clip), 0.0, -1, &"idle")
	space.add_blend_point(_clip(walk_clip), tuning.walk_speed, -1, &"walk")
	space.add_blend_point(_clip(run_clip), tuning.run_speed, -1, &"run")
	space.add_blend_point(_clip(sprint_clip), tuning.sprint_speed, -1, &"sprint")
	_ground = space
	return space


func _build_crouch() -> AnimationNodeBlendSpace1D:
	var tuning := character.tuning if character.tuning != null else CharacterTuning.new()
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = tuning.crouch_speed
	space.sync = true
	space.add_blend_point(_clip(crouch_idle_clip), 0.0, -1, &"idle")
	space.add_blend_point(_clip(crouch_walk_clip), tuning.crouch_speed, -1, &"walk")
	_crouch = space
	return space


# The prone state: the prone idle and the crawl, each with its own pace, blended by ground speed.
func _build_prone() -> AnimationNodeBlendTree:
	var blend := AnimationNodeBlendTree.new()
	blend.add_node(&"Idle", _clip(prone_idle_clip), Vector2(0, 0))
	blend.add_node(&"IdlePace", AnimationNodeTimeScale.new(), Vector2(200, 0))
	blend.add_node(&"Crawl", _clip(crawl_clip), Vector2(0, 200))
	blend.add_node(&"CrawlPace", AnimationNodeTimeScale.new(), Vector2(200, 200))
	blend.add_node(&"Move", AnimationNodeBlend2.new(), Vector2(400, 100))
	blend.connect_node(&"IdlePace", 0, &"Idle")
	blend.connect_node(&"CrawlPace", 0, &"Crawl")
	blend.connect_node(&"Move", 0, &"IdlePace")
	blend.connect_node(&"Move", 1, &"CrawlPace")
	blend.connect_node(&"output", 0, &"Move")
	return blend


func _clip(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node
