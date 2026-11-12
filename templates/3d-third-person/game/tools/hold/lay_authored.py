"""Lays the hand-set poses into a solve's own file, so a stage run on it afterwards measures the hands the
game shows (kit #1213).

    uv run --no-project --with numpy --with scipy python tools/hold/lay_authored.py <abs>/rig.json
        <abs>/hold.json tools/hold/pistol_authored.json --body=female|male

`write_hold.gd` lays `pistol_authored.json` over the files it writes, which a later stage of the solver never
reads: `--magazine-only` and `--way-only` go on from the solve's file. Run on the solver's own right little
finger and thumb, they put the hand under the magazine and the way off the gun through the hand-set ones
(5.7 mm on the female's way). This writes the `grip` and `support` angles and the lifted `thumb` of the
body's entry into the solve's angles and rotations; run it after the full solve and before either stage.
"""

import json
import sys

import hold_rig as R
import numpy as np
import solve_pistol_hold as P
from hold_hand import FINGERS


def main():
    rigs, pistol = R.load(sys.argv[1])
    body = P.body_option()
    scene = P.Scene(rigs[body], pistol, sys.argv[1] + f".{body}.gun.npz")
    out = P.restore(scene)
    with open(sys.argv[3], encoding="utf-8") as file:
        authored = json.load(file).get(body, {})
    right, left = scene.right, scene.left
    for finger, angles in authored.get("grip", {}).items():
        out["angles"]["right"][finger] = angles
        right.set(finger, np.array(angles, float))
    out["grip"] = right.quaternions()
    held = left.angles_of(out["support"])
    for finger in FINGERS:
        left.angles[finger] = held[finger].copy()
    left._apply_all()
    for finger, angles in authored.get("support", {}).items():
        left.set(finger, np.array(angles, float))
    out["angles"]["left"] = {finger: left.angles[finger].tolist() for finger in FINGERS}
    out["support"] = left.quaternions()
    if "thumb" in authored:
        carried = right.angles["thumb"].copy()
        over = np.array(authored["thumb"]["thumb"], float)
        out["angles"]["thumb_over"] = over.tolist()
        right.set("thumb", over)
        out["thumb"] = right.quaternions(["thumb"])
        right.set("thumb", carried)
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())
    print("laid", body, sorted(authored))


if __name__ == "__main__":
    main()
