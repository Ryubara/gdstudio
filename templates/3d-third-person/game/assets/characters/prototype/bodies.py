"""The bodies of the prototype mannequins (kit #1149): where the joints are and how thick each part is.

A body is plain numbers: a game makes its own (a hero, a child, a brute) by copying one and changing it, then runs
`build_mannequins.py`. Every body shares the skeleton of `skeleton.py`, so every clip plays on every body. Axes are
Godot's: +Y up, +Z front, +X the character's left; metres. Only the left side is given.

What may change freely: every girth, the trunk's heights, the shoulders' and hips' width, the arms' lengths, the
hand's and the head's size. What should keep its ratio: the leg (thigh, calf and ankle height). A clip's knee angles
plant the foot only on a leg with the reference's proportions (0.400 : 0.429 : 0.104), so the bodies here scale the
whole leg by one number (`leg`); a body that breaks the ratio needs foot IK (the `ik_foot` targets).
"""

from skeleton import REFERENCE_HIPS


def _leg(scale, hip_x):
    """The reference leg, scaled as a whole: the pelvis and the five leg joints."""
    s = scale
    return {
        "root": (0, 0, 0),
        "pelvis": (0, REFERENCE_HIPS * s, -0.0503 * s),
        "thigh_l": (hip_x, 0.9320 * s, 0.0007 * s),
        "calf_l": (hip_x, 0.5317 * s, -0.0010 * s),
        "foot_l": (hip_x, 0.1040 * s, -0.0362 * s),
        "ball_l": (hip_x, 0.0150 * s, 0.1126 * s),
        "ball_leaf_l": (hip_x, 0.0150 * s, 0.1917 * s),
    }


def _body(name, leg, hip_x, trunk, shoulder, upper_arm, forearm, hand_scale, shape):
    """`trunk` is the heights of spine_01, spine_02, spine_03, neck_01, Head and the arm; `shoulder` is (x, z)."""
    joints = _leg(leg, hip_x)
    s1, s2, s3, neck, head, arm_y = trunk
    sx, sz = shoulder
    joints.update(
        {
            "spine_01": (0, s1, -0.016 * leg),
            "spine_02": (0, s2, 0.0),
            "spine_03": (0, s3, -0.005 * leg),
            "neck_01": (0, neck, -0.011 * leg),
            "Head": (0, head, 0.005 * leg),
            "clavicle_l": (0.019 * leg, arm_y + 0.017 * leg, sz + 0.09 * leg),
            "upperarm_l": (sx, arm_y, sz),
            "lowerarm_l": (sx + upper_arm, arm_y, sz - 0.003),
            "hand_l": (sx + upper_arm + forearm, arm_y, sz),
        }
    )
    return {"name": name, "joints": joints, "hand_scale": hand_scale, "leg": leg, "shape": shape}


## Girths. Trunk rows are (height, half width, half depth to the front, to the back, the middle's z). Limb rows are
## radii at the joints and at the muscle between them. All in metres, for the look called `form`; the other looks
## scale them (`styles.py`).
MALE = _body(
    "male",
    leg=1.0,
    hip_x=0.089,
    trunk=(1.051, 1.174, 1.315, 1.488, 1.569, 1.441),
    shoulder=(0.190, -0.045),
    upper_arm=0.280,
    forearm=0.265,
    hand_scale=1.0,
    shape={
        "trunk": [
            (0.845, 0.085, 0.080, 0.085, -0.005),
            (0.940, 0.168, 0.105, 0.118, -0.005),
            (1.020, 0.158, 0.100, 0.105, 0.0),
            (1.110, 0.140, 0.096, 0.086, 0.005),
            (1.220, 0.158, 0.112, 0.098, 0.005),
            (1.330, 0.182, 0.128, 0.108, 0.0),
            (1.420, 0.178, 0.112, 0.108, -0.010),
            (1.475, 0.120, 0.085, 0.090, -0.015),
        ],
        "neck": (0.056, 0.060),
        "head": {"chin": 1.560, "top": 1.800, "half_width": 0.086, "front": 0.108, "back": 0.102, "z": 0.012},
        "upper_arm": (0.058, 0.052, 0.043),
        "forearm": (0.046, 0.031, 0.024),
        "palm": (0.044, 0.015),
        "finger": 1.0,
        "thigh": (0.090, 0.079, 0.056),
        "calf": (0.060, 0.038),
        "foot": {"half_width": 0.047, "heel": -0.052},
    },
)

