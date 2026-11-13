class_name AimLayer
extends Node
## Points the character's weapon where it aims, in any move (kit #1253): an aim offset over the
## move's pose. The clips aim a weapon from a body standing upright; a slide leans the hips back
## (the pistol pointed at the sky), a crouch or a lying body bends them, and a slide keeps the body
## along the slide while the player aims to its side. This node turns the spine after the clips by
## the yaw and pitch that put the muzzle on the aim, within the move's `AimLimits`
## (`Character.aim_limits`), so the arms swing left, right, up and down with the aim and the hands
## stay on the weapon (the grip, the trigger and the support hand follow: `WeaponHold`).
##
## The skeleton is inside the model's `.glb`, so the `AimOffsetModifier` is made here, as a child
## of the model's `Skeleton3D`, placed after the `WeaponHold`'s grip (whose wrist turn moves the
## muzzle) and before its support arm (which reaches for the weapon where the turn left it), and
## made again when the model or the hold's modifiers are made again. It follows the aim ray of the
## character's last two steps, blended by the physics interpolation as the aim clips are, and it
## is on by as much as the weapon is aimed (`CharacterAnimation.pistol_weights()`), less a
## reload; until the weapon is nearly up, the turn is the one the aim pose alone needs (`AimPose`),
## so the chest never folds back as the aim comes up or goes down. It is a pose on each machine
## from what the body already has (the view's yaw and pitch): cosmetic, never sent. A weapon with
## no muzzle (the fists) turns nothing.
##
## It makes an `AimHeadModifier` after it too (kit #1334): with any weapon, the fists among them,
## the head looks along the aim, level, with the neck on its line, whatever head the clips carry.
## It is on by the aim (the pistol's aim pose, or the character's `aim_amount` eased), less a
## reload. A weapon whose definition says `AimHead.SIGHT` (the rifle) has the head brought to its
## sights instead, the eye toward the definition's `aim_eye` marker; the head's modifier then
## runs after the stance of the hold that places that weapon.
##
## Between the two it makes an `AimUprightModifier` (kit #1351): with a weapon the spine's turn
## does not aim (the fists, no muzzle), the chest leans at most `upright_max_lean` forward while
## aiming, so a crouch's folded trunk stands up and the head stays in the shoulder camera's frame.
## It is on by the head's weight, and off lying.

const _MODIFIER := &"AimOffset"
const _HEAD_MODIFIER := &"AimHead"
const _UPRIGHT_MODIFIER := &"AimUpright"
# The prone aim's place on its look axis in the tree (`ProneAnimation.drive()`).
const _PRONE_PITCH := (
	"parameters/Locomotion/%s/%s" % [CharacterAnimation.PRONE, ProneAnimation.AIM_POSE]
)

@export_group("Nodes")
## The character whose aim the weapon follows.
@export var character: Character
## The slot that holds the character's model.
@export var model: CharacterModel
## The animation whose weapon layer says how far the weapon is aimed and when a shot plays.
@export var animation: CharacterAnimation
## The hold whose grip turns the wrist first and whose support arm follows the turned weapon.
@export var hold: WeaponHold

@export_group("Aim")
## The bones that turn, from the hips up, and each one's share of the turn (adding up to 1).
@export var chain: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
@export var chain_weights := PackedFloat32Array([0.3, 0.3, 0.4])
## How far along the aim ray the muzzle is pointed, from the ray's start: the shots meet the
## aim there (a shot flies from the muzzle to what the ray hits, so a target nearer or further is
## a little off the barrel's line, never off the crosshair).
@export_range(1.0, 200.0, 0.5, "suffix:m") var converge_distance := 15.0
## Seconds the turn takes to ease back after a shot's recoil, which it leaves as the clip plays.
@export_range(0.0, 1.0, 0.01, "suffix:s") var release_time := 0.12
## From this much of the aim up (`CharacterAnimation.pistol_weights().y`) the turn is solved on the
## drawn pose more and more, and below it on the aim pose alone (`AimPose`): the drawn pose is the
## aim pose blended with the carry pose, whose muzzle points at the floor, so a turn solved on it
## while the weapon comes up or goes down folds the chest back (kit #1318).
@export_range(0.0, 1.0, 0.01) var drawn_from := 0.9
## On: no turn (the clips alone aim the weapon, as before the layer).
@export var disabled := false

