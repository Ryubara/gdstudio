@tool
class_name TwoHandHold
extends Node3D
## How a character holds a long gun with both hands when the animation library has no clip for it
## (the Universal Animation Library has pistol clips only): the gun sits with its butt in the right
## shoulder's pocket, low and across the body at rest and at the shoulder along the view when the
## character aims or shoots, the chest turns the left shoulder forward so the left arm reaches, each
## arm reaches its hand's place on the gun, and the fingers close on it: the right hand on the
## pistol grip with the index finger along the receiver (on the trigger while the gun is up), the
## left hand cupped under the hand guard. Both hands stay on the gun in every state; only a reload
## takes the left hand away, to the magazine and the belt and back. The legs and the head stay on
## the locomotion clips. `two_hand_hold.tscn` is the part with no gun; the rifle's
## `gameplay/weapon/rifle_held.tscn` inherits it and puts the rifle and the hands' places under
## `Pivot`.
##
## The parts a person tunes are scene nodes: `Pivot` (the shoulder's pocket, which this node moves
## and turns), the gun under it, the hands' places on the gun (`RightHandTarget`,
## `LeftHandTarget` and `MagazineHand`, where each hand's bone sits: written with the finger poses
## by `tools/hold/solve_rifle_hold.py`, so the skin meets the gun) and the elbows' pole markers
## (`RightPole`, `LeftPole`, in the model's space). The modifiers that bend the arms and close the
## fingers are made at run time on the model's skeleton (they belong to whatever model the
## `CharacterModel` slot holds): the stance (`TwoHandStance`: places the pocket, turns the chest,
## hands each arm its place of this update), a `HoldArm` per arm and a `HandPoseModifier` per hand.
##
## A switch is one sequence with the loadout's own times. Going away, the gun goes down to its
## `stow` place with both hands on it and is hidden there, in the tick the next weapon appears in
## the right hand, and the arms go from the gun's places to the next weapon's pose while that one
## comes up. Coming out, the arms go to the stow place while the last weapon goes down, the gun
## appears in the hands there and comes up. So no frame shows the gun without the hands on it.
##
## It is a child of the character's `Model` slot, shown by the `WeaponLoadout` while its weapon is
## in the hands (the definition's `view`). The pose is cosmetic: it is worked out on each machine
## from what the character already has (`aim_amount`, `view_pitch`, the weapon's shots and reload,
## the loadout's switch) and never sent. With no `character` (a figure posed by hand: a test, a
## capture) the `posed_` values are the caller's.

const STANCE_SCRIPT := preload("res://gameplay/weapon/two_hand_stance.gd")
const _MODIFIER_PREFIX := "TwoHandHold_"
## The share of a magazine's way out of the gun that is straight down the magazine well.
const _WELL_SHARE := 0.4
## The left hand's way from the hand guard to the magazine, as shares of it: its four fingers
## open by the first (the knuckles over its first half, then the rest, as the hand starts down),
## it is off the hand guard by the second, beside the magazine by the third and on it by the
## fourth; the fingers close on the magazine after that.
const _WAY_OPEN := 0.1
## How far the left hand drops while its knuckles open, before it moves off the hand guard.
const _LET_GO_DROP := 0.006
## What a finger's first bone (the knuckle's) has in its name: those open first.
const _KNUCKLE := "_01_"
const _WAY_DOWN := 0.3
## The shares of that way over which the thumb goes from its place on the hand guard to its place
## behind the magazine.
const _WAY_THUMB := Vector2(0.2, 0.5)
const _WAY_BESIDE := 0.7
const _WAY_ON := 0.88

@export_group("Nodes")
## The character holding it. Empty: the `Model` slot's parent.
@export var character: Character

