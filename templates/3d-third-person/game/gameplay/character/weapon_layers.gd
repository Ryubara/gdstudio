class_name WeaponLayers
extends RefCounted
## The weapon layer of the `CharacterAnimation`'s tree, built from the held `WeaponDef`'s clips
## (`add_to()`) and driven every frame (`drive()`): `Armed` blends the grip pose over the
## locomotion, on the gripping hand only (or on the whole upper body in the `HELD_POSE` carry),
## `Aim` blends the aim pose over that on the upper body, `Shoot` plays a shot's clip over it or
## added to it (`ShotLayer`) and `Reload` the reload clip, both on the upper body; the rack
## (`RackLayer`) and the melee blow (`MeleeLayer`) go over those. An empty clip is idle. The
## animation owns one and asks it what the layers do now (`weights`, `is_reloading()`,
## `reload_progress()`).

## The tree's nodes of the layer.
const ARMED := "Armed"
const PISTOL_IDLE := "PistolIdle"
const AIM_POSE := "AimPose"
const AIM := "Aim"
const SHOOT_CLIP := "ShootClip"
const SHOOT_SCALE := "ShootScale"
const SHOOT := "Shoot"
const RELOAD_CLIP := "ReloadClip"
const RELOAD_SCALE := "ReloadScale"
const RELOAD := "Reload"
## Seconds the reload clip takes to come over the upper body and to leave it.
const RELOAD_FADE_IN := 0.15
const RELOAD_FADE_OUT := 0.2

# The tree's parameters the layer sets or reads, made once (a path formatted every frame was seven
# strings and seven name lookups a character a frame).
const _P_ARMED := StringName("parameters/%s/blend_amount" % ARMED)
const _P_AIM := StringName("parameters/%s/blend_amount" % AIM)
const _P_AIM_POSE := StringName("parameters/%s/blend_position" % AIM_POSE)
const _P_SHOOT_SCALE := StringName("parameters/%s/scale" % SHOOT_SCALE)
const _P_SHOOT_ACTIVE := StringName("parameters/%s/active" % SHOOT)
const _P_RELOAD_ACTIVE := StringName("parameters/%s/active" % RELOAD)
const _P_RELOAD_REQUEST := StringName("parameters/%s/request" % RELOAD)
const _P_RELOAD_SCALE := StringName("parameters/%s/scale" % RELOAD_SCALE)
const _P_RELOAD_FADING_IN := StringName("parameters/%s/fade_in_remaining" % RELOAD)
const _P_RELOAD_FADING_OUT := StringName("parameters/%s/fade_out_remaining" % RELOAD)
const _P_RELOAD_INSIDE := StringName("parameters/%s/internal_active" % RELOAD)
const _P_RELOAD_AT := StringName("parameters/%s/current_position" % RELOAD_CLIP)
const _P_RELOAD_LENGTH := StringName("parameters/%s/current_length" % RELOAD_CLIP)
# The prone state of the body machine (`CharacterAnimation.PRONE`), whose parameters lie under it.
const _PRONE_STATE := "parameters/Locomotion/prone/"

## How far the weapon is held (x: 0 away, 1 in the hand) and aimed (y: 0 carried, 1 the arm up),
## as the last frame set them.
var weights := Vector2.ZERO
## Shots fired with the held weapon: a weapon with several shot clips plays them in turn.
var shots := 0

var _shoot_clip_node: AnimationNodeAnimation
var _shot_added := false


