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
## - the magazines through a reload (kit #1052): the pistol's own leaves the grip and falls when
##   the reload's first sound plays (`DroppedMagazine`, a body of the world for `dropped_life`
##   seconds), a new one is in the left hand from the belt (`carry_pose`) up the grip's line and is
##   the pistol's own again once it is in, and the slide, locked back on an empty pistol, runs
##   forward when the reload's last sound plays (`slide_travel`); a reload cut short leaves the
##   pistol whole;
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
##
## Each body has its own hold (kit #1187): hands of other sizes close on the grip, and on the new
## magazine, with other finger poses and hold the weapon at another seat. The scene's own poses,
## `support_way` and the weapon's seat and markers are the default body's
## (`CharacterBodies.FEMALE`); `fits` holds the others, and the one whose body is the model's
## file is put on when the model is (re)built.

## The modifiers were made again on the model's skeleton (the `AimLayer` places its own after the
## grip).
signal built

const _GRIP := &"HoldGrip"
const _SUPPORT_ARM := &"HoldSupportArm"
const _SUPPORT_FINGERS := &"HoldSupportFingers"
const _HELD_MAGAZINE := &"HoldMagazine"
const _DROPPED_MAGAZINE := &"DroppedMagazine"

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
## The right thumb while the left hand is on the weapon too (kit #1084): it rests on the root of
## the left thumb, which takes its place on the frame, as a two-handed grip is taught. Blended
## over `grip_pose` while the left hand waits at the far end of `support_way`, before it comes in
## (`SupportHandPlan.room`).
@export var thumb_pose: HandPose
## Where the right thumb is half-way between the frame and the left thumb's root: lifted clear of
## the frame's edge, which the straight blend took its middle bone through (2.7 mm on the male
## body). Posed by hand (`tools/hold/pistol_authored.json`), as the trigger finger's way is solved.
@export var thumb_way_pose: HandPose
## How far the right hand is on `grip_pose` (0 the clip's own fist).
@export_range(0.0, 1.0, 0.01) var held_weight := 1.0
## The arm that carries the weapon, and how many degrees it is held out from the body while the
## weapon is carried: a hand closed on a grip is wider than the clips' open hand, and with the arm
## hanging as the clips have it the grip's foot would be in the thigh. It goes back as the
## character aims or reloads (those clips hold the weapon clear of the body).
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
## Where the left hand goes down off the seated magazine before it crosses back, from its place
## under it, in the weapon's own space (the plan takes it `SupportHandPlan.BACK_DOWN_SHARE` of
## this far): straight down from the grip's foot. Back down the magazine's own way in, which
## leans with the grip, the female body's curled index finger passed 2.2 to 2.5 mm deep.
@export var return_down := Vector3(0.0, -0.1, 0.0)
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

@export_group("Magazine")
## The weapon's child that is its magazine (a mesh): it leaves the grip in a reload, and its mesh
## is the one in the left hand and the one that falls.
@export var magazine_part := ^"Pistol/Magazine"
## The left hand's fingers closed on the new magazine, from the belt until the grip's foot comes
## down over them. Solved with the poses, never typed.
@export var carry_pose: HandPose
## The left hand's fingers opened at the belt before they close on the new magazine: the clip's
## fist there would close through it. Solved, never typed.
@export var carry_open_pose: HandPose
## The shares of the way in (0 the magazine's top at the well, 1 seated) over which the fingers go
## from `carry_pose` to `magazine_pose`: the latest that keep them out of the grip. Solved.
@export var carry_release := Vector2(0.4, 0.6)
## The share of the reload clip at which the left hand, down at the belt, takes the new magazine.
@export_range(0.0, 1.0, 0.01) var reload_take := 0.25
## The share of the reload clip at which the old magazine leaves the grip, when the hold has no
## weapon definition to read it from (the definition's first reload sound, the magazine out).
@export_range(0.0, 1.0, 0.01) var reload_drop := 0.2
## How fast the old magazine leaves the grip, down its line, in metres a second (the weapon's own
## motion is added).
@export_range(0.0, 5.0, 0.05) var drop_speed := 0.5
## How long the old magazine lies in the world before it goes, in seconds (one a character: the
## next reload takes it back).
@export_range(0.0, 60.0, 0.5) var dropped_life := 8.0
## What the old magazine falls onto (it is on no layer: nothing meets it, no shot, no camera).
@export_flags_3d_physics var dropped_mask := PhysicsLayers.WORLD | PhysicsLayers.PROPS

