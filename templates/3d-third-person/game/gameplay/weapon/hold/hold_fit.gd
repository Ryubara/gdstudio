class_name HoldFit
extends Resource
## A weapon's hold solved on one body (kit #1187): where the weapon sits in that body's right hand,
## where its left hand holds and pushes the magazine, the line its opened hand leaves along, and
## the five hand poses. Hands of other sizes need other finger poses and another seat, so each
## body the template ships has its own, written by `tools/hold/write_hold.gd` from the solver's
## output (no number here is typed). `WeaponHold.fits` holds them; the one whose `body` is the
## model's file is used, and a model with none keeps the hold scene's own.

## The file name of the body's model it was solved on (`form_male.glb`).
@export var body := ""
## The weapon's place on the right hand's bone (the `BoneAttachment3D`'s first child).
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