@export_group("Head")
## The neck's share of the head's turn toward the aim (the head takes the rest).
@export_range(0.0, 1.0, 0.01) var head_neck_share := 0.4
## The neck's share in the crouch. Our crouch turns the shoulders over a folded trunk, which the
## level head has to roll against: shared evenly, neither the neck nor the head takes it alone
## (10.9 degrees each with the rifle aimed level, where 0.4 gave the head 15.4).
@export_range(0.0, 1.0, 0.01) var head_crouch_neck_share := 0.5
## The neck's share lying with a prone aim (`CharacterAnimation.prone_hold_share()` blends to it):
## the prone aim clips leave the chest rolled, and with the standing share the head took too much
## of the turn that levels it.
@export_range(0.0, 1.0, 0.01) var head_prone_neck_share := 0.5
## The most the head may turn off the line the chest gives it, in degrees.
@export_range(0.0, 120.0, 0.5, "suffix:deg") var head_max_turn := 90.0
## On: the head keeps the clips' pose while aiming (as before kit #1334).
@export var head_disabled := false

@export_group("Upright")
## The most the chest (`spine_03` to the neck) may lean forward while aiming a weapon the spine's
## turn does not aim (the fists), in degrees: the crouch idle leans it 81. The pistol's and the
## rifle's aim stand it at 16 to 29 crouched.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var upright_max_lean := 30.0
## On: the chest keeps the clips' lean while aiming the fists (as before kit #1351).
@export var upright_disabled := false

var _modifier: AimOffsetModifier
var _aim_pose := AimPose.new()
var _prone_pose := AimPose.new()
var _head: AimHeadModifier
var _upright: AimUprightModifier
# The weapon whose `aim_eye` was looked up last, and the marker found (null: a level head).
var _eye_of: WeaponDef
var _eye: Node3D
var _ray_before := PackedVector3Array()
var _ray_now := PackedVector3Array()


func _ready() -> void:
	if model != null:
		model.rig_changed.connect(_build.unbind(1))
	if hold != null:
		hold.built.connect(_build)
	_build.call_deferred()


# Keeps the aim ray of the last two steps. A child is processed after its parent, so this reads
# what the character's step of this tick left.
func _physics_process(_delta: float) -> void:
	if character == null:
		return
	_ray_before = _ray_now
	_ray_now = character.aim_ray()


func _process(_delta: float) -> void:
	refresh()


## The modifier this node made on the skeleton, or null.
func modifier() -> AimOffsetModifier:
	return _modifier if _modifier != null and is_instance_valid(_modifier) else null


## The head modifier this node made on the skeleton, or null.
func head_modifier() -> AimHeadModifier:
	return _head if _head != null and is_instance_valid(_head) else null


## The upright modifier this node made on the skeleton, or null.
func upright_modifier() -> AimUprightModifier:
	return _upright if _upright != null and is_instance_valid(_upright) else null


## The share the chest is stood up by now (0 the clips' lean, 1 at most `upright_max_lean`): the
## head's weight, with a weapon the spine's turn does not aim (no muzzle or no aim clip), less how
## far the body lies.
func upright_weight() -> float:
	if upright_disabled or character == null or character.weapon == null:
		return 0.0
	var definition := character.weapon.definition
	if character.weapon.muzzle != null and definition != null and definition.aim_clip != &"":
		return 0.0
	return head_weight() * (1.0 - smoothstep(0.0, 1.0, character.prone_amount))


## The share the head looks along the aim by now (0 the clips' head, 1 all the way): the aim,
## from the aim pose's weight or the character's `aim_amount` eased, less a reload. A melee blow's
## aim is not an aim (`MeleeLayer.aim_of`): the blow's clip keeps its own head, where an aimed
## rifle's head looked along the sights of a rifle the clip was swinging (gdstudio #1288).
func head_weight() -> float:
	if head_disabled or character == null or animation == null or animation.tree == null:
		return 0.0
	if not animation.tree.active or character.aim_limits == null:
		return 0.0
	var aim := animation.melee.aim_of(character)
	var aimed := maxf(animation.pistol_weights().y, smoothstep(0.0, 1.0, aim))
	return aimed * (1.0 - _reloading())


