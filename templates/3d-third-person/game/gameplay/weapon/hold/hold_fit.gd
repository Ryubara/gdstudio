class_name HoldFit
extends Resource
## A weapon's hold solved on one body (kit #1187): where the weapon sits in that body's right hand,
## where its left hand holds and pushes the magazine, the line its opened hand leaves along, the
## new magazine's way in, and the hand poses. Hands of other sizes need other finger poses and
## another seat, so each body the template ships has its own, written by
## `tools/hold/write_hold.gd` from the solver's output (no number here is typed).
## `WeaponHold.fits` (the pistol) and `TwoHandHold.fits` (the rifle) hold them; the one whose
## `body` is the model's file is used (`chosen`), and a model with none keeps the hold scene's own.

## The file name of the body's model it was solved on (`form_male.glb`).
@export var body := ""
## The weapon's place on the right hand's bone: the pistol's `BoneAttachment3D`'s first child; for
## a gun the arms reach (the rifle) the inverse of its `RightHandTarget`.
@export var seat := Transform3D.IDENTITY
## The `SupportHand` marker's place in the weapon: where the left hand's bone sits on it.
@export var support_hand := Transform3D.IDENTITY
## The `MagazineHand` marker's place in the weapon: where the left hand's bone pushes the magazine.
@export var magazine_hand := Transform3D.IDENTITY
## The `ChargeHand` marker's place on the rifle: where the left hand's bone sits on the charging
## handle (kit #1266). Identity: the weapon has none.
@export var charge_hand := Transform3D.IDENTITY
## `WeaponHold.support_way` for this body.
@export var support_way := Vector3(0.0, 0.0, 0.06)
@export var grip_pose: HandPose
@export var trigger_pose: HandPose
@export var trigger_way_pose: HandPose
@export var thumb_pose: HandPose
@export var thumb_way_pose: HandPose
@export var support_pose: HandPose
@export var magazine_pose: HandPose
@export var open_pose: HandPose
## The left hand's fingers hooked on the charging handle (`TwoHandHold.charge_pose`, kit #1266).
@export var charge_pose: HandPose
## `WeaponHold.one_hand_pose` and `one_hand_way_pose` for this body, or none (the pistol's: kit
## #1085, fitted to the default body's placement: kit #1274).
@export var one_hand_pose: HandPose
@export var one_hand_way_pose: HandPose
## The left hand's fingers closed on the new magazine and opened to take it (kit #1052:
## `WeaponHold.carry_pose`, `carry_open_pose`), for this body.
@export var carry_pose: HandPose
@export var carry_open_pose: HandPose
## `WeaponHold.magazine_approach`, `carry_release` and `carry_arrive` for this body.
@export var magazine_approach := Vector3(0.0, -0.1, 0.0)
@export var carry_release := Vector2(0.4, 0.6)
@export var carry_arrive := Vector2(0.6, 1.0)
## The poses the trigger finger passes through between `grip_pose` and `trigger_pose` on this
## body (`TwoHandHold.trigger_way`, written by `tools/hold/solve_trigger_way.gd`). None: the
## straight way.
@export var trigger_way: HandPoseWay


## The fit of `fits` solved on the body `model` wears (its file is the fit's `body`), or null.
static func chosen(fits: Array[HoldFit], model: CharacterModel) -> HoldFit:
	var rig := model.rig() if model != null else null
	var file := rig.scene_file_path.get_file() if rig != null else ""
	for each in fits:
		if each != null and each.body == file:
			return each
	return null


## A two-hand hold's own fit (`TwoHandHold`), kept before a body's fit is first put on: its
## scene's places (the right hand's marker `right`, the left hand's place `support` and the
## `magazine` and charging `handle` markers, null where the scene has none) and `hold`'s poses.
static func of_two_hand(
	hold: TwoHandHold, right: Node3D, support: Transform3D, magazine: Node3D, handle: Node3D
) -> HoldFit:
	var own := HoldFit.new()
	own.seat = right.transform.affine_inverse() if right != null else Transform3D.IDENTITY
	own.support_hand = support
	own.magazine_hand = magazine.transform if magazine != null else Transform3D.IDENTITY
	own.charge_hand = handle.transform if handle != null else Transform3D.IDENTITY
	own.charge_pose = hold.charge_pose
	own.grip_pose = hold.grip_pose
	own.trigger_pose = hold.trigger_pose
	own.support_pose = hold.support_pose
	own.magazine_pose = hold.magazine_pose
	own.open_pose = hold.open_pose
	own.trigger_way = hold.trigger_way
	return own


## Puts this fit on a two-hand hold: its places on the scene's markers (as `of_two_hand` reads
## them, `left` the left hand's) and its poses on `hold`. The charging handle's place and pose
## only when the fit has a charge pose (a fit solved before kit #1266 keeps the scene's).
func put_on_two_hand(
	hold: TwoHandHold, right: Node3D, left: Node3D, magazine: Node3D, handle: Node3D
) -> void:
	if right != null:
		right.transform = seat.affine_inverse()
	if left != null:
		left.transform = support_hand
	if magazine != null:
		magazine.transform = magazine_hand
	if charge_pose != null:
		if handle != null:
			handle.transform = charge_hand
		hold.charge_pose = charge_pose
	hold.grip_pose = grip_pose
	hold.trigger_pose = trigger_pose
	hold.support_pose = support_pose
	hold.magazine_pose = magazine_pose
	hold.open_pose = open_pose
	hold.trigger_way = trigger_way
