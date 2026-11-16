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
##
## Its parts, each a class of its own beside it: `BodyMachine` builds the body's state machine,
## `WeaponLayers` the weapon layer and its drive (grip, aim, shots, reload), `ActionLayer` the
## one-shot of the actions, `TreeClock` hands the tree's clock to a throttle, and `TreeParts` holds
## the clip nodes and bone filters they are made of. This node keeps the exports, the signals, the
## build order and the reads the game asks of it.

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
# The playback of the body machine, the one path the node itself reads (made once).
const _P_PLAYBACK := StringName("parameters/%s/playback" % _MACHINE)

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
## The push off the ground standing (from a run: `GaitSettings.run_takeoff_left`, `_right`).
@export var jump_clip: StringName = CharacterClips.JUMP_START:
	set(value):
		jump_clip = value
		_rebuild()
## In the air, falling (with the rise and the top on the vertical speed: `GaitSettings`).
@export var air_clip: StringName = CharacterClips.AIR:
	set(value):
		air_clip = value
		_rebuild()
## Touching down (a hard landing and one into a run: `GaitSettings`, `JumpAnimation`).
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
## Degrees the muzzle jumps up at a shot fired lying down (the prone aim has no shot clip: the
## look it is posed for is kicked up and settles), and the seconds it takes to settle.
@export_range(0.0, 20.0, 0.5, "suffix:deg") var prone_shot_kick := 7.0
@export_range(0.02, 1.0, 0.01, "suffix:s") var prone_shot_kick_time := 0.22
## Prone clips a model plays instead of the `AnimationPlayer`'s own `prone` library, by the model's
## scene file (`res://assets/characters/mannequin/mannequin_male.glb`): a body whose limbs differ
## lies on the floor with clips solved on it. The library must hold the same clip names. Swapped
## in the game when the model is set or replaced, never in the editor (the scene keeps its own).
@export var prone_libraries: Dictionary[String, AnimationLibrary] = {}
## The same for the `prone_aim` library: the hands of each body are solved on its own arms.
@export var prone_aim_libraries: Dictionary[String, AnimationLibrary] = {}
## The same for the library `prone_reload`: a reload lying down is solved a body, as the aim is.
@export var prone_reload_libraries: Dictionary[String, AnimationLibrary] = {}

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
## Seconds the body states take to blend into each other, when the momentum blend is off
## (`GaitSettings.momentum_blend`; on, a new state shows at once and its difference dies away).
@export_range(0.0, 1.0, 0.01, "suffix:s") var blend_time := 0.15:
	set(value):
		blend_time = value
		_rebuild()
## Seconds an action clip takes to blend in and out.
@export_range(0.0, 1.0, 0.01, "suffix:s") var action_blend_time := 0.1:
	set(value):
		action_blend_time = value
		_rebuild()
## How the gaits fit the body's motion: the speed matching, the transitions, the momentum blend
## that replaces `blend_time`'s cross-fade, the lean (`GaitSettings`). Empty: its defaults.
@export var gait_settings: GaitSettings:
	set(value):
		gait_settings = value
		_rebuild()

var melee := MeleeLayer.new()  # The melee blow's one-shot (gdstudio #1254).
var hits := HitLayer.new()  # where a hit's clip plays: stance and weapon (gdstudio #1292, #1345)
var rack := RackLayer.new()  # The slide's rack after an empty reload (gdstudio #1337).
var gait := CharacterGait.new()  # speed matching, transitions, momentum, lean (gdstudio #1158)
var _body := BodyMachine.new()  # the body's state machine (gdstudio #1287)
var _weapons := WeaponLayers.new()  # grip, aim, shots and reload, built and driven
var _actions := ActionLayer.new()  # the one-shot of the actions over the whole or upper body
var _clock := TreeClock.new()  # the tree moving itself, or a throttle moving it
var _tuning: CharacterTuning  # its speeds are the blend spaces' (its `changed` is connected)
var _prone_look := ProneAnimation.new()  # the crawl, the weapon put away, a model's own clips
var _vault_look := VaultAnimation.new()  # a vault timed by its clip and its landing step
var _watched_hold: WeaponDef
var _playback: AnimationNodeStateMachinePlayback
var _dead := false
var _clip_death := false
var _pitch_before := 0.0
var _pitch_now := 0.0
var _brace := AimBrace.Driver.new()


