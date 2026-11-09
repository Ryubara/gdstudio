class_name RagdollLayout
extends RefCounted
## Which bones of the Quaternius universal rig get a physical bone, how big its shape is and how
## its joint bends. `PlayerRagdoll` reads it and builds the bones from the skeleton it finds, so
## both mannequins (and any model on the same rig) get the same ragdoll. No fingers or toes: the
## hand and the foot are one body each.
##
## Lengths come from the skeleton (a limb is as long as the bone it runs to); what is here are the
## radii, the boxes of the torso, the share of the mass and the joint. Directions are in the
## model's rest pose (a T-pose facing +Z, the character's left at +X), where the model is made.
##
## Each entry:
## - `bone`: the bone the body is attached to; its parent is the nearest earlier entry on the way
##   up the skeleton (the joint connects the two).
## - `shape`: `capsule` runs from the bone to `end` (a bone name, or a `reach` in metres up the
##   skeleton's Y when there is none); `box` is `size` metres wide, tall and deep, `offset` metres
##   from the bone, in the rest pose's axes; `sphere` is `radius` metres, `offset` from the bone.
## - `mass`: its share of the body's mass (the shares are normalised).
## - `joint`: `none` (the root), `cone` (the limb may swing `swing` degrees and twist `twist`
##   degrees from where it is when the body dies; `axis` is the limb's direction in the rest pose)
##   or `hinge` (a knee or an elbow: it bends about `axis`, fixed in the bone above, from `lower`
##   to `upper` degrees measured from the straight limb, one way only).

const BONES: Array[Dictionary] = [
	{
		&"bone": &"pelvis",
		&"shape": &"box",
		&"size": Vector3(0.30, 0.17, 0.20),
		&"offset": Vector3(0.0, 0.03, 0.05),
		&"mass": 0.14,
		&"joint": &"none",
	},
	{
		&"bone": &"spine_01",
		&"shape": &"box",
		&"size": Vector3(0.30, 0.27, 0.20),
		&"offset": Vector3(0.0, 0.135, 0.05),
		&"mass": 0.14,
		&"joint": &"cone",
		&"axis": Vector3.UP,
		&"swing": 22.0,
		&"twist": 22.0,
	},
	{
		&"bone": &"spine_03",
		&"shape": &"box",
		&"size": Vector3(0.34, 0.20, 0.22),
		&"offset": Vector3(0.0, 0.09, 0.05),
		&"mass": 0.22,
		&"joint": &"cone",
		&"axis": Vector3.UP,
		&"swing": 22.0,
		&"twist": 22.0,
	},
	{
		&"bone": &"neck_01",
		&"shape": &"capsule",
		&"end": &"Head",
		&"radius": 0.045,
		&"mass": 0.02,
		&"joint": &"cone",
		&"axis": Vector3.UP,
		&"swing": 35.0,
		&"twist": 35.0,
	},
	{
		&"bone": &"Head",
		&"shape": &"sphere",
		&"radius": 0.1,
		&"offset": Vector3(0.0, 0.1, 0.03),
		&"mass": 0.07,
		&"joint": &"cone",
		&"axis": Vector3.UP,
		&"swing": 40.0,
		&"twist": 45.0,
	},
	{
		&"bone": &"upperarm_l",
		&"shape": &"capsule",
		&"end": &"lowerarm_l",
		&"radius": 0.05,
		&"mass": 0.03,
		&"joint": &"cone",
		&"axis": Vector3.RIGHT,
		&"swing": 80.0,
		&"twist": 50.0,
	},
	{
		&"bone": &"lowerarm_l",
		&"shape": &"capsule",
		&"end": &"hand_l",
		&"radius": 0.04,
		&"mass": 0.02,
		&"joint": &"hinge",
		&"axis": Vector3.DOWN,
		&"lower": 0.0,
		&"upper": 150.0,
	},
	{
		&"bone": &"hand_l",
		&"shape": &"capsule",
		&"end": &"middle_02_l",
		&"radius": 0.035,
		&"mass": 0.008,
		&"joint": &"cone",
		&"axis": Vector3.RIGHT,
		&"swing": 45.0,
		&"twist": 20.0,
	},
	{
		&"bone": &"upperarm_r",
		&"shape": &"capsule",
		&"end": &"lowerarm_r",
		&"radius": 0.05,
		&"mass": 0.03,
		&"joint": &"cone",
		&"axis": Vector3.LEFT,
		&"swing": 80.0,
		&"twist": 50.0,
	},
	{
		&"bone": &"lowerarm_r",
		&"shape": &"capsule",
		&"end": &"hand_r",
		&"radius": 0.04,
		&"mass": 0.02,
		&"joint": &"hinge",
		&"axis": Vector3.UP,
		&"lower": 0.0,
		&"upper": 150.0,
	},
	{
		&"bone": &"hand_r",
		&"shape": &"capsule",
		&"end": &"middle_02_r",
		&"radius": 0.035,
		&"mass": 0.008,
		&"joint": &"cone",
		&"axis": Vector3.LEFT,
		&"swing": 45.0,
		&"twist": 20.0,
	},
	{
		&"bone": &"thigh_l",
		&"shape": &"capsule",
		&"end": &"calf_l",
		&"radius": 0.085,
		&"mass": 0.1,
		&"joint": &"cone",
		&"axis": Vector3.DOWN,
		&"swing": 80.0,
		&"twist": 35.0,
	},
	{
		&"bone": &"calf_l",
		&"shape": &"capsule",
		&"end": &"foot_l",
		&"radius": 0.065,
		&"mass": 0.05,
		&"joint": &"hinge",
		&"axis": Vector3.RIGHT,
		&"lower": -5.0,
		&"upper": 150.0,
	},
	{
		&"bone": &"foot_l",
		&"shape": &"capsule",
		&"end": &"ball_leaf_l",
		&"radius": 0.045,
		&"mass": 0.015,
		&"joint": &"cone",
		&"axis": Vector3.DOWN,
		&"swing": 40.0,
		&"twist": 15.0,
	},
	{
		&"bone": &"thigh_r",
		&"shape": &"capsule",
		&"end": &"calf_r",
		&"radius": 0.085,
		&"mass": 0.1,
		&"joint": &"cone",
		&"axis": Vector3.DOWN,
		&"swing": 80.0,
		&"twist": 35.0,
	},
	{
		&"bone": &"calf_r",
		&"shape": &"capsule",
		&"end": &"foot_r",
		&"radius": 0.065,
		&"mass": 0.05,
		&"joint": &"hinge",
		&"axis": Vector3.RIGHT,
		&"lower": -5.0,
		&"upper": 150.0,
	},
	{
		&"bone": &"foot_r",
		&"shape": &"capsule",
		&"end": &"ball_leaf_r",
		&"radius": 0.045,
		&"mass": 0.015,
		&"joint": &"cone",
		&"axis": Vector3.DOWN,
		&"swing": 40.0,
		&"twist": 15.0,
	},
]

## The bone whose body is the middle of the ragdoll: the camera follows it and the character
## stands up where it lies.
const PELVIS := &"pelvis"
## The chest, which says which way the body faces.
const CHEST := &"spine_03"
## The head, which says which way a body lying on its front or back is turned.
const HEAD := &"Head"


## The sum of every entry's `mass`, to divide by.
static func total_mass() -> float:
	var total := 0.0
	for entry in BONES:
		total += entry[&"mass"]
	return total
