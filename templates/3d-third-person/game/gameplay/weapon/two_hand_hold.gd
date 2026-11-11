@tool
class_name TwoHandHold
extends Node3D
## How a character holds a long gun with both hands when the animation library has no clip for it
## (the Universal Animation Library has pistol clips only): the gun sits with its butt in the right
## shoulder's pocket, low and across the body at rest and at the shoulder along the view when the
## character aims or shoots, the chest turns the left shoulder forward so the left arm reaches, and
## a two-bone IK puts each hand on its marker on the gun. The legs and the head stay on the
## locomotion clips. `two_hand_hold.tscn` is the part with no gun; the rifle's
## `gameplay/weapon/rifle_held.tscn` inherits it and puts the rifle and the hands' targets under
## `Pivot`.
##
## The parts a person tunes are scene nodes: `Pivot` (the shoulder's pocket, which this node moves
## and turns), the gun under it, the hands' targets on the gun (`RightHandTarget`,
## `LeftHandTarget`: move one to move the hand) and the elbows' pole markers (`RightPole`,
## `LeftPole`, in the model's space). The engine's modifiers that bend the arms are made at run
## time on the model's skeleton (they belong to whatever model the `CharacterModel` slot holds):
## the stance (`TwoHandStance`: places the pocket, turns the chest), then per arm a `TwoBoneIK3D`
## and a `CopyTransformModifier3D` that turns the hand to its target.
##
## It is a child of the character's `Model` slot, shown by the `WeaponLoadout` while its weapon is
## in the hands (the definition's `view`). The pose is cosmetic: it is worked out on each machine
## from what the character already has (`aim_amount`, `view_pitch`, the weapon's shots and
## reload) and never sent.

const STANCE_SCRIPT := preload("res://gameplay/weapon/two_hand_stance.gd")
const _MODIFIER_PREFIX := "TwoHandHold_"

@export_group("Nodes")
## The character holding it. Empty: the `Model` slot's parent.
@export var character: Character

@export_group("Stance")
## Where the butt sits when aiming, from the chest bone (`chest_bone`) in the model's space (+Z
## forward, +X the model's left). The chest's place comes from the clip, so a crouch or a lean
## carries the gun with it.
@export var aim_pocket := Vector3(-0.124, 0.12, 0.109)
## Where it sits at rest (the low ready).
@export var low_pocket := Vector3(-0.114, 0.06, 0.109)
## How far the muzzle points down at rest.
@export_range(0.0, 80.0, 0.5, "suffix:deg") var low_pitch := 35.0
## How far the muzzle points across the body at rest (toward the left).
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var low_yaw := 20.0
## How far the chest turns about the model's up axis, split over the spine bones; negative brings
## the left shoulder forward so the left hand reaches the fore-end.
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var chest_turn := -30.0
## The most the gun follows the view up or down.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var pitch_limit := 60.0
## Seconds from the low ready to the shoulder (and back).
@export_range(0.01, 2.0, 0.01, "suffix:s") var raise_time := 0.15
## Seconds the gun stays at the shoulder after a shot fired from the low ready.
@export_range(0.0, 3.0, 0.05, "suffix:s") var shot_hold_time := 0.6

@export_group("Recoil")
## How far a shot pushes the gun back along the barrel.
@export_range(0.0, 0.2, 0.001, "suffix:m") var kick_distance := 0.02
## How far a shot tips the muzzle up.
@export_range(0.0, 20.0, 0.1, "suffix:deg") var kick_degrees := 2.0
## Seconds for the gun to come back from a kick.
@export_range(0.01, 1.0, 0.01, "suffix:s") var kick_recover_time := 0.08

@export_group("Reload")
## Where the left hand takes the magazine down to during a reload, from its place on the gun, in
## the model's space (down and back, to the belt).
@export var reload_reach := Vector3(0.05, -0.28, -0.12)
## The magazine node under the gun that leaves with the left hand. Empty: none moves.
@export var magazine: NodePath
## The far level's magazine, moved and hidden with it. Empty: none.
@export var magazine_far: NodePath

@export_group("Bones")
## The bone whose place the pocket follows.
@export var chest_bone: StringName = &"spine_03"
## The bones the chest turn spreads over.
@export var spine_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
## The right arm: upper arm, forearm, hand.
@export var right_arm: Array[StringName] = [&"upperarm_r", &"lowerarm_r", &"hand_r"]
## The left arm.
@export var left_arm: Array[StringName] = [&"upperarm_l", &"lowerarm_l", &"hand_l"]