@export_group("Slide")
## The weapon's child that is its slide: locked back while the weapon is empty, it runs forward
## when the reload's last sound plays (the slide released).
@export var slide_part := ^"Pistol/Slide"
## How far the slide stands back while it is locked, along the weapon's +X, in metres.
@export_range(0.0, 0.1, 0.001) var slide_travel := 0.04
## The share of the reload clip at which the slide runs forward, when the hold has no weapon
## definition to read it from (the definition's last reload sound).
@export_range(0.0, 1.0, 0.01) var reload_slide := 0.85

@export_group("Bodies")
## Holds solved on other bodies than the one the scene's own poses and the weapon's seat and
## markers were solved on (`HoldFit`, written by `tools/hold/write_hold.gd`): a model whose file
## is a fit's `body` gets that fit's seat, markers, way and poses; any other model the scene's own.
@export var fits: Array[HoldFit] = []

var _skeleton: Skeleton3D
var _grip: HandPoseModifier
var _arm: HoldArm
var _fingers: HandPoseModifier
var _marker: Node3D
var _magazine: Node3D
# The pistol's own magazine and slide, the new magazine on the left hand's bone and the old one
# once it fell; where the pistol's magazine was on the last frame, for the speed it falls with.
var _gun_magazine: Node3D
var _held_magazine: BoneAttachment3D
var _dropped: RigidBody3D
var _dropped_left := 0.0
var _magazine_was := Vector3.ZERO
var _magazine_speed := Vector3.ZERO
var _magazine_followed := false
# What this node last showed of the two magazines (the nodes are written only on a change).
var _shown_in_gun := true
var _shown_in_hand := false
var _slide: Node3D
var _slide_rest := Transform3D.IDENTITY
var _slide_released := false
# Whether this node has the slide back now (what it last wrote).
var _slide_locked := false
# Where the left hand is now: on its way on or off the weapon, at the magazine, with the clip.
var _left := SupportHandPlan.new()
# The scene's own hold as a fit, kept the first time a model is built, for a model with no fit.
var _own: HoldFit


func _ready() -> void:
	if model != null:
		model.rig_changed.connect(_build.unbind(1))
	_build.call_deferred()