@export_group("Stance")
## Where the butt sits when aiming, from the chest bone (`chest_bone`) in the model's space (+Z
## forward, +X the model's left). The chest's place comes from the clip, so a crouch or a lean
## carries the gun with it.
@export var aim_pocket := Vector3(-0.124, 0.12, 0.04)
## Where it sits at rest (the low ready).
@export var low_pocket := Vector3(-0.114, 0.06, 0.04)
## How far the muzzle points down at rest.
@export_range(0.0, 80.0, 0.5, "suffix:deg") var low_pitch := 35.0
## How far the muzzle points across the body at rest (toward the left).
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var low_yaw := 20.0
## How far the chest stands turned from the model's front, about its up axis, split over the
## spine bones; negative brings the left shoulder forward so the left hand reaches the fore-end.
## The clip's own turn of the chest is taken off, so the shoulders keep this in a walk or a run.
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var chest_turn := -30.0
## The most of its length the left arm stretches to. When the hand guard is farther than that
## from the left shoulder (a clip leans or drops the shoulder), the gun comes back along its
## barrel until the hand reaches, by `pull_limit` at most.
@export_range(0.5, 1.0, 0.005) var arm_stretch := 0.97
@export_range(0.0, 0.3, 0.005, "suffix:m") var pull_limit := 0.12
## The most the gun follows the view up or down.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var pitch_limit := 60.0
## Seconds from the low ready to the shoulder (and back).
@export_range(0.01, 2.0, 0.01, "suffix:s") var raise_time := 0.15
## Seconds the gun stays at the shoulder after a shot fired from the low ready.
@export_range(0.0, 3.0, 0.05, "suffix:s") var shot_hold_time := 0.6

@export_group("Switch")
## Where the butt is when the gun is all the way down in a switch (the place it is hidden and
## shown at), from the chest bone like `low_pocket`: both hands still reach it there.
@export var stow_pocket := Vector3(-0.114, 0.0, 0.04)
## How far the muzzle points down there, and across the body.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var stow_pitch := 55.0
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var stow_yaw := 30.0

@export_group("Recoil")
## How far a shot pushes the gun back along the barrel.
@export_range(0.0, 0.2, 0.001, "suffix:m") var kick_distance := 0.02
## How far a shot tips the muzzle up.
@export_range(0.0, 20.0, 0.1, "suffix:deg") var kick_degrees := 2.0
## Seconds for the gun to come back from a kick.
@export_range(0.01, 1.0, 0.01, "suffix:s") var kick_recover_time := 0.08

@export_group("Hands")
## The right hand's fingers on the grip, the index finger straight along the receiver.
@export var grip_pose: HandPose
## The index finger on the trigger, blended over `grip_pose` as the gun comes up to the shoulder.
@export var trigger_pose: HandPose
## The left hand's fingers cupped under the hand guard.
@export var support_pose: HandPose
## The left hand's four fingers opened, as it lets go of the gun and comes back to it (the thumb
## keeps the pose under it).
@export var open_pose: HandPose
## The left hand's fingers round the magazine.
@export var magazine_pose: HandPose

## Past this distance from the camera the fingers keep the clip's fist (the hands are a few
## pixels there; the rifle's far level shows from 10 m). 0: always posed. The hold reads no
## camera (a server has none): the animation throttle, which measures every character's distance,
## sets `fingers_far`.
@export_range(0.0, 100.0, 0.5, "suffix:m") var fingers_far_distance := 10.0

@export_group("Reload")
## Where the left hand takes the magazine to during a reload: the belt at the left hip, from the
## chest bone in the model's space like the pockets (a place the left arm reaches in every clip).
@export var reload_belt := Vector3(0.17, -0.3, 0.1)
## How far the magazine comes straight down out of the gun before it goes to the belt, along the
## gun's own up axis.
@export_range(0.0, 0.3, 0.005, "suffix:m") var magazine_well := 0.1
## How far the left hand comes off the hand guard before it goes to the magazine (and where it
## comes back to before it goes onto it), in the gun's space: down, and out to the left, the
## thumb's side, since the thumb stays as it lies up the hand guard's left side.
@export var reload_clearance := Vector3(0.0, -0.07, 0.035)
## Where the left hand is beside the magazine before it closes on it, from its place on it, in
## the gun's space: out to the left, so the open fingers pass in front of the magazine.
@export var magazine_approach := Vector3(0.0, 0.0, 0.07)
## The shares of the reload between which the left hand goes from the hand guard to the magazine.
@export var reload_leave := Vector2(0.0, 0.18)
## The shares between which it takes the magazine out and down to the belt.
@export var reload_out := Vector2(0.2, 0.42)
## The shares between which it brings the new magazine up and in.
@export var reload_in := Vector2(0.48, 0.62)
## The shares between which it goes back to the hand guard.
@export var reload_return := Vector2(0.66, 0.86)
## The magazine node under the gun that leaves with the left hand. Empty: none moves.
@export var magazine: NodePath
## The far level's magazine, moved and hidden with it. Empty: none.
@export var magazine_far: NodePath

