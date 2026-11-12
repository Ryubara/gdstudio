class_name HoldFit
extends Resource
## A weapon's hold solved on one body (kit #1187): where the weapon sits in that body's right hand,
## where its left hand holds and pushes the magazine, the line its opened hand leaves along, and
## the five hand poses. Hands of other sizes need other finger poses and another seat, so each
## body the template ships has its own, written by `tools/hold/write_hold.gd` from the solver's
## output (no number here is typed). `WeaponHold.fits` (the pistol) and `TwoHandHold.fits` (the
## rifle) hold them; the one whose `body` is the model's file is used (`chosen`), and a model with
## none keeps the hold scene's own.

## The file name of the body's model it was solved on (`form_male.glb`).
@export var body := ""
## The weapon's place on the right hand's bone: the pistol's `BoneAttachment3D`'s first child; for
## a gun the arms reach (the rifle) the inverse of its `RightHandTarget`.
@export var seat := Transform3D.IDENTITY
## The `SupportHand` marker's place in the weapon: where the left hand's bone sits on it.
@export var support_hand := Transform3D.IDENTITY
## The `MagazineHand` marker's place in the weapon: where the left hand's bone pushes the magazine.
@export var magazine_hand := Transform3D.IDENTITY
## `WeaponHold.support_way` for this body.
@export var support_way := Vector3(0.0, 0.0, 0.06)
@export var grip_pose: HandPose
@export var trigger_pose: HandPose
@export var support_pose: HandPose
@export var magazine_pose: HandPose
@export var open_pose: HandPose
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