func _process(delta: float) -> void:
	# The magazine's speed is only wanted where it drops: it is followed through a reload alone
	# (its place in the world is the skeleton's work to give; kit #1052's cost a character).
	if reload_weight <= 0.0:
		_magazine_followed = false
	elif _gun_magazine != null and is_instance_valid(_gun_magazine) and delta > 0.0:
		var at := _gun_magazine.global_position
		_magazine_speed = (at - _magazine_was) / delta if _magazine_followed else Vector3.ZERO
		_magazine_was = at
		_magazine_followed = true
	if _dropped != null and _dropped_left > 0.0:
		_dropped_left -= delta
		if _dropped_left <= 0.0:
			_park_dropped()
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
	# The arm comes back in for a reload as for the aim: the reload clip holds the weapon in front of
	# the body, and swung out the weapon was past the left hand's reach (13 mm on the Quaternius male,
	# 9 to 29 mm on the prototype bodies at the clip's start and end: kit #1187).
	_grip.swing_degrees = carry_arm_out * (1.0 - aim_weight) * (1.0 - reload_weight)
	if _arm == null:
		return
	_plan_left()
	_place_magazines()
	_place_slide()
	# The right thumb makes room while the left hand waits at the far end of its way, before it
	# comes in, and lies on the weapon again once that hand is back out there.
	_grip.open_weight = _left.room
	_weigh(_arm, held_weight * _left.arm)
	# The fingers hold the new magazine at the belt too, where the clip's arm has the hand.
	var fingers := maxf(_left.arm, _left.fingers)
	_weigh(_fingers, held_weight * fingers)
	_fingers.third_weight = _left.carry
	_fingers.third_open_weight = _left.carry_open
	_fingers.second_weight = _left.magazine_fingers
	_fingers.open_weight = _left.opened
	if _arm.active:
		# The hand's place in the weapon: where it holds, moved out along its way; from the reach
		# of a reload on, blended with its place under the magazine, down the approach line.
		var place := _marker.transform
		place.origin += support_way * _left.off
		if _magazine != null and _left.at_magazine > 0.0:
			var under := _magazine.transform
			under.origin += magazine_approach * (_left.down - _left.down_back)
			under.origin += return_down * _left.down_back
			place = place.interpolate_with(under, _left.at_magazine)
			place.origin += return_clearance * sin(PI * _left.across)
		# In the bone's space: the weapon's seat times the place in the weapon.
		var weapon := (_marker.get_parent() as Node3D).transform
		_arm.offset = weapon * place
		_arm.elbow = support_elbow
		# An arm too short for the place (the aim coming up, the weapon still out to the side)
		# backs the hand off along its way, opened; under the magazine it has no such line.
		_arm.retreat = weapon.basis * support_way if _left.at_magazine <= 0.0 else Vector3.ZERO


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
	if reload_weight > 0.0:
		_left.drop = _sound_share(0, reload_drop)
	_left.take = reload_take
	_left.carry_release = carry_release
	_left.update(aim_weight, reload_weight if _magazine != null else 0.0, reload_share)


## The modifiers this node made on the skeleton now: the grip, then the left arm and fingers.
func modifiers() -> Array[SkeletonModifier3D]:
	var found: Array[SkeletonModifier3D] = []
	if _grip != null and is_instance_valid(_grip):
		found.append(_grip)
		if _arm != null:
			found.append_array([_arm, _fingers])
	return found


## The new magazine on the left hand's bone (its child is the mesh), or null.
func held_magazine() -> BoneAttachment3D:
	return _held_magazine


## The old magazine that fell in the last reload, or null before the first.
func dropped_magazine() -> RigidBody3D:
	return _dropped


## How far the left hand stopped from its place on the last update, in metres.
func support_shortfall() -> float:
	return _arm.shortfall if _arm != null and is_instance_valid(_arm) else 0.0


## How far the left arm backed the hand off along `support_way` on the last update because it was
## too short for the hand's place, in metres (0 when it reached).
func support_backed() -> float:
	return _arm.backed if _arm != null and is_instance_valid(_arm) else 0.0


# The share of the reload clip at which the held weapon's reload sound `index` plays (from its end
# when negative), or `fallback` for a hold with no definition to read.
func _sound_share(index: int, fallback: float) -> float:
	var definition := animation.held_definition() if animation != null else null
	if definition == null or definition.reload_sound_at.is_empty():
		return fallback
	var shares := definition.reload_sound_at
	return shares[index if index >= 0 else shares.size() + index]


# Shows the pistol's magazine or the new one in the hand as the plan has them, and drops the old
# one as it leaves the grip.
func _place_magazines() -> void:
	var in_gun := _left.magazine_in_gun
	var in_hand := _left.magazine_in_hand
	if in_gun == _shown_in_gun and in_hand == _shown_in_hand:
		return
	if _gun_magazine == null or not is_instance_valid(_gun_magazine):
		return
	if _shown_in_gun and not in_gun:
		_drop()
	_shown_in_gun = in_gun
	_shown_in_hand = in_hand
	_gun_magazine.visible = in_gun
	if _held_magazine != null:
		_held_magazine.visible = in_hand