@export_group("Bodies")
## Holds solved on other bodies than the one the scene's own hands' places and poses were solved
## on (`HoldFit`, written by `tools/hold/write_hold.gd ... rifle <body>`): a model whose file is a
## fit's `body` gets that fit's places (`seat` is the inverse of `RightHandTarget`) and poses; any
## other model the scene's own.
@export var fits: Array[HoldFit] = []

@export_group("Bones")
## The bone whose place the pocket follows.
@export var chest_bone: StringName = &"spine_03"
## The bones the chest turn spreads over.
@export var spine_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
## The right arm: upper arm, forearm, hand.
@export var right_arm: Array[StringName] = [&"upperarm_r", &"lowerarm_r", &"hand_r"]
## The left arm.
@export var left_arm: Array[StringName] = [&"upperarm_l", &"lowerarm_l", &"hand_l"]

## For a figure posed by hand (no `character`): how far the gun is up at the shoulder, the view's
## pitch in degrees, how far a reload is (below 0: none) and how far a switch has it down.
var posed_aim := 0.0
var posed_pitch := 0.0
var posed_reload := -1.0
var posed_lowered := 0.0
## True while the camera is past `fingers_far_distance` (set by `CharacterAnimationThrottle`).
var fingers_far := false

var _skeleton: Skeleton3D
var _modifiers: Array[SkeletonModifier3D] = []
var _stance: SkeletonModifier3D
var _arms: Array[HoldArm] = []
var _fingers: Array[HandPoseModifier] = []
var _raised := 0.0
var _shot_left := 0.0
var _kick := 0.0
var _reach := 1.0
var _down := 0.0
var _leaving := false
var _chest := Vector3.ZERO
var _left_rest := Transform3D.IDENTITY
var _magazine_rest := Transform3D.IDENTITY
var _weapon: Weapon
var _loadout: WeaponLoadout
# The scene's parts and the bones, found once (`_find_parts()`, `_find_bones()`) rather than
# looked up every frame (kit #1178).
var _pivot: Node3D
var _gun: Node3D
var _targets: Array[Node3D] = [null, null]
var _poles: Array[Node3D] = [null, null]
var _on_magazine: Node3D
var _mag: Node3D
var _mag_far: Node3D
var _chest_index := -1
var _spine_indices := PackedInt32Array()
var _left_indices := PackedInt32Array()
# Whether the left hand and the magazine are at rest already (nothing to write outside a reload).
var _hand_at_rest := false
# The weapon definition this hold is the view of, looked for again when the slots change.
var _mine: WeaponDef
var _mine_slots := -1
# The scene's own hold as a fit, kept before a body's fit is first put on.
var _own: HoldFit


func _ready() -> void:
	_find_parts()
	if _targets[1] != null:
		_left_rest = _targets[1].transform
	if _mag != null:
		_magazine_rest = _mag.transform
	if Engine.is_editor_hint():
		set_process(false)
		return
	if character == null and get_parent() != null:
		character = get_parent().get_parent() as Character
	var slot := get_parent() as CharacterModel
	if slot != null:
		slot.rig_changed.connect(_on_rig_changed.unbind(1))
	if character != null:
		_weapon = character.weapon
		_loadout = character.loadout
		if _weapon != null:
			_weapon.fired.connect(_on_fired.unbind(1))
		if _loadout != null:
			_loadout.slots_changed.connect(_forget_definition)
			_loadout.weapon_changed.connect(_on_weapon_changed)
			_loadout.switch_finished.connect(_on_switch_finished.unbind(1))
	_on_rig_changed.call_deferred()


func _exit_tree() -> void:
	_drop_modifiers()


func _process(delta: float) -> void:
	_step(delta)
	refresh()


## How far the gun is up at the shoulder: 0 at the low ready, 1 aimed.
func raised_amount() -> float:
	return _raised


## How far the arms are on the gun's places: 1 while the gun is in the hands, and the way there
## or away while a switch brings it out or has just put it away.
func reach_amount() -> float:
	return _reach


