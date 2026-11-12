"""`Crouch_Walk`: walking crouched at the game's 1.5 m/s (kit #1160). Replaces `ual1/Crouch_Fwd`.

The library's crouch walk takes 60 steps a minute and its planted sole moves at anything from 0.04 to 0.96 m/s, so
at the game's speed its feet cover 30 % of the ground and a sole wanders 574 mm in a contact; its arms hold still
and its head rises 27 mm over the crouched capsule (`docs/tools/blender/own-animation.md#audit-gaits`). Ours is
written as its footfalls (the research and its sources are in `../README.md`):

- **The feet hold the floor at 1.5 m/s.** Each sole is one place on the floor for its whole contact; the speed,
  the cadence and the planted share are inputs.
- **Carried like its idle.** The pelvis's height, the trunk's fold, the head and each arm's carriage are the
  shipped crouch idle's, so the blend between the two neither pumps nor straightens. The left foot lands at
  frame 0.
- **No side is the other's mirror.** The steps are half a stride apart and the same length, as a steady gait's
  must be; everything else has a number per side (a pair is `[left, right]`): the right foot tracks wider and
  turns out further, its knee swings wider, the trunk keeps a share of the idle's turn and tilt, the left arm is
  carried bent beside its thigh and swings little while the right hangs longer and swings freely.
- **The body rides level.** A walk on bent legs has a nearly flat centre of mass: the pelvis dips a little as each
  leg takes the weight, where an upright walk rises over a straight leg.
- **The weight goes over the foot that carries it**: the centre of mass is solved to a point that moves toward
  each planted foot, and the free leg's hip drops.
- **The arms swing**, each against its own side's leg, from bent elbows, and the shoulders turn against the hips.
"""

import math

from gdsanim import maths, overlap
from gdsanim.build import Clip
from gdsanim.maths import FPS
from gdsanim.plan import ContactPlan, Footfall, Travel
from gdsanim.rig import SIDES

from . import crouch_idle

## What each number of a style's `crouch_walk` section means, with the values a style starts from.
DEFAULTS = {
    "frames": 22,  # one stride (two steps); even, so the halves mirror
    "speed": 1.5,  # metres a second (`CharacterTuning.crouch_speed`)
    "planted": 0.62,  # the share of the stride a foot is on the floor
    "lead": 0.03,  # metres the footfalls sit ahead of where they would be centred under the hip
    "track": [0.0, 0.018],  # metres each foot lands wider than the rest stance
    "toe_out": [4.0, 11.0],  # degrees each foot points outward
    "knee_out": [8.0, 14.0],  # degrees each knee points outward of its foot
    "heel_strike": 0.0,  # degrees the toes are up as the heel lands (bent legs land nearly flat)
    "roll_in": 0.0,  # frames the foot takes to come flat
    "toe_off": 54.0,  # degrees the heel is up as the toes leave
    "heel_rise": 1.0,  # the share of the contact the heel takes to get there (1: it starts to rise as the foot lands)
    "clearance": 0.045,  # metres the ball of the foot clears the floor by in its swing
    "toe_reach": 0.026,  # metres the male mannequin's toes are longer than the reference body's (24 mm, measured)
    "lift": 0.056,  # metres the pelvis is carried higher than in the crouch idle
    "dip": 0.016,  # metres the pelvis goes down and up, twice a stride
    "dip_at": 0.22,  # where in a step (0 landing, 1 the next landing) the pelvis is lowest
    "shift": 0.3,  # how far the weight goes toward the planted foot (1 is over it)
    "ahead": -0.03,  # metres the centre of mass rides ahead of the middle of the feet's sweep
    "hip_turn": 7.0,  # degrees the pelvis turns with the leg that swings forward
    "hip_tip": 3.0,  # degrees the free leg's hip drops
    "chest_turn": 6.0,  # degrees the shoulders turn against the hips
    "chest_more": 8.0,  # degrees the trunk folds further than in the crouch idle
    "stance": 0.5,  # the share of the crouch idle's turn and tilt (pelvis, chest and head) the walk keeps
    "arm_swing": [10.0, 18.0],  # degrees each upper arm swings to each side of its hang
    "arm_bend": [0.3, 0.6],  # degrees each elbow closes for each degree its arm swings forward
    "elbow": [74.0, 36.0],  # degrees each elbow bends
    "arm_out": [18.0, 10.0],  # degrees each arm is carried wider than in the crouch idle, outside the thigh that rises to it
    "arm_fore": [-24.0, -20.0],  # degrees each arm hangs further forward than in the crouch idle
    "wrist": [8.0, 5.0],  # degrees each wrist bends toward the palm (the idle's resting hand droops further)
    "arm_twist": 0.0,  # the share of the crouch idle's inward turn each upper arm keeps
    "arm_clear": [0.10, 0.10],  # metres each hand keeps from its thigh's line
    "finger_live": [2.0, 4.0],  # degrees each hand's fingers open and close with the swing
    "head_turn": 0.35,  # the share of the chest's turn the head takes (0 keeps it facing the way it goes)
}
PARTS = crouch_idle.PARTS
AT = crouch_idle.AT