func _ready() -> void:
	if character == null or animation_player == null or tree == null:
		return
	if model != null:
		model.rig_changed.connect(_on_rig_changed)
		_follow_rig()
	var own := [prone_libraries, prone_aim_libraries, prone_reload_libraries]
	_prone_look.use_body_clips(animation_player, _rig_or_null(), own)
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
	return _clock.throttled


## Hands the tree's clock to the caller (`on`) or gives it back (`TreeClock`). Throttled, the tree
## and the skeleton's modifiers (with `skeleton_too`) move only when `advance()` is called; given
## back, they run every frame as before. Nothing calls it for the player: off, the tree is exactly
## as it always was. A death gives it back at once (the ragdoll needs the skeleton every frame).
func set_throttled(on: bool, skeleton_too: bool = true) -> void:
	if Engine.is_editor_hint() or tree == null or on == _clock.throttled:
		return
	_clock.hand_over(self, on, skeleton_too)


## Moves a throttled tree on by `delta` seconds at once (the time since its last advance): the
## parameters are set from the character as a frame would set them, then the tree and the
## skeleton's modifiers run. Nothing while the tree is off (dead).
func advance(delta: float) -> void:
	if not _clock.throttled or tree == null or not tree.active or _playback == null:
		return
	if delta <= 0.0:
		return
	# Switching the tree on again (a new model) lets it run itself: stop that first.
	TreeClock.runs_itself(tree, false)
	_drive(delta)
	_clock.step(tree, delta)


# What a frame sets on the tree from the character, `delta` seconds after the last time.
func _drive(delta: float) -> void:
	_follow_tuning()
	var speed := _vault_look.follow(character, self, action_blend_time, delta)
	gait.drive(self, _playback, speed, delta)
	_prone_look.step_crawl_share(speed, blend_time, delta)
	var up := _look_up_at(Engine.get_physics_interpolation_fraction())
	_weapons.drive(self, _brace, _prone_look, _vault_look, up, delta)
	var active := _actions.is_active(tree)
	var hit := active and _actions.clip == hit_clip
	var armed := _weapons.weights.x > 0.0
	hits.follow(tree, hit, body_state(), armed, active and _actions.upper_only)
	if _actions.was_active and not active:
		action_finished.emit(_actions.clip)
	_actions.was_active = active


## The body state the tree is in now (`ground`, `crouch`, `prone`, `jump`, `fall`, `land` or
## `push`).
func body_state() -> StringName:
	return _playback.get_current_node() if _playback != null else &""


## True while an action clip plays over the body; with `whole_body`, over all of it (a vault, a
## push), not over the upper body alone.
func is_acting(whole_body := false) -> bool:
	return _actions.is_active(tree) and not (whole_body and _actions.upper_only)


## True while a whole-body action plays that came in with no cross-fade (lying down, getting up):
## the momentum blend carries the drawn pose into it (`ActionLayer.play_carried()`).
func is_action_carried() -> bool:
	return _actions.carried and is_acting(true)


## The action clip that played last.
func last_action() -> StringName:
	return _actions.clip


## Plays any clip of the libraries over the body once (`CharacterClips.SWORD_ATTACK`). With a
## `duration` above zero the clip is sped up or slowed to take that long; with `upper_body` it
## plays on the spine, head and left arm alone (`UseLayer`: using an item).
func play_clip(clip: StringName, duration: float = 0.0, upper_body := false) -> void:
	if tree == null or not animation_player.has_animation(clip):
		push_warning("CharacterAnimation: no clip called %s" % clip)
		return
	_actions.play(self, clip, duration, upper_body)
	action_started.emit(clip)


## How far the weapon is held (x: 0 away, 1 in the hand) and aimed (y: 0 carried, 1 the arm up),
## standing or lying, the aim less during a melee blow.
func pistol_weights() -> Vector2:
	return melee.weigh(tree, _weapons.weights) if tree != null else Vector2.ZERO


## How far the body lies with a weapon that has a prone aim (0 up, 1 lying): by this much the
## prone aim clips stand in for the standing weapon layer.
func prone_hold_share() -> float:
	return _prone_look.lies