## The skeleton modifiers this hold made: the stance, each arm's reach, each hand's fingers.
func modifiers() -> Array[SkeletonModifier3D]:
	return _modifiers.duplicate()


## How far each hand's bone stopped from its place on the gun on the last update, in metres (an
## arm too short for the stance): x the right hand, y the left.
func shortfall() -> Vector2:
	if _arms.size() < 2:
		return Vector2.ZERO
	return Vector2(_arms[0].shortfall, _arms[1].shortfall)


## Puts the weights on the modifiers now (the frame's own `_process` does it too).
func refresh() -> void:
	_reach = _reach_now()
	_down = _down_now()
	var alive := character == null or not character.is_dead()
	var shown := alive and is_visible_in_tree()
	if is_instance_valid(_pivot):
		_pivot.visible = alive
	var fingers := 1.0 if shown and not _fingers_far() else 0.0
	for modifier in _modifiers:
		if not is_instance_valid(modifier):
			continue
		var share := fingers if modifier is HandPoseModifier else _reach
		if not alive:
			share = 0.0
		if not is_equal_approx(modifier.influence, share):
			modifier.influence = share
		if modifier.active != (share > 0.0):
			modifier.active = share > 0.0
	if _fingers.size() < 2:
		return
	# The finger is on the trigger while the gun is up, and off it through a reload.
	var reload := _reload_progress()
	_fingers[0].second_weight = _raised if reload < 0.0 else 0.0
	var to_magazine := _to_magazine(reload)
	# The thumb goes from the hand guard's side to its place behind the magazine while the hand
	# comes down off the hand guard (the open pose leaves it be): a thumb still standing up
	# on the way across went 17 mm through the magazine well. The four fingers stay open until
	# the hand is on the magazine, then close as one: closing tips first, as they open off the
	# hand guard, swung the little finger 8 mm through the magazine's front.
	_fingers[1].second_weight = smoothstep(_WAY_THUMB.x, _WAY_THUMB.y, to_magazine)
	_fingers[1].open_together = to_magazine > _WAY_DOWN
	_fingers[1].open_weight = (
		smoothstep(0.0, _WAY_OPEN, to_magazine) * (1.0 - smoothstep(_WAY_ON, 1.0, to_magazine))
	)


## Puts the pocket and the gun where they are this frame, and gives each arm its hand's place.
## The stance modifier calls it while the skeleton updates, when the chest bone has the clip's
## pose of this frame. Every pose comes from the local ones up the parents and every node's place
## from the transforms up to this node: nothing asks the engine to work out a global one.
func place(skeleton: Skeleton3D) -> void:
	if not is_instance_valid(_pivot) or not is_instance_valid(_gun):
		_find_parts()
		if _pivot == null:
			return
	var chest := Vector3.ZERO
	var to_here := global_transform.affine_inverse() * skeleton.global_transform
	if _chest_index >= 0:
		chest = to_here * HandPoseModifier.global_pose(skeleton, _chest_index).origin
	_chest = chest
	var pitch := posed_pitch
	if character != null:
		pitch = rad_to_deg(character.view_pitch)
	pitch = clampf(pitch, -pitch_limit, pitch_limit)
	var low := _turned(low_pitch, low_yaw)
	var aim := _turned(-pitch - kick_degrees * _kick, 0.0)
	var turn := low.slerp(aim, _raised)
	var pocket := low_pocket.lerp(aim_pocket, _raised)
	if _down > 0.0:
		var eased := smoothstep(0.0, 1.0, _down)
		turn = turn.slerp(_turned(stow_pitch, stow_yaw), eased)
		pocket = pocket.lerp(stow_pocket, eased)
	var basis_now := Basis(turn)
	var pivot_xf := Transform3D(basis_now, chest + pocket - basis_now.z * kick_distance * _kick)
	var gun_in_pivot := _between(_gun, _pivot) if _gun != null else Transform3D.IDENTITY
	pivot_xf.origin -= basis_now.z * _pull(skeleton, pivot_xf, gun_in_pivot, to_here)
	_pivot.transform = pivot_xf
	var gun_here := pivot_xf * gun_in_pivot
	_place_reload(gun_here)
	var to_skeleton := to_here.affine_inverse()
	for index in mini(_arms.size(), 2):
		var target := _targets[index]
		if target == null:
			continue
		var target_here := gun_here * target.transform
		if target.get_parent() != _gun:
			target_here = _in_here(target)
		_arms[index].offset = to_skeleton * target_here
		if _poles[index] != null:
			_arms[index].elbow = to_skeleton * _in_here(_poles[index]).origin


