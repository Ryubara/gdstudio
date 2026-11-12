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
## reload. It is a pose on each machine from what the body already has (the view's yaw and
## pitch): cosmetic, never sent. A weapon with no muzzle (the fists) turns nothing.
##
## It makes an `AimHeadModifier` after it too (kit #1334): with any weapon, the fists among them,
## the head looks along the aim, level, with the neck on its line, whatever head the clips carry.
## It is on by the aim (the pistol's aim pose, or the character's `aim_amount` eased), less a
## reload.

const _MODIFIER := &"AimOffset"
const _HEAD_MODIFIER := &"AimHead"

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
## On: no turn (the clips alone aim the weapon, as before the layer).
@export var disabled := false

@export_group("Head")
## The neck's share of the head's turn toward the aim (the head takes the rest).
@export_range(0.0, 1.0, 0.01) var head_neck_share := 0.4
## The most the head may turn off the line the chest gives it, in degrees.
@export_range(0.0, 120.0, 0.5, "suffix:deg") var head_max_turn := 90.0
## On: the head keeps the clips' pose while aiming (as before kit #1334).
@export var head_disabled := false

var _modifier: AimOffsetModifier
var _head: AimHeadModifier
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


## The share the head looks along the aim by now (0 the clips' head, 1 all the way): the aim,
## from the aim pose's weight or the character's `aim_amount` eased, less a reload.
func head_weight() -> float:
	if head_disabled or character == null or animation == null or animation.tree == null:
		return 0.0
	if not animation.tree.active or character.aim_limits == null:
		return 0.0
	var aimed := maxf(animation.pistol_weights().y, smoothstep(0.0, 1.0, character.aim_amount))
	return aimed * (1.0 - animation.reload_progress().x)


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
	var reload := animation.reload_progress().x
	return animation.pistol_weights().y * (1.0 - reload)


## Puts the aim on the modifiers now (the frame's own `_process` does it too).
func refresh() -> void:
	_refresh_head()
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
	aim.hold_turn = animation.is_shooting() or animation.is_reloading()
	aim.release_time = release_time


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
	looking.neck_share = head_neck_share
	looking.max_turn = head_max_turn
	looking.target = aim_point(Engine.get_physics_interpolation_fraction())


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
	for made: Node in [_modifier, _head]:
		if made != null and is_instance_valid(made):
			made.get_parent().remove_child(made)
			made.queue_free()
	_modifier = null
	_head = null
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
	refresh()


# The modifiers run in the order of the skeleton's children: after the grip, before the arm.
func _place(skeleton: Skeleton3D) -> void:
	var at := 0
	if hold != null:
		var made := hold.modifiers()
		if not made.is_empty():
			at = made[0].get_index() + 1
	if _modifier.get_index() > at:
		skeleton.move_child(_modifier, at)
	elif _modifier.get_index() < at:
		skeleton.move_child(_modifier, at - 1)
