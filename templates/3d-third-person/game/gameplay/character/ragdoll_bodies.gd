class_name RagdollBodies
extends RefCounted
## The table `CharacterRagdoll` makes its physical bones from (`CharacterRagdoll.BODIES` is this
## one), for the Quaternius universal rig (every body on it). Data only, in a file of its own so
## the ragdoll's script stays one that reads in one go.
##
## The capsules were sized on the Quaternius female and measured again on the template's bodies,
## the `form` prototype mannequins (kit #1187, `tools/mannequin/measure_segments.gd`): every radius
## is within the skin of both, as before, but for the calves, thinned from 0.06 to 0.055 so the
## female's calf (0.054 m) does not lie on a capsule fatter than itself. Thinner arms and legs
## (each capsule the share of the skin the Quaternius table used) let the jogging male's shoulder
## twist 28 to 35 degrees past a person's range as it rolls over the arm
## (`test_ragdoll_cones.gd`), so the rest stay as they were.
##
## Each physical bone: `bone` is the skeleton bone it moves, `from` and `to` the bones (or, for
## `to`, a length along the bone, in metres) between which its capsule lies, `radius` the
## capsule's radius in metres and `share` its share of the body's mass in per cent (the
## Dempster/Winter segment masses). A body's frame has X along the bone and Z across it, toward
## `side` (in the skeleton's space, which holds a T-pose facing +Z) or else up or to the right.
##
## `joint` is how it hangs on the body above it: `&""` (the root, no joint); `&"cone"`, a ball
## joint that swings up to `swing` degrees from `centre` (a turn from the rest pose, Euler
## degrees, the pose a person stands in) and twists `twist` degrees either way around the bone;
## or `&"hinge"`, a knee or an elbow, that bends about `axis` (in the body's frame) through
## `range` (degrees, the lowest and the highest, from the straight limb) and does nothing else.
##
## The limits are a person's (the sources are in docs/engines/godot/ragdoll.md#limits), the same
## on the left and the right, but for the shoulders' twist: 45 where a person turns about 60,
## because a shoulder the body lands on is pushed past its twist and 45 keeps it near a person's.
## A clip can hold a joint outside them; the pose is pushed inside when the body goes limp
## (`CharacterRagdoll._clamped_world`), so no joint starts out of range and is thrown.
## `tools/ragdoll/measure_joints.gd` prints how far the clips go past them.
const BODIES := [
	{
		bone = &"pelvis",
		from = &"pelvis",
		to = &"spine_01",
		radius = 0.12,
		share = 14.2,
		joint = &""
	},
	{
		bone = &"spine_01",
		from = &"spine_01",
		to = &"spine_03",
		radius = 0.12,
		share = 13.9,
		joint = &"cone",
		centre = Vector3.ZERO,
		swing = 20.0,
		twist = 12.0
	},
	{
		bone = &"spine_03",
		from = &"spine_03",
		to = &"neck_01",
		radius = 0.13,
		share = 20.1,
		joint = &"cone",
		centre = Vector3(0.7, -0.1, 34.6),
		swing = 30.0,
		twist = 20.0
	},
	{
		bone = &"Head",
		from = &"neck_01",
		to = 0.26,
		radius = 0.1,
		share = 8.1,
		joint = &"cone",
		centre = Vector3(-0.9, -1.4, -14.7),
		swing = 45.0,
		twist = 60.0
	},
	{
		bone = &"upperarm_l",
		from = &"upperarm_l",
		to = &"lowerarm_l",
		radius = 0.05,
		share = 2.8,
		joint = &"cone",
		centre = Vector3(25.8, 33.6, -31.9),
		swing = 100.0,
		twist = 45.0
	},
	{
		bone = &"lowerarm_l",
		from = &"lowerarm_l",
		to = &"hand_l",
		radius = 0.045,
		share = 1.6,
		side = Vector3.DOWN,
		joint = &"hinge",
		axis = Vector3(0.0, 0.181, 0.983),
		range = Vector2(-5.0, 150.0)
	},
	{
		bone = &"hand_l",
		from = &"hand_l",
		to = 0.17,
		radius = 0.04,
		share = 0.6,
		joint = &"cone",
		centre = Vector3(-10.4, -4.4, -6.4),
		swing = 60.0,
		twist = 60.0
	},
	{
		bone = &"upperarm_r",
		from = &"upperarm_r",
		to = &"lowerarm_r",
		radius = 0.05,
		share = 2.8,
		joint = &"cone",
		centre = Vector3(-27.8, 39.8, 21.5),
		swing = 100.0,
		twist = 45.0
	},
	{
		bone = &"lowerarm_r",
		from = &"lowerarm_r",
		to = &"hand_r",
		radius = 0.045,
		share = 1.6,
		side = Vector3.UP,
		joint = &"hinge",
		axis = Vector3(0.0, -0.109, 0.994),
		range = Vector2(-5.0, 150.0)
	},
	{
		bone = &"hand_r",
		from = &"hand_r",
		to = 0.17,
		radius = 0.04,
		share = 0.6,
		joint = &"cone",
		centre = Vector3(17.6, -0.8, 10.6),
		swing = 60.0,
		twist = 60.0
	},
	{
		bone = &"thigh_l",
		from = &"thigh_l",
		to = &"calf_l",
		radius = 0.075,
		share = 10.0,
		joint = &"cone",
		centre = Vector3(-8.9, -20.4, -39.2),
		swing = 70.0,
		twist = 35.0
	},
	{
		bone = &"calf_l",
		from = &"calf_l",
		to = &"foot_l",
		radius = 0.055,
		share = 4.65,
		side = Vector3.RIGHT,
		joint = &"hinge",
		axis = Vector3(0.0, 0.12, 0.993),
		range = Vector2(-5.0, 140.0)
	},
	{
		bone = &"foot_l",
		from = &"foot_l",
		to = &"ball_leaf_l",
		radius = 0.045,
		share = 1.45,
		joint = &"cone",
		centre = Vector3(-0.8, -5.8, -9.7),
		swing = 35.0,
		twist = 15.0
	},
	{
		bone = &"thigh_r",
		from = &"thigh_r",
		to = &"calf_r",
		radius = 0.075,
		share = 10.0,
		joint = &"cone",
		centre = Vector3(6.7, 10.0, -22.5),
		swing = 70.0,
		twist = 35.0
	},
	{
		bone = &"calf_r",
		from = &"calf_r",
		to = &"foot_r",
		radius = 0.055,
		share = 4.65,
		side = Vector3.RIGHT,
		joint = &"hinge",
		axis = Vector3(0.0, -0.114, 0.994),
		range = Vector2(-5.0, 140.0)
	},
	{
		bone = &"foot_r",
		from = &"foot_r",
		to = &"ball_leaf_r",
		radius = 0.045,
		share = 1.45,
		joint = &"cone",
		centre = Vector3(1.2, -8.0, 14.8),
		swing = 35.0,
		twist = 15.0
	},
]
