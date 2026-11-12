"""Reads one body's pistol hold out of the project's files, for the tools that work on top of it (the rack
clip's solver and build, `assets/animation/pistol/`): the pistol's seat on `hand_r`, the `SupportHand` marker,
the line the opened left hand leaves the gun along and the five hand poses. The default body's (`female`) are
the hold scene's own (`pistol_held.tscn`, `weapon_hold.tscn` and the `pistol_*_pose.tres` files), any other
body's are in its `HoldFit` file (`pistol_fit_<body>.tres`), both written by `write_hold.gd`. `read_rifle` reads
the rifle's two-hand hold the same way (the melee build's rifle blows). Plain Python and numpy, so Blender's Python
reads it too."""

import re
from pathlib import Path

import numpy as np

DEFAULT_BODY = "female"
POSES = ("grip", "trigger", "support", "magazine", "open")
_DICTIONARY = r" = Dictionary\[StringName, Quaternion\]\(\{(.*?)\}\)"


def _place(numbers):
    """A `Transform3D(...)` as the files write it (the basis by rows, then the origin) as a 4 x 4."""
    values = [float(v) for v in numbers.split(",")]
    out = np.eye(4)
    out[:3, :3] = np.array(values[:9]).reshape(3, 3)
    out[:3, 3] = values[9:]
    return out


def _quaternions(text, block):
    """The `block` dictionary (`rotations` or `turns`) of a `HandPose`: bone name to (x, y, z, w)."""
    body = re.search(block + _DICTIONARY, text, re.S)
    found = re.findall(r'&"(\w+)": Quaternion\(([^)]*)\)', body.group(1) if body else "")
    return {name: [float(v) for v in numbers.split(",")] for name, numbers in found}


def _way(text):
    return np.array([float(v) for v in re.search(r"^support_way = Vector3\(([^)]*)\)", text, re.M).group(1).split(",")])


def _pose(text):
    return {"rotations": _quaternions(text, "rotations"), "turns": _quaternions(text, "turns")}


def read(game, body=DEFAULT_BODY):
    """The hold of `body` in the game folder `game`: {"seat", "support_hand": 4 x 4, "support_way": the three
    numbers of `WeaponHold.support_way`, "<pose>": {"rotations", "turns": {bone: (x, y, z, w)}} for each of
    `POSES`}."""
    hold = Path(game) / "gameplay" / "weapon" / "hold"
    out = {}
    if body == DEFAULT_BODY:
        held = (Path(game) / "assets" / "weapons" / "pistol" / "pistol_held.tscn").read_text(encoding="utf-8")
        for key, node in (("seat", "Pistol"), ("support_hand", "SupportHand")):
            block = held.split(f'[node name="{node}"', 1)[1].split("[node", 1)[0]
            out[key] = _place(re.search(r"transform = Transform3D\(([^)]*)\)", block).group(1))
        for pose in POSES:
            out[pose] = _pose((hold / f"pistol_{pose}_pose.tres").read_text(encoding="utf-8"))
        out["support_way"] = _way((hold / "weapon_hold.tscn").read_text(encoding="utf-8"))
        return out
    text = (hold / f"pistol_fit_{body}.tres").read_text(encoding="utf-8")
    head, _, main = text.partition("[resource]")
    for key in ("seat", "support_hand"):
        out[key] = _place(re.search(rf"^{key} = Transform3D\(([^)]*)\)", main, re.M).group(1))
    out["support_way"] = _way(main)
    blocks = {}
    for block in head.split("[sub_resource ")[1:]:
        blocks[re.search(r'id="([^"]+)"', block).group(1)] = block
    for pose in POSES:
        out[pose] = _pose(blocks[re.search(rf'^{pose}_pose = SubResource\("([^"]+)"\)', main, re.M).group(1)])
    return out


def _node_place(text, node):
    block = text.split(f'[node name="{node}"', 1)[1].split("[node", 1)[0]
    return _place(re.search(r"transform = Transform3D\(([^)]*)\)", block).group(1))


def read_rifle(game, body=DEFAULT_BODY):
    """The rifle hold of `body` (`TwoHandHold`, kit #1288's melee clips): {"rifle": the `Rifle` node's place in
    `Pivot`, "right" and "left": where the hand bones sit in the `Rifle` node's space (`RightHandTarget`,
    `LeftHandTarget`; a fit's `seat` is the inverse of the first), "<pose>": {"rotations", "turns"} for each of
    `POSES`}, all 4 x 4 in Godot's axes. The default body's are the scene's own (`rifle_held.tscn`, the
    `rifle_*_pose.tres` files), any other body's from its `HoldFit` (`rifle_fit_<body>.tres`)."""
    weapon = Path(game) / "gameplay" / "weapon"
    held = (weapon / "rifle_held.tscn").read_text(encoding="utf-8")
    out = {"rifle": _node_place(held, "Rifle")}
    if body == DEFAULT_BODY:
        out["right"] = _node_place(held, "RightHandTarget")
        out["left"] = _node_place(held, "LeftHandTarget")
        for pose in POSES:
            out[pose] = _pose((weapon / "hold" / f"rifle_{pose}_pose.tres").read_text(encoding="utf-8"))
        return out
    text = (weapon / "hold" / f"rifle_fit_{body}.tres").read_text(encoding="utf-8")
    head, _, main = text.partition("[resource]")
    out["right"] = np.linalg.inv(_place(re.search(r"^seat = Transform3D\(([^)]*)\)", main, re.M).group(1)))
    out["left"] = _place(re.search(r"^support_hand = Transform3D\(([^)]*)\)", main, re.M).group(1))
    blocks = {}
    for block in head.split("[sub_resource ")[1:]:
        blocks[re.search(r'id="([^"]+)"', block).group(1)] = block
    for pose in POSES:
        out[pose] = _pose(blocks[re.search(rf'^{pose}_pose = SubResource\("([^"]+)"\)', main, re.M).group(1)])
    return out