## Adds the layer to `root` over the locomotion machine `machine` (by name), from the clips of the
## weapon `animation` holds, and the rack and the melee blow over it.
func add_to(animation: CharacterAnimation, root: AnimationNodeBlendTree, machine: String) -> void:
	var hold := animation.held_definition()
	var player := animation.animation_player
	var idle := animation.idle_clip
	var grip_bones: Array = hold.grip_bones if hold != null else []
	var upper := TreeParts.bone_paths(player, [animation.upper_body_bone])
	var hand_only := animation.carry == CharacterAnimation.Carry.HAND_ONLY
	var held := TreeParts.bone_paths(player, grip_bones) if hand_only else upper
	var armed := AnimationNodeBlend2.new()
	armed.filter_enabled = true
	var aim := AnimationNodeBlend2.new()
	aim.filter_enabled = true
	var shoot := AnimationNodeOneShot.new()
	shoot.fadein_time = 0.03
	shoot.fadeout_time = 0.12
	shoot.filter_enabled = true
	var reload := AnimationNodeOneShot.new()
	reload.fadein_time = RELOAD_FADE_IN
	reload.fadeout_time = RELOAD_FADE_OUT
	reload.filter_enabled = true
	for path in held:
		armed.set_filter_path(path, true)
	var free := TreeParts.bone_paths(player, hold.free_bones() if hold != null else [])
	for path in upper:
		aim.set_filter_path(path, not free.has(path))
		shoot.set_filter_path(path, not free.has(path))
		reload.set_filter_path(path, true)
	var pitch := animation.aim_pitch_range
	var pose := AnimationNodeBlendSpace1D.new()
	pose.min_space = -pitch
	pose.max_space = pitch
	pose.sync = true
	pose.add_blend_point(_hold_clip(hold, &"aim_down_clip", idle), -pitch, -1, &"down")
	pose.add_blend_point(_hold_clip(hold, &"aim_clip", idle), 0.0, -1, &"level")
	pose.add_blend_point(_hold_clip(hold, &"aim_up_clip", idle), pitch, -1, &"up")
	var shoot_scale := AnimationNodeTimeScale.new()
	var first_shot: StringName = &""
	if hold != null and not hold.shoot_clips.is_empty():
		first_shot = hold.shoot_clips[0]
	_shoot_clip_node = TreeParts.clip(_or_idle(first_shot, idle))
	root.add_node(PISTOL_IDLE, _hold_clip(hold, &"grip_clip", idle), Vector2(200, 400))
	root.add_node(ARMED, armed, Vector2(400, 0))
	root.add_node(AIM_POSE, pose, Vector2(400, 600))
	root.add_node(AIM, aim, Vector2(600, 0))
	root.add_node(SHOOT_CLIP, _shoot_clip_node, Vector2(400, 800))
	root.add_node(SHOOT_SCALE, shoot_scale, Vector2(600, 800))
	root.add_node(SHOOT, shoot, Vector2(800, 0))
	root.add_node(RELOAD_CLIP, _hold_clip(hold, &"reload_clip", idle), Vector2(800, 1000))
	root.add_node(RELOAD_SCALE, AnimationNodeTimeScale.new(), Vector2(1000, 1000))
	root.add_node(RELOAD, reload, Vector2(1200, 0))
	root.connect_node(ARMED, 0, machine)
	root.connect_node(ARMED, 1, PISTOL_IDLE)
	root.connect_node(AIM, 0, ARMED)
	root.connect_node(AIM, 1, AIM_POSE)
	root.connect_node(SHOOT_SCALE, 0, SHOOT_CLIP)
	root.connect_node(SHOOT, 0, AIM)
	var added := hold != null and hold.shoot_additive and first_shot != &""
	var additive := TreeParts.clip(first_shot)
	_shot_added = ShotLayer.wire(root, shoot, SHOOT, SHOOT_SCALE, additive, added)
	root.connect_node(RELOAD_SCALE, 0, RELOAD_CLIP)
	root.connect_node(RELOAD, 0, SHOOT)
	root.connect_node(RELOAD, 1, RELOAD_SCALE)
	var racked := animation.rack.add_to(animation, root, RELOAD, upper, idle)
	var blow := TreeParts.clip(_or_idle(MeleeLayer.first_clip(hold), idle))
	animation.melee.add_to(animation, root, racked, upper, blow)