## Where the aim pose is on its pitch axis, in degrees (negative looks down).
func aim_pitch() -> float:
	return _weapons.aim_pitch(tree)


## True while a shot's clip (the recoil, a blow) plays over the upper body, fading in and out.
func is_shooting() -> bool:
	return _weapons.is_shooting(tree)


## True while the reload clip plays over the upper body.
func is_reloading() -> bool:
	return _weapons.is_reloading(tree)


## Where the reload clip is, for whatever follows it (the `WeaponHold`'s left hand): x how much of
## the upper body the clip holds now (0 none, 1 all of it: it fades in and out), y the share of the
## clip that has played (0 its start, 1 its end), however long the weapon's reload takes.
func reload_progress() -> Vector2:
	return _weapons.reload_progress(tree)


## Stops the reload clip (a switch or a death cut the reload short).
func stop_reload() -> void:
	_weapons.stop_reload(tree)


## The weapon definition whose clips the weapon layer plays, or null.
func held_definition() -> WeaponDef:
	if character == null or character.weapon == null:
		return null
	return character.weapon.definition


## Stops an action clip early.
func stop_clip() -> void:
	_actions.stop(self)


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
	var own := [prone_libraries, prone_aim_libraries, prone_reload_libraries]
	_prone_look.use_body_clips(animation_player, _rig_or_null(), own)
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
	var root := _build_root()
	gait.decorate(self, root, _body.machine)
	tree.tree_root = root
	gait.after_build(self)
	_brace.build(self)


# The tree's root, in its build order: the body machine, the action layer, the weapon layer between
# them, and the action one-shot joined over the weapon layer's last one-shot (the melee blow's).
func _build_root() -> AnimationNodeBlendTree:
	var root := AnimationNodeBlendTree.new()
	root.add_node(_MACHINE, _body.build(self, _brace), Vector2(0, 0))
	_actions.add_to(self, root)
	_weapons.add_to(self, root, _MACHINE)
	root.connect_node(ActionLayer.NODE, 0, MeleeLayer.NODE)
	root.connect_node(ActionLayer.NODE, 1, ActionLayer.SCALE)
	root.connect_node(&"output", 0, ActionLayer.NODE)
	return root


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


# Moves the gait points of the ground and crouch blend spaces to their speeds (`GaitBlend`): the
# clips' with the speed matching, else the tuning's, which says `changed` when one changes.
func _sync_ground_speeds() -> void:
	if character != null:
		gait.blend.place_points(character.tuning)


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
	var to := BodyMachine.state_for(state, body_state())
	if to != &"" and _playback != null:
		_playback.travel(gait.route(to))


## How fast and which way the crawl clip plays now (1 its own pace; below zero backwards).
func crawl_pace() -> float:
	return ProneAnimation.crawl_pace(character, crawl_clip_speed)


func _on_prone_changed(down: bool) -> void:
	var prone := character.prone_tuning
	var clip := to_prone_clip if down else to_crouch_clip
	if prone == null or clip == &"" or tree == null or not animation_player.has_animation(clip):
		return
	_actions.play_carried(self, clip, prone.enter_time if down else prone.exit_time)
	action_started.emit(clip)


func _on_interacted(_target: Node3D) -> void:
	play_clip(interact_clip, character.tuning.interact_time)


func _on_hit(_amount: float, _source: Node3D) -> void:
	play_clip(hit_clip, character.tuning.hit_stun_time)
	hits.follow(tree, true, body_state(), _weapons.weights.x > 0.0)
	_brace.hold_up(self, character.tuning.hit_stun_time + action_blend_time)


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
	_weapons.count_shot(hold)
	if not _prone_look.kick():
		ShotLayer.fire(tree, hold)


func _on_definition_changed(_definition: WeaponDef) -> void:
	_weapons.shots = 0
	_rebuild()
	ShotLayer.stop(tree)


func _on_reload_started(seconds: float) -> void:
	var clip := _prone_look.reload_clip(character, held_definition())
	if clip == &"" or not animation_player.has_animation(clip):
		return
	_weapons.start_reload(self, clip, seconds)
