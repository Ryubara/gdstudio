class_name WeaponHold
extends Node
## Closes the character's hands on the weapon it holds (kit #1001). The weapon rides the right
## hand's bone on a `BoneAttachment3D` (`pistol_held.tscn`); this node adds what the clips lack:
##
## - the right hand's fingers on the grip and the wrist turned under it (`grip_pose`), the index
##   finger along the frame and, as the character aims, on the trigger (`trigger_pose`), and the
##   arm held a little out from the thigh while the weapon is carried (`carry_arm_out`);
## - while aiming or firing, the left hand on the weapon: the left arm reaches the weapon's
##   `SupportHand` marker (`HoldArm`) and its fingers wrap over the right hand (`support_pose`);
## - through a reload, the left hand where the reload clip means it to be (kit #1031): on the
##   weapon until the clip takes it away, the clip's own arm while it fetches the new magazine at
##   the belt, up the grip's line to the magazine's foot and under it while it goes in (the
##   `MagazineHand` marker, `magazine_pose`), and round the grip's foot onto the weapon again.
##   The clip gives the times (the Reload group's shares of `Pistol_Reload`);
## - the left hand's one way on and off the weapon (kit #1051): its fingers open where it holds
##   (`open_pose`), then the opened hand leaves along `support_way`, and it comes on the same way
##   backwards, for the aim and from the magazine alike. `SupportHandPlan` says where on all of
##   this the hand is now, and holds the reload's phases.
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
## Where the index finger is half-way between the frame and the trigger (kit #1079): it leaves
## the trigger guard on its own side before it lifts, so it never crosses the left thumb, which
## lies along the frame on the other side. Solved with the poses, never typed.
@export var trigger_way_pose: HandPose
## How far the right hand is on `grip_pose` (0 the clip's own fist).
@export_range(0.0, 1.0, 0.01) var held_weight := 1.0
## The arm that carries the weapon, and how many degrees it is held out from the body while the
## weapon is carried: a hand closed on a grip is wider than the clips' open hand, and with the arm
## hanging as the clips have it the grip's foot would be in the thigh. It goes back as the
## character aims (the aim clips hold the weapon clear of the body).
@export var carry_arm: StringName = &"upperarm_r"
@export_range(0.0, 30.0, 0.5) var carry_arm_out := 8.0

@export_group("Left hand")
## The left hand's fingers over the right hand and the grip.
@export var support_pose: HandPose
## The weapon's child that marks where the left hand's bone sits while it supports the weapon.
@export var support_marker := ^"SupportHand"
## The bones that reach for the marker: the upper arm, the forearm and the hand.
@export var support_arm: Array[StringName] = [&"upperarm_l", &"lowerarm_l", &"hand_l"]
## Where the left elbow points, in the model's space (out to the left and down).
@export var support_elbow := Vector3(0.6, 0.6, 0.2)
## The left hand opened where it holds: the first step of its way off the weapon, and the last
## of its way on.
@export var open_pose: HandPose
## The line the opened left hand leaves the weapon along, from its place on it, in the weapon's
## own space: its far end is where the clip's arm takes the hand, and where it comes in from.
## Solved with `open_pose` (the clear line nearest the way to the belt), never typed.
@export var support_way := Vector3(0.0, 0.0, 0.06)
## How far the weapon is aimed: the left hand is on it by this much, and the trigger finger.
@export_range(0.0, 1.0, 0.01) var aim_weight := 0.0

@export_group("Reload")
## The left hand's fingers while the heel of its palm pushes the magazine in.
@export var magazine_pose: HandPose
## The weapon's child that marks where the left hand's bone sits while it pushes the magazine in.
@export var magazine_marker := ^"MagazineHand"
## Where the left hand starts from under the magazine, from its place there, in the weapon's own
## space: the new magazine's length down the grip, since the magazine goes in ahead of the palm.
@export var magazine_approach := Vector3(0.0, -0.1, 0.0)
## How far the left hand bows out, in the weapon's own space, half-way from under the magazine
## to the far end of `support_way` (it goes round the grip's foot, not through it).
@export var return_clearance := Vector3(0.0, -0.04, 0.04)
## The shares of the reload clip between which the left hand lets go of the weapon: it opens and
## leaves along `support_way` first, and after the second the clip's own arm has it (the reach to
## the belt for the new magazine).
@export var reload_leave := Vector2(0.02, 0.1)
## The shares between which the left hand comes from the clip's arm to the line under the magazine.
@export var reload_reach := Vector2(0.3, 0.4)
## The shares between which it pushes the magazine up into the grip.
@export var reload_insert := Vector2(0.4, 0.54)
## The shares between which it goes from the magazine back to its place on the weapon: down off
## the magazine, across to the far end of `support_way`, in along it, and the fingers close.
@export var reload_return := Vector2(0.71, 0.88)
## How much of the upper body the reload clip holds now (it fades in and out), and the share of the
## clip that has played; from `animation`, or the caller's for a character posed by hand.
@export_range(0.0, 1.0, 0.01) var reload_weight := 0.0
@export_range(0.0, 1.0, 0.01) var reload_share := 0.0