# The old magazine leaves the grip: a body of the world where the pistol's was, falling down the
# grip's line with the weapon's own motion. One a character, made the first time.
func _drop() -> void:
	if _dropped == null:
		_dropped = _make_dropped()
		add_child(_dropped)
	_dropped.process_mode = Node.PROCESS_MODE_INHERIT
	_dropped.visible = true
	_dropped.global_transform = _gun_magazine.global_transform
	_dropped.linear_velocity = (
		_magazine_speed - _gun_magazine.global_basis.y.normalized() * drop_speed
	)
	_dropped.angular_velocity = Vector3.ZERO
	_dropped_left = dropped_life


# Takes the old magazine out of the world (out of the physics too) until the next reload.
func _park_dropped() -> void:
	_dropped.visible = false
	_dropped.process_mode = Node.PROCESS_MODE_DISABLED


# A body for the old magazine: the pistol's magazine mesh in a box of its size, on no layer.
func _make_dropped() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = _DROPPED_MAGAZINE
	body.collision_layer = 0
	body.collision_mask = dropped_mask
	body.continuous_cd = true
	body.mass = 0.1
	var shown := (_gun_magazine as MeshInstance3D).mesh
	var mesh := MeshInstance3D.new()
	mesh.mesh = shown
	body.add_child(mesh)
	var bounds := shown.get_aabb()
	var box := BoxShape3D.new()
	box.size = bounds.size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = bounds.get_center()
	body.add_child(shape)
	return body


# The slide: back while the weapon is empty, until the reload's last sound releases it. The node
# is written only when that changes, so whatever else moves it between (the hand that racks it,
# `SlideRack`) is not put back every frame.
func _place_slide() -> void:
	if _slide == null or not is_instance_valid(_slide):
		return
	var empty := false
	var character := animation.character if animation != null else null
	if character != null and character.weapon != null:
		var ammo: Variant = character.weapon.ammo
		empty = ammo is int and ammo == 0
	if not empty:
		_slide_released = false
	elif reload_weight > 0.0 and reload_share >= _sound_share(-1, reload_slide):
		_slide_released = true
	var locked := empty and not _slide_released
	if locked == _slide_locked:
		return
	_slide_locked = locked
	var place := _slide_rest
	if locked:
		place.origin += _slide_rest.basis.x.normalized() * slide_travel
	_slide.transform = place


# A node's place in `root`'s space, from the transforms between them.
static func _in(node: Node3D, root: Node3D) -> Transform3D:
	var place := Transform3D.IDENTITY
	var cursor := node
	while cursor != null and cursor != root:
		place = cursor.transform * place
		cursor = cursor.get_parent() as Node3D
	return place


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
	if _held_magazine != null and is_instance_valid(_held_magazine):
		_held_magazine.get_parent().remove_child(_held_magazine)
		_held_magazine.queue_free()
	_held_magazine = null
	_gun_magazine = null
	if _slide != null and is_instance_valid(_slide) and _slide_locked:
		# The same weapon may be built on again: its slide is at rest when its place is read.
		_slide.transform = _slide_rest
	_slide_locked = false
	_slide = null
	_skeleton = model.skeleton() if model != null else null
	if _skeleton == null or seat == null or seat.get_child_count() == 0:
		built.emit()
		return
	_fit_body()
	_grip = HandPoseModifier.new()
	_grip.name = _GRIP
	_grip.pose = grip_pose
	_grip.second = trigger_pose
	# The trigger finger's pose between is a way of one stop (`HandPoseModifier.second_way`).
	var trigger_way: Array[HandPose] = []
	if trigger_way_pose != null:
		trigger_way.append(trigger_way_pose)
	_grip.second_way = trigger_way
	_grip.open = thumb_pose
	_grip.open_via = thumb_way_pose
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
		_fingers.third = carry_pose
		_fingers.third_open = carry_open_pose
		_arm.opener = _fingers
		_magazine = seat.get_child(0).get_node_or_null(magazine_marker) as Node3D
		_skeleton.add_child(_fingers)
		_build_magazines(seat.get_child(0) as Node3D)
	refresh()
	built.emit()