## Sets the layer on `animation`'s tree for this frame, `delta` seconds after the last: held (or
## not), how far the arm is up, and how far up or down the character looks (`up`, degrees, from
## `view_pitch`, never a camera) for the aim pose. The arm is up by the character's aim amount, or
## by the shot's own hold when that is more: after a shot it goes on rising for `shot_hold_time`
## and then comes down at the speed of the aim (`aim_pose_time`), so a tap of the fire button shows
## the arm up and never pops.
func drive(
	animation: CharacterAnimation,
	brace: AimBrace.Driver,
	prone: ProneAnimation,
	vault: VaultAnimation,
	up: float,
	delta: float
) -> void:
	var character := animation.character
	var tree := animation.tree
	var model := animation.model
	var hold := animation.held_definition()
	var up_share := ProneAnimation.upright_share(character, hold)
	if character.loadout != null:
		up_share *= 1.0 - character.loadout.lowered_amount()
	var stowed := ProneAnimation.stow_share(character, reload_progress(tree).x)
	var stow := maxf(stowed, vault.hands)
	var hidden := stowed > 0.5 or vault.away
	prone.stow_view(model if is_instance_valid(model) else null, hold, hidden)
	var grip := up_share * CharacterSlide.grip_share(character, hold)
	var armed := grip * (1.0 - stow) if hold != null and hold.grip_clip != &"" else 0.0
	var aims := up_share if hold != null and hold.aim_clip != &"" else 0.0
	var arm := brace.arm(animation, delta)
	# Lying with a prone aim, its clips (in the prone state) stand in for the standing layers.
	var lying := prone.lying(character, hold)
	if is_reloading(tree) and prone.reload_misplaced():
		stop_reload(tree)
	animation.rack.step()
	weights = Vector2(armed, arm * aims)
	tree.set(_P_ARMED, minf(armed, 1.0 - lying))
	tree.set(_P_AIM, arm * aims * (1.0 - lying))
	brace.drive(animation, arm * aims * (1.0 - lying), delta)
	tree.set(_P_SHOOT_SCALE, animation.shoot_speed)
	ShotLayer.drive(tree, _shot_added)
	var limit := animation.aim_pitch_range
	tree.set(_P_AIM_POSE, clampf(up, -limit, limit))
	var paces := Vector2(animation.crawl_pace(), animation.prone_idle_pace)
	var kick := prone.step_kick(animation.prone_shot_kick, animation.prone_shot_kick_time, delta)
	prone.drive(tree, _PRONE_STATE, paces, arm * aims * lying, up + kick)


## Where the aim pose is on its pitch axis, in degrees (negative looks down).
func aim_pitch(tree: AnimationTree) -> float:
	return tree.get(_P_AIM_POSE) if tree != null else 0.0


## True while a shot's clip (the recoil, a blow) plays over the upper body, fading in and out.
func is_shooting(tree: AnimationTree) -> bool:
	return tree != null and tree.tree_root != null and tree.get(_P_SHOOT_ACTIVE)


## True while the reload clip plays over the upper body.
func is_reloading(tree: AnimationTree) -> bool:
	return tree != null and tree.get(_P_RELOAD_ACTIVE)


## Where the reload clip is: x how much of the upper body it holds now (it fades in and out), y the
## share of the clip that has played (`CharacterAnimation.reload_progress()`).
func reload_progress(tree: AnimationTree) -> Vector2:
	if not is_reloading(tree):
		return Vector2.ZERO
	var weight := 1.0 - float(tree.get(_P_RELOAD_FADING_IN)) / RELOAD_FADE_IN
	if not tree.get(_P_RELOAD_INSIDE):
		weight = float(tree.get(_P_RELOAD_FADING_OUT)) / RELOAD_FADE_OUT
	var length: float = tree.get(_P_RELOAD_LENGTH)
	var share := float(tree.get(_P_RELOAD_AT)) / length if length > 0.0 else 1.0
	return Vector2(clampf(weight, 0.0, 1.0), clampf(share, 0.0, 1.0))


## Plays `clip` over the upper body, stretched to last `seconds` (the weapon's reload time).
func start_reload(animation: CharacterAnimation, clip: StringName, seconds: float) -> void:
	var tree := animation.tree
	var root := tree.tree_root as AnimationNodeBlendTree
	(root.get_node(RELOAD_CLIP) as AnimationNodeAnimation).animation = clip
	var length := animation.animation_player.get_animation(clip).length
	tree.set(_P_RELOAD_SCALE, length / maxf(seconds, 0.01))
	tree.set(_P_RELOAD_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Stops the reload clip.
func stop_reload(tree: AnimationTree) -> void:
	if tree != null and tree.tree_root != null:
		tree.set(_P_RELOAD_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Counts a shot of `hold`, whose clips play one after another shot by shot (a jab, then a cross).
func count_shot(hold: WeaponDef) -> void:
	if hold != null and hold.shoot_clips.size() > 1 and _shoot_clip_node != null:
		_shoot_clip_node.animation = hold.shoot_clips[shots % hold.shoot_clips.size()]
	shots += 1


# The clip node of the hold's `property` (`aim_clip`), or of the idle clip when the hold leaves it
# empty (its layer then has no weight).
func _hold_clip(hold: WeaponDef, property: StringName, idle: StringName) -> AnimationNodeAnimation:
	var clip: StringName = hold.get(property) if hold != null else &""
	return TreeParts.clip(_or_idle(clip, idle))


func _or_idle(clip: StringName, idle: StringName) -> StringName:
	return clip if clip != &"" else idle