FEMALE = _body(
    "female",
    leg=1.0,
    hip_x=0.092,
    trunk=(1.046, 1.160, 1.290, 1.450, 1.526, 1.404),
    shoulder=(0.160, -0.045),
    upper_arm=0.262,
    forearm=0.248,
    hand_scale=0.92,
    shape={
        "trunk": [
            (0.845, 0.085, 0.078, 0.085, -0.005),
            (0.935, 0.176, 0.100, 0.122, -0.005),
            (1.015, 0.160, 0.094, 0.104, 0.0),
            (1.110, 0.118, 0.084, 0.076, 0.004),
            (1.210, 0.132, 0.104, 0.086, 0.005),
            (1.300, 0.150, 0.128, 0.094, 0.0),
            (1.385, 0.148, 0.104, 0.096, -0.010),
            (1.438, 0.100, 0.076, 0.082, -0.015),
        ],
        "neck": (0.047, 0.050),
        "head": {"chin": 1.518, "top": 1.745, "half_width": 0.082, "front": 0.103, "back": 0.098, "z": 0.012},
        "upper_arm": (0.048, 0.042, 0.036),
        "forearm": (0.038, 0.027, 0.021),
        "palm": (0.040, 0.013),
        "finger": 0.9,
        "thigh": (0.092, 0.076, 0.051),
        "calf": (0.054, 0.034),
        "foot": {"half_width": 0.042, "heel": -0.049},
    },
)

## A small low-poly body at the scale of Deadnight's Soldier: a head a third of its height, short thick limbs, big
## hands and feet. Its legs are the reference's at 0.545, so its `motion_scale` is 0.545.
CHIBI = _body(
    "chibi",
    leg=0.545,
    hip_x=0.070,
    trunk=(0.570, 0.640, 0.715, 0.815, 0.860, 0.790),
    shoulder=(0.135, -0.020),
    upper_arm=0.155,
    forearm=0.150,
    hand_scale=0.74,
    shape={
        "trunk": [
            (0.445, 0.075, 0.070, 0.075, -0.003),
            (0.510, 0.135, 0.100, 0.105, -0.003),
            (0.570, 0.130, 0.100, 0.098, 0.0),
            (0.630, 0.122, 0.098, 0.090, 0.003),
            (0.700, 0.132, 0.104, 0.092, 0.003),
            (0.765, 0.140, 0.104, 0.094, 0.0),
            (0.805, 0.125, 0.090, 0.088, -0.005),
            (0.830, 0.080, 0.065, 0.068, -0.008),
        ],
        "neck": (0.050, 0.052),
        "head": {"chin": 0.845, "top": 1.250, "half_width": 0.165, "front": 0.180, "back": 0.170, "z": 0.012},
        "upper_arm": (0.050, 0.047, 0.043),
        "forearm": (0.047, 0.040, 0.034),
        "palm": (0.050, 0.020),
        "finger": 1.45,
        "thigh": (0.078, 0.072, 0.060),
        "calf": (0.066, 0.052),
        "foot": {"half_width": 0.055, "heel": -0.050, "height": 1.35},
    },
)

BODIES = {"male": MALE, "female": FEMALE, "chibi": CHIBI}


def socket_places(body, rest):
    """Where the seven sockets rest, in the model's space, from the body's own shape (`rest` holds its joints)."""
    place = {name: value[0] for name, value in rest.items()}
    shape, hand = body["shape"], body["hand_scale"]
    rows = shape["trunk"]
    palm_x = (place["hand_l"][0] + place["middle_01_l"][0]) / 2 + 0.01 * hand
    palm_z = (place["index_01_l"][2] + place["pinky_01_l"][2]) / 2
    palm_y = place["hand_l"][1] - shape["palm"][1] - 0.02 * hand
    head = shape["head"]
    return {
        "socket_hand_l": (palm_x, palm_y, palm_z),
        "socket_hand_r": (-palm_x, palm_y, palm_z),
        "socket_back": (0.0, rows[5][0], rows[5][4] - rows[5][3]),
        "socket_hip_l": (rows[1][1], rows[1][0], rows[1][4]),
        "socket_hip_r": (-rows[1][1], rows[1][0], rows[1][4]),
        "socket_head": (0.0, head["top"], head["z"]),
        "socket_camera": (0.0, head["chin"] + 0.5 * (head["top"] - head["chin"]), head["z"] + head["front"]),
    }
