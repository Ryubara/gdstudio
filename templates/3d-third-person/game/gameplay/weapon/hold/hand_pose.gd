class_name HandPose
extends Resource
## How the bones of a hand are turned to hold one weapon (kit #1001): each finger bone's rotation
## in its parent's space, as `Skeleton3D.set_bone_pose_rotation()` takes it. The hand bone carries
## the weapon, so a pose given in the fingers' own spaces holds in every clip. `HandPoseModifier`
## puts it on the skeleton (and lays it out again when it says `changed`, as a new dictionary
## does); the files are written by `tools/hold/solve_pistol_hold.py` from the
## weapon's sockets and measured by `tests/gameplay/test_pistol_hold.gd`, so no number is typed.

## The bone's name (`index_02_r`) and its rotation in its parent's space.
@export var rotations: Dictionary[StringName, Quaternion] = {}:
	set(value):
		rotations = value
		emit_changed()
## Bones that keep the clip's rotation and are turned on top of it, about their own axes: the
## hand bone's name and the turn of the wrist that lays the palm on the grip while the barrel
## keeps its line in the forearm.
@export var turns: Dictionary[StringName, Quaternion] = {}:
	set(value):
		turns = value
		emit_changed()