## The share the layer is on by now (0 off, 1 the whole turn): the aim's weight, less a reload,
## and 0 in a move whose limits are off.
func weight() -> float:
	if disabled or character == null or animation == null or animation.tree == null:
		return 0.0
	if not animation.tree.active or character.weapon == null or character.weapon.muzzle == null:
		return 0.0
	var limits := character.aim_limits
	if limits == null or not limits.enabled:
		return 0.0
	return animation.pistol_weights().y * (1.0 - _reloading())


## Puts the aim on the modifiers now (the frame's own `_process` does it too).
func refresh() -> void:
	_refresh_head()
	_refresh_upright()
	var aim := modifier()
	if aim == null:
		return
	var share := weight()
	if not is_equal_approx(aim.influence, share):
		aim.influence = share
	if aim.active != (share > 0.0):
		aim.active = share > 0.0
	if share <= 0.0:
		return
	aim.muzzle = character.weapon.muzzle
	aim.limits = character.aim_limits
	aim.target = aim_point(Engine.get_physics_interpolation_fraction())
	aim.hold_turn = animation.is_shooting() or animation.is_reloading() or _racking()
	aim.release_time = release_time
	_pose_aim(aim)


# Gives the modifier the weapon's aim pose alone at the aim's pitch now (the prone aim's, by how
# far the body lies), and how far to trust the drawn pose instead.
func _pose_aim(aim: AimOffsetModifier) -> void:
	var held := animation.held_definition()
	var clips: Array[StringName] = []
	var prone: Array[StringName] = []
	if held != null:
		clips = [held.aim_down_clip, held.aim_clip, held.aim_up_clip]
		var level := held.prone_aim_clip
		for clip in [held.prone_aim_down_clip, level, held.prone_aim_up_clip]:
			prone.append(clip if clip != &"" else level)
	var skeleton := model.skeleton() if model != null else null
	var player := animation.animation_player
	var pitch := Vector2(animation.aim_pitch_range, animation.aim_pitch_range)
	var standing := _aim_pose.prepare(player, skeleton, clips, pitch)
	var share := animation.prone_hold_share()
	var lying := (
		share > 0.0
		and held != null
		and _prone_pose.prepare(player, skeleton, prone, held.prone_aim_angles)
	)
	_aim_pose.lying = _prone_pose if lying else null
	_aim_pose.lying_share = share if lying else 0.0
	if not (standing or lying) or not _aim_pose.has_pose():
		aim.aim_pose = null
		aim.drawn_trust = 1.0
		return
	_aim_pose.set_pitch(animation.aim_pitch())
	_brace_aim(skeleton, share)
	var gripping := hold.grip_modifier() if hold != null else null
	_aim_pose.grip = gripping.pose if gripping != null else null
	if lying:
		_prone_pose.set_pitch(animation.tree.get(_PRONE_PITCH))
	aim.aim_pose = _aim_pose
	var up := animation.pistol_weights().y
	aim.drawn_trust = smoothstep(drawn_from, 1.0, up) if drawn_from < 1.0 else float(up >= 1.0)


# Tells the aim pose how the `AimBrace` (the skeleton's first modifier, made by
# `CharacterAnimation` the first time the character aims) holds the upper body: its share at full
# aim is its weight now over the aim's, which it follows.
func _brace_aim(skeleton: Skeleton3D, lying: float) -> void:
	var brace := skeleton.get_node_or_null(^"AimBrace") as AimBrace
	var aimed := animation.pistol_weights().y * (1.0 - lying)
	if brace == null or not brace.active or aimed <= 0.0:
		_aim_pose.brace_share = 0.0
		return
	_aim_pose.brace_bone = skeleton.find_bone(brace.bone)
	_aim_pose.brace_stance = brace.stance
	_aim_pose.brace_share = clampf(brace.influence / aimed, 0.0, 1.0)


func _refresh_upright() -> void:
	var upright := upright_modifier()
	if upright == null:
		return
	var share := upright_weight()
	if not is_equal_approx(upright.influence, share):
		upright.influence = share
	if upright.active != (share > 0.0):
		upright.active = share > 0.0
	upright.max_lean = upright_max_lean