## The skeleton's indexes of `spine_bones`, for the stance modifier.
func spine_indices() -> PackedInt32Array:
	return _spine_indices


# How far the gun must come back along its barrel for the left arm to reach its place under the
# hand guard: the place is on the gun, the shoulder where the clip and the chest turn have it.
func _pull(
	skeleton: Skeleton3D, pivot_xf: Transform3D, gun_in_pivot: Transform3D, to_here: Transform3D
) -> float:
	if _targets[1] == null or _left_indices.size() < 3 or _left_indices.has(-1):
		return 0.0
	var length := skeleton.get_bone_pose_position(_left_indices[1]).length()
	length += skeleton.get_bone_pose_position(_left_indices[2]).length()
	length *= to_here.basis.get_scale().x * arm_stretch
	var shoulder := to_here * HandPoseModifier.global_pose(skeleton, _left_indices[0]).origin
	var held_at := pivot_xf * (gun_in_pivot * _left_rest.origin)
	var off := held_at - shoulder
	if off.length() <= length:
		return 0.0
	# The place moves back along the barrel: the nearest point of that line the arm reaches.
	var back := -pivot_xf.basis.z
	var along := off.dot(back)
	var beside := off.length_squared() - along * along
	var reach := sqrt(maxf(length * length - beside, 0.0))
	return clampf(-along - reach, 0.0, pull_limit)


## The weight of the chest turn: with the arms.
func weight() -> float:
	return _reach


# How far the arms are on the gun's places now. In the hands: all the way. While the weapon
# before it goes down to make room for it, and while the one after it comes up: as far as the
# loadout's switch has the weapon down, so the arms are on the gun in the tick it appears and
# leave it only once it is hidden.
func _reach_now() -> float:
	if character == null or _loadout == null:
		return 1.0
	var mine := _definition()
	if _loadout.held_definition() == mine:
		return 1.0
	if not _loadout.is_switching():
		return 0.0
	var target := _loadout.target_slot()
	var coming := target >= 0 and target < _loadout.slots.size() and _loadout.slots[target] == mine
	return _loadout.lowered_amount() if coming or _leaving else 0.0


# How far the gun is down at its stow place: by the switch while it is in the hands, all the way
# while it is not.
func _down_now() -> float:
	if character == null or _loadout == null:
		return posed_lowered
	if _loadout.held_definition() == _definition():
		return _loadout.lowered_amount()
	return 1.0


# The weapon definition this hold is the view of, or null: looked for again after the slots
# changed (or their count, for slots set by hand) and while it is not found.
func _definition() -> WeaponDef:
	if _loadout == null or _loadout.model == null:
		return null
	if _mine != null and _mine_slots == _loadout.slots.size():
		return _mine
	_mine = null
	_mine_slots = _loadout.slots.size()
	for definition in _loadout.slots:
		if definition != null and _loadout.model.get_node_or_null(definition.view) == self:
			_mine = definition
			break
	return _mine


func _forget_definition() -> void:
	_mine = null


# Whether the fingers rest: `fingers_far`, unless `fingers_far_distance` is 0.
func _fingers_far() -> bool:
	return fingers_far and fingers_far_distance > 0.0


func _on_weapon_changed(definition: WeaponDef) -> void:
	# Hidden for the next weapon: the arms leave the gun's places as that one comes up.
	_leaving = _reach >= 1.0 and definition != _definition() and _loadout.is_switching()


func _on_switch_finished() -> void:
	_leaving = false


func _step(delta: float) -> void:
	if character != null:
		var wants := character.aim_amount
		_shot_left = maxf(_shot_left - delta, 0.0)
		if _shot_left > 0.0:
			wants = 1.0
		_raised = move_toward(_raised, wants, delta / maxf(raise_time, 0.001))
	else:
		_raised = posed_aim
	_kick = move_toward(_kick, 0.0, delta / maxf(kick_recover_time, 0.001))