var _skeleton: Skeleton3D
var _modifiers: Array[SkeletonModifier3D] = []
var _raised := 0.0
var _shot_left := 0.0
var _kick := 0.0
var _left_rest := Transform3D.IDENTITY
var _magazine_rest := Transform3D.IDENTITY
var _weapon: Weapon
# The scene's parts, found once by name.
var _found := {}


func _ready() -> void:
	var left := _node(&"LeftHandTarget")
	if left != null:
		_left_rest = left.transform
	var mag := get_node_or_null(magazine) as Node3D
	if mag != null:
		_magazine_rest = mag.transform
	if Engine.is_editor_hint():
		return
	if character == null and get_parent() != null:
		character = get_parent().get_parent() as Character
	var slot := get_parent() as CharacterModel
	if slot != null:
		slot.rig_changed.connect(_on_rig_changed.unbind(1))
	visibility_changed.connect(_update_active)
	if character != null:
		character.died.connect(_update_active)
		character.revived.connect(_update_active)
		_weapon = character.weapon
		if _weapon != null:
			_weapon.fired.connect(_on_fired.unbind(1))
	_on_rig_changed.call_deferred()


func _exit_tree() -> void:
	_drop_modifiers()


## How far the gun is up at the shoulder: 0 at the low ready, 1 aimed.
func raised_amount() -> float:
	return _raised


## The skeleton modifiers this hold made (the stance, then each arm's IK and hand turn).
func modifiers() -> Array[SkeletonModifier3D]:
	return _modifiers.duplicate()


## Puts the pocket and the gun where they are this frame. The stance modifier calls it while the
## skeleton updates, when the chest bone has the clip's pose of this frame.
func place(skeleton: Skeleton3D, delta: float) -> void:
	var pivot := _node(&"Pivot")
	if pivot == null:
		return
	_step(delta)
	var bone := skeleton.find_bone(chest_bone)
	var chest := Vector3.ZERO
	if bone >= 0:
		var to_here := global_transform.affine_inverse() * skeleton.global_transform
		chest = to_here * skeleton.get_bone_global_pose(bone).origin
	var pitch := 0.0
	if character != null:
		pitch = clampf(rad_to_deg(character.view_pitch), -pitch_limit, pitch_limit)
	var low := Basis(Vector3.RIGHT, deg_to_rad(low_pitch)) * Basis(Vector3.UP, deg_to_rad(low_yaw))
	var aim := Basis(Vector3.RIGHT, deg_to_rad(-pitch - kick_degrees * _kick))
	var turn := low.get_rotation_quaternion().slerp(aim.get_rotation_quaternion(), _raised)
	var pocket := chest + low_pocket.lerp(aim_pocket, _raised)
	var basis_now := Basis(turn)
	pivot.transform = Transform3D(basis_now, pocket - basis_now.z * kick_distance * _kick)
	_place_reload()


## The weight of the hold: 1 while the weapon is up, falling to 0 as a switch puts it away.
func weight() -> float:
	if character == null or character.loadout == null:
		return 1.0
	return 1.0 - character.loadout.lowered_amount()


func _step(delta: float) -> void:
	var wants := 0.0
	if character != null:
		wants = character.aim_amount
	_shot_left = maxf(_shot_left - delta, 0.0)
	if _shot_left > 0.0:
		wants = 1.0
	_raised = move_toward(_raised, wants, delta / maxf(raise_time, 0.001))
	_kick = move_toward(_kick, 0.0, delta / maxf(kick_recover_time, 0.001))
	var share := weight()
	for modifier in _modifiers:
		if modifier is TwoBoneIK3D or modifier is CopyTransformModifier3D:
			modifier.influence = share


# The left hand leaves the gun with the magazine and comes back with a full one, by the weapon's
# reload progress: to the magazine, down to the belt, back up, seated, back on the fore-end.
func _place_reload() -> void:
	var left := _node(&"LeftHandTarget")
	if left == null:
		return
	var progress := -1.0
	if _weapon != null and _weapon.is_reloading() and visible:
		progress = _weapon.reload_progress()
	var mag := get_node_or_null(magazine) as Node3D
	var mag_far := get_node_or_null(magazine_far) as Node3D
	if progress < 0.0:
		left.transform = _left_rest
		_set_magazine(mag, mag_far, _magazine_rest, true)
		return
	# Where the hand is on the way: 0 on the fore-end, 1 on the magazine, 2 at the belt.
	var at := 0.0
	if progress < 0.15:
		at = progress / 0.15
	elif progress < 0.45:
		at = 1.0 + (progress - 0.15) / 0.3
	elif progress < 0.6:
		at = 2.0
	elif progress < 0.8:
		at = 2.0 - (progress - 0.6) / 0.2
	else:
		at = 1.0 - (progress - 0.8) / 0.2
	var rifle_to_here := _rifle_space()
	var on_mag := _magazine_rest
	if mag != null:
		on_mag = (mag.get_parent() as Node3D).transform * _magazine_rest
	var hand_on_mag := Transform3D(_left_rest.basis, on_mag.origin)
	var hand := _left_rest.interpolate_with(hand_on_mag, clampf(at, 0.0, 1.0))
	var drop := clampf(at - 1.0, 0.0, 1.0)
	# The reach is in the model's space; the hand target is on the gun.
	var reach_on_gun := rifle_to_here.basis.inverse() * reload_reach
	hand.origin += reach_on_gun * drop
	left.transform = hand
	var mag_xf := _magazine_rest
	if mag != null:
		var parent_basis := (mag.get_parent() as Node3D).transform.basis
		mag_xf.origin += parent_basis.inverse() * (reach_on_gun * drop)
	_set_magazine(mag, mag_far, mag_xf, drop < 0.9)