func _refresh_head() -> void:
	var looking := head_modifier()
	if looking == null:
		return
	var share := head_weight()
	if not is_equal_approx(looking.influence, share):
		looking.influence = share
	if looking.active != (share > 0.0):
		looking.active = share > 0.0
	if share <= 0.0:
		return
	var crouched := 0.0 if character.prone else smoothstep(0.0, 1.0, character._crouch_amount)
	var standing_share := lerpf(head_neck_share, head_crouch_neck_share, crouched)
	looking.neck_share = lerpf(standing_share, head_prone_neck_share, animation.prone_hold_share())
	looking.max_turn = head_max_turn
	looking.target = aim_point(Engine.get_physics_interpolation_fraction())
	looking.eye = _sight_eye(looking)


# The marker the head's eye goes to with the weapon in the hands, or null for a level head. The
# weapon is placed by its hold's stance in the same update, so the head's modifier is moved after
# it.
func _sight_eye(looking: AimHeadModifier) -> Node3D:
	var definition := character.weapon.definition if character.weapon != null else null
	if definition != _eye_of or (_eye != null and not is_instance_valid(_eye)):
		_eye_of = definition
		_eye = null
		if definition != null and definition.aim_head == WeaponDef.AimHead.SIGHT and model != null:
			_eye = model.get_node_or_null(definition.aim_eye) as Node3D
	if _eye == null:
		return null
	var skeleton := looking.get_parent()
	for index in range(looking.get_index() + 1, skeleton.get_child_count()):
		var after := skeleton.get_child(index)
		if after is SkeletonModifier3D and after.get_script() == TwoHandHold.STANCE_SCRIPT:
			skeleton.move_child(looking, index)
			break
	return _eye


## The point the muzzle is turned toward, `fraction` of the way from the step before the last to
## the last one: `converge_distance` along the aim ray.
func aim_point(fraction: float) -> Vector3:
	if _ray_now.size() < 2:
		var ray := character.aim_ray()
		return ray[0] + ray[1] * converge_distance
	var before := _ray_before if _ray_before.size() == 2 else _ray_now
	var share := clampf(fraction, 0.0, 1.0)
	var start := before[0].lerp(_ray_now[0], share)
	var along := before[1].slerp(_ray_now[1], share).normalized()
	return start + along * converge_distance


# Makes the modifiers on the model's skeleton, after freeing the ones made on the last model: the
# spine's right after the hold's grip (or first, with no hold), the head's right after it.
func _build() -> void:
	for made: Node in [_modifier, _head, _upright]:
		if made != null and is_instance_valid(made):
			made.get_parent().remove_child(made)
			made.queue_free()
	_modifier = null
	_head = null
	_upright = null
	_eye_of = null
	_eye = null
	var skeleton := model.skeleton() if model != null else null
	if skeleton == null:
		return
	_modifier = AimOffsetModifier.new()
	_modifier.name = _MODIFIER
	_modifier.chain = chain
	_modifier.weights = chain_weights
	_modifier.active = false
	_modifier.influence = 0.0
	skeleton.add_child(_modifier)
	_place(skeleton)
	_head = AimHeadModifier.new()
	_head.name = _HEAD_MODIFIER
	_head.active = false
	_head.influence = 0.0
	skeleton.add_child(_head)
	skeleton.move_child(_head, _modifier.get_index() + 1)
	_upright = AimUprightModifier.new()
	_upright.name = _UPRIGHT_MODIFIER
	_upright.chain = chain
	_upright.weights = chain_weights
	_upright.active = false
	_upright.influence = 0.0
	skeleton.add_child(_upright)
	skeleton.move_child(_upright, _head.get_index())
	refresh()


# The modifiers run in the order of the skeleton's children: after the grip, before the arm.
func _place(skeleton: Skeleton3D) -> void:
	var at := 0
	if hold != null:
		var grip := hold.grip_modifier()
		if grip != null:
			at = grip.get_index() + 1
	if _modifier.get_index() > at:
		skeleton.move_child(_modifier, at)
	elif _modifier.get_index() < at:
		skeleton.move_child(_modifier, at - 1)


# How much of the body a reload holds now, or the slide's rack after it (kit #1337): the aim gives
# way to both, whose clips hold the weapon in front of the chest.
func _reloading() -> float:
	return maxf(animation.reload_progress().x, animation.rack.progress().x)


func _racking() -> bool:
	return animation.rack.progress().x > 0.0