# A turn of the gun from straight ahead: the muzzle `pitch` degrees down and `yaw` across.
func _turned(pitch: float, yaw: float) -> Quaternion:
	var turned := Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.UP, deg_to_rad(yaw))
	return turned.get_rotation_quaternion()


# A node's transform in this node's space, from the transforms up its parents (no global
# transform is asked for while the skeleton updates).
func _in_here(node: Node3D) -> Transform3D:
	return _between(node, self)


# A node's transform in the space of `top`, one of its parents, from the transforms between.
func _between(node: Node3D, top: Node) -> Transform3D:
	var xf := node.transform
	var above := node.get_parent() as Node3D
	while above != null and above != top:
		xf = above.transform * xf
		above = above.get_parent() as Node3D
	return xf


# How far the reload is (0 to 1), or below 0 with none.
func _reload_progress() -> float:
	if character == null:
		return posed_reload
	if _weapon != null and _weapon.is_reloading() and visible:
		return _weapon.reload_progress()
	return -1.0


# How far the left hand is from the hand guard (0) to the magazine (1) at `progress` of a reload.
func _to_magazine(progress: float) -> float:
	if progress < 0.0:
		return 0.0
	var there := smoothstep(reload_leave.x, reload_leave.y, progress)
	return there * (1.0 - smoothstep(reload_return.x, reload_return.y, progress))


# The left hand leaves the gun for the magazine and comes back with a full one, by the weapon's
# reload progress: down off the hand guard with its fingers open, across to beside the magazine,
# onto it and closed on it, straight down out of the well and to the belt (where the magazine is
# changed, out of sight), back up under the well, straight in, and back the way it came.
func _place_reload(gun_here: Transform3D) -> void:
	var left := _targets[1]
	if left == null:
		return
	var progress := _reload_progress()
	var mag := _mag
	var mag_far := _mag_far
	var on_magazine := _on_magazine
	if progress < 0.0 or on_magazine == null:
		# At rest nothing but this moves the hand's place and the magazine: put them back once.
		if not _hand_at_rest:
			left.transform = _left_rest
			_set_magazine(mag, mag_far, _magazine_rest, true)
			_hand_at_rest = true
		return
	_hand_at_rest = false
	var to_magazine := _to_magazine(progress)
	var away := smoothstep(reload_out.x, reload_out.y, progress)
	away *= 1.0 - smoothstep(reload_in.x, reload_in.y, progress)
	# Down off the hand guard, across to beside the magazine, then onto it.
	var below := _left_rest.translated(reload_clearance)
	var beside := on_magazine.transform.translated(magazine_approach)
	# A little straight down while the knuckles let go (the hooked fingers come off the far side
	# clear), then down and out to the thumb's side together: a move sideways under closed fingers
	# pushes the far side's into the hand guard, and a drop with none drags the thumb through it.
	var hand := _left_rest.translated(
		Vector3.DOWN * _LET_GO_DROP * smoothstep(0.0, _WAY_OPEN * 0.5, to_magazine)
	)
	hand = hand.interpolate_with(below, smoothstep(_WAY_OPEN * 0.5, _WAY_DOWN, to_magazine))
	hand = hand.interpolate_with(beside, smoothstep(_WAY_DOWN, _WAY_BESIDE, to_magazine))
	hand = hand.interpolate_with(
		on_magazine.transform, smoothstep(_WAY_BESIDE, _WAY_ON, to_magazine)
	)
	# Out of the well along the gun's own up axis, then to the belt, which is a place on the
	# body (the hand's place is on the gun).
	var out := Vector3.DOWN * magazine_well * minf(away / _WELL_SHARE, 1.0)
	var to_belt := smoothstep(0.0, 1.0, (away - _WELL_SHARE) / (1.0 - _WELL_SHARE))
	var belt := gun_here.affine_inverse() * (_chest + reload_belt)
	out += (belt - (hand.origin + out)) * to_belt
	hand.origin += out
	left.transform = hand
	var mag_xf := _magazine_rest
	if mag != null:
		mag_xf.origin += (mag.get_parent() as Node3D).transform.basis.inverse() * out
	_set_magazine(mag, mag_far, mag_xf, away < 0.9)


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
	_fit_body(slot)
	_find_bones()
	_stance = STANCE_SCRIPT.new() as SkeletonModifier3D
	_stance.set(&"hold", self)
	_add_modifier(_stance, "Stance")
	_add_arm(right_arm, "RightArm")
	_add_arm(left_arm, "LeftArm")
	_add_fingers(grip_pose, trigger_pose, null, "RightFingers")
	_add_fingers(support_pose, magazine_pose, open_pose, "LeftFingers")
	refresh()


