class_name LeftShoulder
extends Node
## The weapon on the left side for a left peek lean (gdstudio #1435). The template's weapons are
## right-handed: leaning left, the head cleared a wall's edge before the muzzle did, which stayed
## right of it, so a left peek needed the edge about 0.2 m closer than a right one and its shot
## could strike the edge it peeked past. By `CharacterPeek.shoulder_share()` (the left lean,
## eased):
##
## - the rifle goes to the left shoulder: its `TwoHandHold` mirrors the shoulder's pocket, the
##   gun's turn across the body and the chest's turn (`TwoHandHold.side`);
## - the pistol goes across the face to the left eye: this node makes a `LeftShoulderCross` and a
##   `HoldArm` on the right arm, right before the `WeaponHold`'s support arm, that move the right
##   hand `pistol_shift` to the left across the leaning chest and turn it so the muzzle stays on
##   the aim point, while the pistol is aimed;
##
## and a weapon with no muzzle (a server's body) mirrors its shot's start
## (`CharacterPeek.lean_offset()`). The hands keep their places on the weapon (the grip, the
## trigger finger and the support hand are solved on the weapon, not on the body), so they close
## on it as on the right. A pose on each machine from the lean the body already has: never sent.

const _CROSS := &"LeftShoulderCross"
const _ARM := &"LeftShoulderArm"
## The support arm the cross runs before (`WeaponHold`'s), so the left hand follows the pistol.
const _SUPPORT_ARM := &"HoldSupportArm"

@export_group("Nodes")
## The character whose lean moves the weapon.
@export var character: Character
## The slot that holds the character's model.
@export var model: CharacterModel
## The pistol's hold: its aim weight says how far the pistol is up, its seat where it rides.
@export var hold: WeaponHold
## The aim layer, whose aim point the moved muzzle is turned back onto.
@export var aim: AimLayer

@export_group("Pistol")
## How far the pistol goes to the left at a whole left lean while aimed, in metres, across the
## leaning chest: from under the right eye to under the left one, where a right lean has it to the
## right.
@export_range(0.0, 0.4, 0.005, "suffix:m") var pistol_shift := 0.19
## The right arm that carries the pistol across: the upper arm, the forearm, the hand.
@export var right_arm: Array[StringName] = [&"upperarm_r", &"lowerarm_r", &"hand_r"]
## On: the pistol stays to the right (`PeekTuning.left_shoulder` off turns the rifle's and the
## server's mirror off too).
@export var disabled := false

## The pistol's share across now (the lean's share times the aim's), for a test.
var share := 0.0

var _cross: LeftShoulderCross
var _arm: HoldArm


func _ready() -> void:
	if hold != null:
		hold.built.connect(_build)
	_build.call_deferred()


func _process(_delta: float) -> void:
	refresh()


## The modifier that moves the right hand, or null.
func cross_modifier() -> LeftShoulderCross:
	return _cross if _cross != null and is_instance_valid(_cross) else null


## Puts the lean's share on the modifiers now (the frame's own `_process` does it too).
func refresh() -> void:
	var cross := cross_modifier()
	if cross == null or character == null or hold == null:
		return
	share = 0.0
	if not disabled and hold.aim_weight > 0.0:
		share = character.peek_motion.shoulder_share(character) * hold.aim_weight
		share *= (1.0 - hold.reload_weight) * (1.0 - hold.rack_weight)
	var muzzle := character.weapon.muzzle if character.weapon != null else null
	var on := share > 0.0 and muzzle != null and muzzle.is_inside_tree() and aim != null
	if cross.active != on:
		cross.active = on
		_arm.active = on
	if not on:
		return
	var skeleton := cross.get_skeleton()
	var to_skeleton := skeleton.global_transform.affine_inverse()
	# Across the leaning chest, not level: to the left and down by the bend's roll, as the
	# mirror of where a right lean holds the pistol (level, it was 20 cm high).
	var facing := model.global_basis.z
	facing = Vector3(facing.x, 0.0, facing.z).normalized()
	var left := Vector3.UP.cross(facing).normalized()
	var peek := character.peek_motion
	var roll := peek.drawn() * peek.full_angle(character, CharacterCapsule.eye_height(character))
	left = left * cos(roll) + Vector3.UP * sin(roll)
	cross.shift = to_skeleton.basis * (left * pistol_shift * share)
	cross.target = to_skeleton * aim.aim_point(Engine.get_physics_interpolation_fraction())
	cross.muzzle_in_hand = _between(muzzle, hold.seat)


## The rifle's turn mirrored to the left side of the body (about the model's side axis, X).
static func mirrored(turn: Quaternion) -> Quaternion:
	return Quaternion(turn.x, -turn.y, -turn.z, turn.w)


# Makes the cross and its arm on the model's skeleton right before the hold's support arm (or
# last), after freeing the ones made on the last model.
func _build() -> void:
	for made: Node in [_cross, _arm]:
		if made != null and is_instance_valid(made):
			made.get_parent().remove_child(made)
			made.queue_free()
	_cross = null
	_arm = null
	var skeleton := model.skeleton() if model != null else null
	if skeleton == null:
		return
	_arm = HoldArm.new()
	_arm.name = _ARM
	_arm.arm = right_arm
	_arm.bone = &""
	_arm.keep_elbow = 1.0
	_arm.active = false
	_cross = LeftShoulderCross.new()
	_cross.name = _CROSS
	_cross.hand_bone = right_arm[2] if right_arm.size() == 3 else &"hand_r"
	_cross.arm = _arm
	_cross.active = false
	skeleton.add_child(_cross)
	skeleton.add_child(_arm)
	var support := skeleton.get_node_or_null(NodePath(String(_SUPPORT_ARM)))
	if support != null:
		skeleton.move_child(_cross, support.get_index())
		skeleton.move_child(_arm, support.get_index())
	refresh()


# A node's transform in the space of `top`, one of its parents, from the transforms between (no
# global transform is asked for: the pistol's attachment follows the skeleton a frame late).
static func _between(node: Node3D, top: Node) -> Transform3D:
	var xf := node.transform
	var above := node.get_parent() as Node3D
	while above != null and above != top:
		xf = above.transform * xf
		above = above.get_parent() as Node3D
	return xf