def describe(rig, style, name: str = "Crouch_Walk", joined=None) -> Clip:
    n = style.numbers("crouch_walk", DEFAULTS)
    frames, speed = int(n["frames"]), float(n["speed"])
    assert frames % 2 == 0, "a stride's frames must be even"
    # The carriage is the shipped crouch idle's.
    idle_style = joined.style("Crouch_Idle") if joined else style
    c = idle_style.numbers("crouch_idle", crouch_idle.DEFAULTS)
    if joined:
        height = float(joined.start("Crouch_Idle")["spec"]["pelvis"]["place"][1])
    else:
        height = float(rig.rest_pos["pelvis"][1]) * c["fold"]
    stance = n["planted"] * frames
    reach = 0.5 * speed * stance / FPS
    falls = []
    for s, sign in SIDES:
        land = 0.0 if s == "l" else frames / 2.0
        ball = rig.sole[s]["ball"]
        place = (ball[0] + sign * n["track"][AT[s]], speed * land / FPS + reach + n["lead"])
        falls.append(
            Footfall(
                s,
                land,
                land + stance,
                place,
                yaw=sign * n["toe_out"][AT[s]],
                heel_strike=n["heel_strike"],
                roll_in=n["roll_in"],
                toe_off=n["toe_off"],
                roll_out=n["heel_rise"] * stance,
            )
        )
    plan = ContactPlan(frames, falls, Travel.steady(speed), clearance=n["clearance"], toe_reach=n["toe_reach"])
    half = frames / 2.0

    def side_of(f: float) -> float:
        """+1 with the weight on the left foot, -1 on the right, crossing as the next foot lands."""
        return math.cos(2.0 * math.pi * (f - 0.5 * stance) / frames)

    def spec(f: int) -> dict:
        root, _ = plan.travel.at(float(f))
        phase = 2.0 * math.pi * f / frames
        step = (f % half) / half
        dip = 0.5 * n["dip"] * (1.0 + math.cos(2.0 * math.pi * (step - n["dip_at"])))
        w = side_of(float(f))
        turn = -n["hip_turn"] * math.cos(phase)
        tip = n["hip_tip"] * w
        arms, fingers, legs = {}, {}, {}
        for s, sign in SIDES:
            i = AT[s]
            swing = -sign * n["arm_swing"][i] * math.cos(phase)
            arms[s] = {
                "swing": c["arm_swing"][i] + n["arm_fore"][i] + swing,
                "out": c["arm_out"][i] + n["arm_out"][i],
                "twist": n["arm_twist"] * c["arm_twist"][i],
                "clear": n["arm_clear"][i],
                "bend": n["elbow"][i] + n["arm_bend"][i] * swing,
                "pronate": c["pronate"][i],
                "wrist": n["wrist"][i],
                "carry": c["carry"][i],
            }
            curls = {
                finger: max(
                    c["curl"][k]
                    + (0.5 if finger == "thumb" else 1.0)
                    * (c["curl_more"][i] - n["finger_live"][i] * swing / max(n["arm_swing"][i], 1e-6)),
                    0.0,
                )
                for k, finger in enumerate(crouch_idle.FINGER_NAMES)
            }
            curls["thumb_out"] = c["thumb_out"][i]
            fingers[s] = curls
            legs[s] = plan.foot(rig, s, float(f))
            yaw = legs[s]["foot"][1]
            legs[s]["knee"] = maths.body_turn(0.0, yaw + sign * n["knee_out"][i], 0.0) @ maths.Z
        chest_turn = n["chest_turn"] * math.cos(phase)
        keep = n["stance"]
        pelvis, chest, head = c["pelvis"], c["chest"], c["head"]
        return {
            "pelvis": {
                "place": root + (0.0, height + n["lift"] - dip, rig.rest_pos["pelvis"][2]),
                "turn": (pelvis[0], keep * pelvis[1] + turn, keep * pelvis[2] - tip),
            },
            "chest": (chest[0] + n["chest_more"], keep * chest[1] + chest_turn, keep * chest[2] + 0.6 * tip),
            "head": (head[0], keep * head[1] + n["head_turn"] * chest_turn, keep * head[2]),
            "arm": arms,
            "fingers": fingers,
            "leg": legs,
        }

    middle = 0.5 * (rig.sole["l"]["heel"][2] + rig.sole["l"]["toe"][2])

    def balance(f: int, at: dict) -> tuple:
        root, _ = plan.travel.at(float(f))
        x = n["shift"] * side_of(float(f)) * (rig.sole["l"]["ball"][0] + 0.5 * sum(n["track"]))
        x += 0.5 * (n["track"][0] - n["track"][1])
        return float(root[0] + x), float(root[2] + middle + n["lead"] + n["ahead"])

    numbers = style.overlap("crouch_walk")
    cadence = 60.0 * FPS / half
    declared = {
        "ceiling": crouch_idle.CEILING,
        "ranges": {
            "cadence": (cadence - 3.0, cadence + 3.0),
            "planted_share": (0.58, 0.68),
            "bob_mm": (0.0, 35.0),
        },
        "distance": speed * frames / FPS,
        # A stride of 26 frames has a key in three on its bending joints: nothing in it holds still.
        "keys_kept": 0.75,
        "kb_a_second": 24.0,
    }
    return Clip(
        name=name,
        frames=frames,
        plan=plan,
        spec=spec,
        balance=balance,
        chains=overlap.chains_from(numbers, PARTS),
        kind="gait",
        declared=declared,
        replaces="ual1/Crouch_Fwd",
        style=style.letter,
    )