## The fit in use: the one solved on the body the model slot holds, or the scene's own.
func fit() -> HoldFit:
	var found := HoldFit.chosen(fits, get_parent() as CharacterModel)
	return found if found != null else _own


# Puts the fit of the model's body on the hands' places and on the poses, keeping the scene's own
# first.
func _fit_body(slot: CharacterModel) -> void:
	var right := _targets[0]
	var left := _targets[1]
	var on_magazine := _on_magazine
	if _own == null:
		_own = HoldFit.new()
		_own.seat = right.transform.affine_inverse() if right != null else Transform3D.IDENTITY
		_own.support_hand = _left_rest
		_own.magazine_hand = on_magazine.transform if on_magazine != null else Transform3D.IDENTITY
		_own.grip_pose = grip_pose
		_own.trigger_pose = trigger_pose
		_own.support_pose = support_pose
		_own.magazine_pose = magazine_pose
		_own.open_pose = open_pose
	var chosen := HoldFit.chosen(fits, slot)
	if chosen == null:
		chosen = _own
	if right != null:
		right.transform = chosen.seat.affine_inverse()
	_left_rest = chosen.support_hand
	if left != null:
		left.transform = _left_rest
	if on_magazine != null:
		on_magazine.transform = chosen.magazine_hand
	_hand_at_rest = false
	grip_pose = chosen.grip_pose
	trigger_pose = chosen.trigger_pose
	support_pose = chosen.support_pose
	magazine_pose = chosen.magazine_pose
	open_pose = chosen.open_pose


func _add_arm(bones: Array[StringName], tag: String) -> void:
	var arm := HoldArm.new()
	arm.arm = bones
	arm.bone = &""
	_arms.append(arm)
	_add_modifier(arm, tag)


func _add_fingers(pose: HandPose, second: HandPose, open: HandPose, tag: String) -> void:
	var fingers := HandPoseModifier.new()
	fingers.pose = pose
	fingers.second = second
	fingers.open = open
	if open != null:
		for bone_name in open.rotations:
			if String(bone_name).contains(_KNUCKLE):
				fingers.open_first.append(bone_name)
		fingers.open_first = fingers.open_first
	_fingers.append(fingers)
	_add_modifier(fingers, tag)


func _add_modifier(modifier: SkeletonModifier3D, tag: String) -> void:
	modifier.name = _MODIFIER_PREFIX + tag
	_skeleton.add_child(modifier)
	_modifiers.append(modifier)


func _drop_modifiers() -> void:
	for modifier in _modifiers:
		if is_instance_valid(modifier):
			modifier.queue_free()
			if modifier.get_parent() != null:
				modifier.get_parent().remove_child(modifier)
	_modifiers.clear()
	_arms.clear()
	_fingers.clear()
	_stance = null


func _find_parts() -> void:
	_pivot = get_node_or_null(^"Pivot") as Node3D
	_targets[0] = find_child("RightHandTarget", true, false) as Node3D
	_targets[1] = find_child("LeftHandTarget", true, false) as Node3D
	_poles[0] = get_node_or_null(^"RightPole") as Node3D
	_poles[1] = get_node_or_null(^"LeftPole") as Node3D
	_on_magazine = find_child("MagazineHand", true, false) as Node3D
	_gun = _targets[1].get_parent() as Node3D if _targets[1] != null else null
	_mag = get_node_or_null(magazine) as Node3D
	_mag_far = get_node_or_null(magazine_far) as Node3D
	_hand_at_rest = false


func _find_bones() -> void:
	_chest_index = _skeleton.find_bone(chest_bone)
	_spine_indices.clear()
	for bone_name in spine_bones:
		_spine_indices.append(_skeleton.find_bone(bone_name))
	_left_indices.clear()
	for bone_name in left_arm:
		_left_indices.append(_skeleton.find_bone(bone_name))