# The new magazine on the left hand's bone, placed as the pistol's own is seen from the magazine
# marker (where the hand's bone sits under it), so it is where the pistol's will be once it is in;
# and the slide's place at rest.
func _build_magazines(weapon: Node3D) -> void:
	_gun_magazine = weapon.get_node_or_null(magazine_part) as Node3D
	_slide = weapon.get_node_or_null(slide_part) as Node3D
	if _slide != null:
		_slide_rest = _slide.transform
		_slide_released = false
	if _gun_magazine == null or not _gun_magazine is MeshInstance3D or _magazine == null:
		_gun_magazine = null
		return
	_gun_magazine.visible = true
	_shown_in_gun = true
	_shown_in_hand = false
	_magazine_followed = false
	_held_magazine = BoneAttachment3D.new()
	_held_magazine.name = _HELD_MAGAZINE
	_held_magazine.bone_name = support_arm[2]
	_held_magazine.visible = false
	var mesh := MeshInstance3D.new()
	mesh.mesh = (_gun_magazine as MeshInstance3D).mesh
	mesh.transform = _magazine.transform.affine_inverse() * _in(_gun_magazine, weapon)
	_held_magazine.add_child(mesh)
	# In the model slot beside the weapon's seat, so the slot puts its mesh on the body's layers
	# as it does every mesh of the model (the minimap, the inventory's preview).
	# The path is set before it enters the tree, where the attachment connects to the skeleton.
	_held_magazine.use_external_skeleton = true
	_held_magazine.external_skeleton = NodePath("../%s" % model.get_path_to(_skeleton))
	model.add_child(_held_magazine)


## The fit in use now: the one whose `body` is the model's file, or the scene's own.
func fit() -> HoldFit:
	var found := HoldFit.chosen(fits, model)
	return found if found != null else _own


# Puts the fit of the model's body on the weapon's seat and markers and on this node's poses and
# way, keeping the scene's own first.
func _fit_body() -> void:
	var weapon := seat.get_child(0) as Node3D
	var support := weapon.get_node_or_null(support_marker) as Node3D
	var magazine := weapon.get_node_or_null(magazine_marker) as Node3D
	if _own == null:
		_own = HoldFit.new()
		_own.seat = weapon.transform
		_own.support_hand = support.transform if support != null else Transform3D.IDENTITY
		_own.magazine_hand = magazine.transform if magazine != null else Transform3D.IDENTITY
		_own.support_way = support_way
		_own.grip_pose = grip_pose
		_own.trigger_pose = trigger_pose
		_own.trigger_way_pose = trigger_way_pose
		_own.thumb_pose = thumb_pose
		_own.thumb_way_pose = thumb_way_pose
		_own.support_pose = support_pose
		_own.magazine_pose = magazine_pose
		_own.open_pose = open_pose
		_own.carry_pose = carry_pose
		_own.carry_open_pose = carry_open_pose
		_own.magazine_approach = magazine_approach
		_own.carry_release = carry_release
	var chosen := fit()
	weapon.transform = chosen.seat
	if support != null:
		support.transform = chosen.support_hand
	if magazine != null:
		magazine.transform = chosen.magazine_hand
	support_way = chosen.support_way
	grip_pose = chosen.grip_pose
	trigger_pose = chosen.trigger_pose
	trigger_way_pose = chosen.trigger_way_pose
	thumb_pose = chosen.thumb_pose
	thumb_way_pose = chosen.thumb_way_pose
	support_pose = chosen.support_pose
	magazine_pose = chosen.magazine_pose
	open_pose = chosen.open_pose
	carry_pose = chosen.carry_pose
	carry_open_pose = chosen.carry_open_pose
	magazine_approach = chosen.magazine_approach
	carry_release = chosen.carry_release