var _skeleton: Skeleton3D
var _grip: HandPoseModifier
var _arm: HoldArm
var _fingers: HandPoseModifier
var _marker: Node3D
var _magazine: Node3D
# Where the left hand is now: on its way on or off the weapon, at the magazine, with the clip.
var _left := SupportHandPlan.new()


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
		var reload := animation.reload_progress() if animation.tree.active else Vector2.ZERO
		reload_weight = reload.x
		reload_share = reload.y
	if _grip == null or not is_instance_valid(_grip):
		return
	_weigh(_grip, held_weight)
	# The finger leaves the trigger for the reload.
	_grip.second_weight = aim_weight * (1.0 - reload_weight)
	_grip.swing_bone = carry_arm
	_grip.swing_degrees = carry_arm_out * (1.0 - aim_weight)
	if _arm == null:
		return
	_plan_left()
	_weigh(_arm, held_weight * _left.arm)
	_weigh(_fingers, held_weight * _left.arm)
	if _arm.active:
		# The hand's place in the weapon: where it holds, moved out along its way; from the reach
		# of a reload on, blended with its place under the magazine, down the approach line.
		var place := _marker.transform
		place.origin += support_way * _left.off
		if _magazine != null and _left.at_magazine > 0.0:
			var under := _magazine.transform
			under.origin += magazine_approach * _left.down
			place = place.interpolate_with(under, _left.at_magazine)
			place.origin += return_clearance * sin(PI * _left.across)
		# In the bone's space: the weapon's seat times the place in the weapon.
		var weapon := (_marker.get_parent() as Node3D).transform
		_arm.offset = weapon * place
		_arm.elbow = support_elbow
		# An arm too short for the place (the aim coming up, the weapon still out to the side)
		# backs the hand off along its way, opened; under the magazine it has no such line.
		_arm.retreat = weapon.basis * support_way if _left.at_magazine <= 0.0 else Vector3.ZERO
		_fingers.second_weight = _left.magazine_fingers
		_fingers.open_weight = _left.opened


## How far the left hand is on the weapon's support marker or its way (x) and at its magazine (y)
## now; together at most 1, and what is left is the clip's own arm.
func support_weights() -> Vector2:
	_plan_left()
	return Vector2(_left.arm * (1.0 - _left.at_magazine), _left.arm * _left.at_magazine)


## The left hand's plan now: the reload's phase and where on its way the hand is, for whatever
## moves with it (read it, never write it).
func left_hand() -> SupportHandPlan:
	_plan_left()
	return _left


# Where the left hand is now (`SupportHandPlan`): aiming brings it on the weapon, and a reload
# takes it through the clip's steps by as much as the reload clip holds the body. A weapon with
# no magazine marker has no reload to follow.
func _plan_left() -> void:
	_left.leave = reload_leave
	_left.reach = reload_reach
	_left.insert = reload_insert
	_left.back = reload_return
	_left.update(aim_weight, reload_weight if _magazine != null else 0.0, reload_share)


## The modifiers this node made on the skeleton now: the grip, then the left arm and fingers.
func modifiers() -> Array[SkeletonModifier3D]:
	var found: Array[SkeletonModifier3D] = []
	if _grip != null and is_instance_valid(_grip):
		found.append(_grip)
		if _arm != null:
			found.append_array([_arm, _fingers])
	return found


## How far the left hand stopped from its place on the last update, in metres.
func support_shortfall() -> float:
	return _arm.shortfall if _arm != null and is_instance_valid(_arm) else 0.0


## How far the left arm backed the hand off along `support_way` on the last update because it was
## too short for the hand's place, in metres (0 when it reached).
func support_backed() -> float:
	return _arm.backed if _arm != null and is_instance_valid(_arm) else 0.0


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
	_grip.second_via = trigger_way_pose
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
		_fingers.second = magazine_pose
		_fingers.open = open_pose
		_arm.opener = _fingers
		_magazine = seat.get_child(0).get_node_or_null(magazine_marker) as Node3D
		_skeleton.add_child(_fingers)
	refresh()