# The gun's frame in this node's space (the hands' targets are children of the gun).
func _rifle_space() -> Transform3D:
	var gun := _node(&"LeftHandTarget")
	if gun == null or gun.get_parent() == null:
		return Transform3D.IDENTITY
	var parent := gun.get_parent() as Node3D
	return global_transform.affine_inverse() * parent.global_transform


func _set_magazine(near: Node3D, far: Node3D, xf: Transform3D, shown: bool) -> void:
	for mag: Node3D in [near, far]:
		if mag != null:
			mag.transform = xf
			mag.visible = shown


func _on_fired() -> void:
	if not visible:
		return
	_shot_left = shot_hold_time
	_kick = 1.0


func _on_rig_changed() -> void:
	_drop_modifiers()
	var slot := get_parent() as CharacterModel
	_skeleton = slot.skeleton() if slot != null else null
	if _skeleton == null:
		return
	var stance := STANCE_SCRIPT.new() as SkeletonModifier3D
	stance.name = _MODIFIER_PREFIX + "Stance"
	stance.set(&"hold", self)
	_add_modifier(stance)
	_add_arm(right_arm, _node(&"RightHandTarget"), _node(&"RightPole"), "Right")
	_add_arm(left_arm, _node(&"LeftHandTarget"), _node(&"LeftPole"), "Left")
	_update_active()


func _add_arm(bones: Array[StringName], target: Node3D, pole: Node3D, side: String) -> void:
	if bones.size() < 3 or target == null:
		return
	var ik := TwoBoneIK3D.new()
	ik.name = _MODIFIER_PREFIX + side + "ArmIK"
	_add_modifier(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, bones[0])
	ik.set_middle_bone_name(0, bones[1])
	ik.set_end_bone_name(0, bones[2])
	ik.set_target_node(0, ik.get_path_to(target))
	if pole != null:
		ik.set_pole_node(0, ik.get_path_to(pole))
	var turn := CopyTransformModifier3D.new()
	turn.name = _MODIFIER_PREFIX + side + "HandTurn"
	_add_modifier(turn)
	turn.setting_count = 1
	turn.set_apply_bone_name(0, bones[2])
	turn.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	turn.set_reference_node(0, turn.get_path_to(target))
	turn.set_copy_flags(0, CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION)


func _add_modifier(modifier: SkeletonModifier3D) -> void:
	_skeleton.add_child(modifier)
	_modifiers.append(modifier)


func _drop_modifiers() -> void:
	for modifier in _modifiers:
		if is_instance_valid(modifier):
			modifier.queue_free()
			if modifier.get_parent() != null:
				modifier.get_parent().remove_child(modifier)
	_modifiers.clear()


# The modifiers run only while the gun is shown and the character is alive (a ragdoll owns the
# bones then).
func _update_active() -> void:
	var on := is_visible_in_tree() and (character == null or not character.is_dead())
	for modifier in _modifiers:
		if is_instance_valid(modifier):
			modifier.active = on
	var pivot := _node(&"Pivot")
	if pivot != null:
		pivot.visible = character == null or not character.is_dead()


func _node(node_name: StringName) -> Node3D:
	var known: Variant = _found.get(node_name)
	if is_instance_valid(known) and is_ancestor_of(known):
		return known as Node3D
	var found := _find(node_name)
	_found[node_name] = found
	return found


func _find(node_name: StringName) -> Node3D:
	match node_name:
		&"Pivot":
			return get_node_or_null(^"Pivot") as Node3D
		&"RightPole", &"LeftPole":
			return get_node_or_null(NodePath(String(node_name))) as Node3D
	return find_child(String(node_name), true, false) as Node3D
