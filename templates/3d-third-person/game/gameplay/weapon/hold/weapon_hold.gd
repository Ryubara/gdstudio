class_name WeaponHold
extends Node
## Closes the character's hands on the weapon it holds (kit #1001). The weapon rides the right
## hand's bone on a `BoneAttachment3D` (`pistol_held.tscn`); this node adds what the clips lack:
##
## - the right hand's fingers on the grip and the wrist turned under it (`grip_pose`), the index
##   finger along the frame and, as the character aims, on the trigger (`trigger_pose`);
## - while aiming or firing, the left hand on the weapon: the left arm reaches the weapon's
##   `SupportHand` marker (`HoldArm`) and its fingers wrap over the right hand (`support_pose`).
##
## The skeleton is inside the model's `.glb`, which a scene cannot add nodes to, so the three
## modifiers (two `HandPoseModifier`s and a `HoldArm`) are made here, as children of the model's
## `Skeleton3D`, and made again when the model is replaced. Move the `SupportHand` marker in
## `pistol_held.tscn` and the left hand follows, in the running game too. Everything is a pose
## worked out on each machine from the aim amount the game already has: it is cosmetic and never
## sent over a network. With no `animation` set, `held_weight` and `aim_weight` are the caller's.

const _GRIP := &"HoldGrip"
const _SUPPORT_ARM := &"HoldSupportArm"
const _SUPPORT_FINGERS := &"HoldSupportFingers"

@export_group("Nodes")
## The slot that holds the character's model.
@export var model: CharacterModel
## The attachment that carries the weapon on the right hand; its first child is the weapon.
@export var seat: BoneAttachment3D
## The animation whose pistol layer says how far the weapon is held and aimed; none for a
## character posed by hand (a test, a capture).
@export var animation: CharacterAnimation

@export_group("Right hand")
## The right hand's fingers on the grip, the index finger along the frame, and the wrist's turn.
@export var grip_pose: HandPose
## The index finger on the trigger, blended over `grip_pose` as the character aims.
@export var trigger_pose: HandPose
## How far the right hand is on `grip_pose` (0 the clip's own fist).
@export_range(0.0, 1.0, 0.01) var held_weight := 1.0

@export_group("Left hand")
## The left hand's fingers over the right hand and the grip.
@export var support_pose: HandPose
## The weapon's child that marks where the left hand's bone sits while it supports the weapon.
@export var support_marker := ^"SupportHand"
## The bones that reach for the marker: the upper arm, the forearm and the hand.
@export var support_arm: Array[StringName] = [&"upperarm_l", &"lowerarm_l", &"hand_l"]
## Where the left elbow points, in the model's space (out to the left and down).
@export var support_elbow := Vector3(0.6, 0.6, 0.2)
## How far the weapon is aimed: the left hand is on it by this much, and the trigger finger.
@export_range(0.0, 1.0, 0.01) var aim_weight := 0.0

var _skeleton: Skeleton3D
var _grip: HandPoseModifier
var _arm: HoldArm
var _fingers: HandPoseModifier
var _marker: Node3D


func _ready() -> void:
	if model != null:
		model.rig_changed.connect(_build.unbind(1))
	_build.call_deferred()


func _process(_delta: float) -> void:
	refresh()


## Puts the weights on the modifiers now (the frame's own `_process` does it too).
func refresh() -> void:
	if animation != null and animation.tree != null:
		var weights := animation.pistol_weights()
		held_weight = weights.x
		# A dead character's tree is off and the ragdoll holds the arms.
		aim_weight = weights.y if animation.tree.active else 0.0
	if _grip == null or not is_instance_valid(_grip):
		return
	_weigh(_grip, held_weight)
	_grip.second_weight = aim_weight
	if _arm == null:
		return
	_weigh(_arm, held_weight * aim_weight)
	_weigh(_fingers, held_weight * aim_weight)
	if _arm.active:
		# The marker's place in the bone's space: the weapon's seat times the marker's own place.
		_arm.offset = (_marker.get_parent() as Node3D).transform * _marker.transform
		_arm.elbow = support_elbow


## The modifiers this node made on the skeleton now: the grip, then the left arm and fingers.
func modifiers() -> Array[SkeletonModifier3D]:
	var found: Array[SkeletonModifier3D] = []
	if _grip != null and is_instance_valid(_grip):
		found.append(_grip)
		if _arm != null:
			found.append_array([_arm, _fingers])
	return found


## How far the left hand stopped from its marker on the last update, in metres.
func support_shortfall() -> float:
	return _arm.shortfall if _arm != null and is_instance_valid(_arm) else 0.0


# A modifier's weight; written only when it changes, since the setters make the skeleton work.
func _weigh(modifier: SkeletonModifier3D, weight: float) -> void:
	if not is_equal_approx(modifier.influence, weight):
		modifier.influence = weight
	if modifier.active != (weight > 0.0):
		modifier.active = weight > 0.0


# Makes the modifiers on the model's skeleton, after freeing the ones made on the last model.
func _build() -> void:
	for modifier in modifiers():
		# Out of the tree at once, so the new ones can take the names.
		modifier.get_parent().remove_child(modifier)
		modifier.queue_free()
	_grip = null
	_arm = null
	_fingers = null
	_skeleton = model.skeleton() if model != null else null
	if _skeleton == null or seat == null or seat.get_child_count() == 0:
		return
	_grip = HandPoseModifier.new()
	_grip.name = _GRIP
	_grip.pose = grip_pose
	_grip.second = trigger_pose
	_skeleton.add_child(_grip)
	_marker = seat.get_child(0).get_node_or_null(support_marker) as Node3D
	if _marker != null and _marker.get_parent() == seat.get_child(0) and support_arm.size() == 3:
		_arm = HoldArm.new()
		_arm.name = _SUPPORT_ARM
		_arm.arm = support_arm
		_arm.bone = seat.bone_name
		_skeleton.add_child(_arm)
		_fingers = HandPoseModifier.new()
		_fingers.name = _SUPPORT_FINGERS
		_fingers.pose = support_pose
		_skeleton.add_child(_fingers)
	refresh()
