"""Build `fixed.glb`: library clips with a limb swung clear of the limb it passed through (kit #1295).

The Universal Animation Library's clips were keyed on Quaternius's mannequins. On the template's own bodies (the
prototype `form` pair, kit #1187) a few of them put a forearm through a shin, because those bodies' shins and
forearms are thicker. This script does not key anything new: it takes the library's clip as it is and, on the frames
where a limb crosses, swings that one limb about its own joint by the smallest angle that clears it on every body in
`CLEAR`, eased in and out over the frames around. Every other bone's keys, the clip's length and its first and last
pose stay the library's.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_fixed_clips.py [-- --out <folder>] [--only <clip> ...]

It writes `fixed.glb` (the fixed clips on the rig's bones and a one-triangle skin, so Godot makes a `Skeleton3D`)
and `fixed_clips.json` (per clip: the swing per frame, the deepest crossing before and after on every body, and the
hash of the file measured). It fails before it writes anything when a fixed clip crosses deeper than `LIMIT_MM` on a
body of `CLEAR`, crosses deeper than the library's own clip did on any other body, or no longer starts and ends on
the library's pose. `--out` writes elsewhere (to compare a rebuild byte for byte); `--only` builds some clips
without writing, to try a number.

How a swing is found. `FIXES` names, per clip, the bone to turn and where its limb's end should go (`out`: away from
the body's middle; `up`; `fwd`). On each frame the bone is turned about the axis through its own joint that moves
the limb's end that way, one degree at a time, until none of the limb's parts is inside a part of the other limb on
the `CLEAR` bodies (`limb_overlap.py`'s measure on the skinned meshes). That gives an angle per frame, zero where the
library's pose is already clear. The angles get `MARGIN` degrees more, are held for `HOLD` frames either side and
eased with a raised-cosine window `EASE` frames wide, so the limb leaves and comes back with the motion and never
on one frame.
"""

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import limb_overlap

ASSETS = HERE.parent.parent
LIBRARIES = HERE.parent / "universal"
## The bodies a fixed clip has to be clear on, and the bodies it must not get worse on (the ones the library's clips
## were keyed on). The name is the report's.
CLEAR = {
    "form_female": ASSETS / "characters/prototype/form_female.glb",
    "form_male": ASSETS / "characters/prototype/form_male.glb",
}
KEEP = {
    "quaternius_female": ASSETS / "characters/mannequin/mannequin_female.glb",
    "quaternius_male": ASSETS / "characters/mannequin/mannequin_male.glb",
}
## The deepest a part may be inside another on a `CLEAR` body, mm (the limit of `limb_overlap.py`).
LIMIT_MM = limb_overlap.LIMIT_MM
## A body of `KEEP` may read this much deeper than on the library's clip (the measure's own noise), mm.
KEEP_SLACK_MM = 0.5
## Degrees added to the angle that just clears, frames the swing is held either side of a crossing, and the width
## of the ease in frames.
MARGIN = 2.0
HOLD = 2
EASE = 9
## The most a limb may be swung, degrees: past this the fix is a new pose, not a correction, and the build fails.
MAX_SWING = 30.0
RATE = 30

## clip: (library file, [(bone, limb end bone, way)]). The limb is the bone and everything under it; a swing may
## end with its own hold and ease, in frames. Tried and left out: `Sword_Dash` and `Sword_Heavy_Combo` (ual2), whose
## thighs pass through each other while the body turns a quarter in two frames: 30 degrees of thigh does not clear
## them, so they need their step keyed again, not a correction (the template plays neither).
FIXES = {
    "Jump_Land": ("ual1.glb", [("upperarm_l", "hand_l", "out")]),
    "Slide_Exit": ("ual2.glb", [("upperarm_r", "hand_r", "out")]),
    "NinjaJump_Land": ("ual2.glb", [("upperarm_l", "hand_l", "out")]),
}
ARM = ("upperarm", "lowerarm", "hand")
LEG = ("thigh", "calf", "foot")


def channels(action):
    return action.layers[0].strips[0].channelbag(action.slots[0]).fcurves


def limb_parts(bone):
    """The parts of `limb_overlap` a swung bone carries: an upper arm takes its forearm and hand, a thigh its
    calf and foot."""
    kind, side = bone[:-2], bone[-2:]
    chain = ARM if kind in ARM else LEG
    return {f"{k}{side}" for k in chain[chain.index(kind) :]}


def swing_axis(source, bone, end, way):
    """The axis, in the armature's space, about which turning `bone` moves the limb's end `way`."""
    pose = source.pose.bones
    along = pose[end].head - pose[bone].head
    side = 1.0 if source.data.bones[bone].head_local.x > 0.0 else -1.0
    want = {"out": Vector((side, 0, 0)), "up": Vector((0, 0, 1)), "fwd": Vector((0, -1, 0))}[way]
    axis = along.cross(want)
    assert axis.length > 1e-4, f"{bone} points straight {way}: no axis"
    return axis.normalized()


def swing(source, bone, axis, degrees, rest):
    """Turn the pose bone about `axis` through its own joint by `degrees` from `rest`, its matrix on this frame."""
    pivot = Matrix.Translation(rest.translation)
    source.pose.bones[bone].matrix = pivot @ Matrix.Rotation(math.radians(degrees), 4, axis) @ pivot.inverted() @ rest
    bpy.context.view_layer.update()


def crossing(bodies, source, parts):
    """The deepest any of `parts` is inside a part outside them, over `bodies`, in mm."""
    deepest = 0.0
    for body in bodies:
        body.pose_from(source)
        for (a, b), (depth, _place) in body.overlaps().items():
            if (a in parts) != (b in parts):
                deepest = max(deepest, depth * 1000.0)
    return deepest


def ease(raw, hold=HOLD, width=EASE):
    """The swing per frame from the angles that just clear: a margin, a hold either side, then a raised-cosine
    blur, scaled so no frame gets less than its own angle and margin."""
    raw = np.asarray(raw, dtype=float)
    need = np.where(raw > 0.0, raw + MARGIN, 0.0)
    held = np.array([need[max(0, i - hold) : i + hold + 1].max() for i in range(len(need))])
    window = np.hanning(width + 2)[1:-1]
    padded = np.pad(held, width, mode="constant")
    smooth = np.convolve(padded, window / window.sum(), mode="same")[width:-width]
    short = need > 0.0
    if short.any():
        smooth *= max(1.0, float((need[short] / smooth[short]).max()))
    smooth[smooth < 0.05] = 0.0
    return smooth


def solve(source, action, bodies, bone, end, way, hold=HOLD, width=EASE):
    """The swing of `bone` on every frame of `action` (degrees), and the axis it turns about on each."""
    scene = bpy.context.scene
    first, last = (round(f) for f in action.frame_range)
    parts = limb_parts(bone)
    raw, axes = [], []
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        rest = source.pose.bones[bone].matrix.copy()
        axis = swing_axis(source, bone, end, way)
        axes.append(axis)
        degrees = 0.0
        while crossing(bodies, source, parts) > 0.0:
            degrees += 1.0
            if degrees > MAX_SWING:
                sys.exit(f"{action.name} frame {frame}: {bone} is not clear {MAX_SWING} degrees {way}")
            swing(source, bone, axis, degrees, rest)
        raw.append(degrees)
    swings = ease(raw, hold, width)
    assert swings[0] == 0.0 and swings[-1] == 0.0, f"{action.name}: {bone} is swung on its first or last frame"
    assert swings.max() <= MAX_SWING, f"{action.name}: {bone} swung {swings.max():.1f} degrees"
    return raw, swings, axes


def key(source, action, bone, swings, axes):
    """Write the swung rotation of `bone` over the library's keys, on the frames it is swung."""
    scene = bpy.context.scene
    first = round(action.frame_range[0])
    path = f'pose.bones["{bone}"].rotation_quaternion'
    curves = sorted((c for c in channels(action) if c.data_path == path), key=lambda c: c.array_index)
    assert len(curves) == 4, f"{action.name}: {bone} has {len(curves)} rotation curves"
    values = {}
    for offset, degrees in enumerate(swings):
        if degrees == 0.0:
            continue
        frame = first + offset
        scene.frame_set(frame)
        pose = source.pose.bones[bone]
        before = pose.rotation_quaternion.copy()
        swing(source, bone, axes[offset], float(degrees), pose.matrix.copy())
        after = pose.rotation_quaternion.copy()
        if after.dot(before) < 0.0:  # the same turn, on the library's side of the sphere
            after.negate()
        values[frame] = after
    for curve in curves:
        for point in curve.keyframe_points:
            frame = round(point.co.x)
            if frame in values:
                point.co.y = values[frame][curve.array_index]
                point.handle_left.y = point.handle_right.y = point.co.y
        curve.update()
    assert len(values) == sum(1 for d in swings if d > 0.0)
    scene.frame_set(first)


def brief(result):
    return {
        name: {"deepest_mm": entry["deepest_mm"], "frame": entry["frame"], "pair": entry["pair"]}
        for name, entry in result.items()
    }


def end_poses(source, action):
    scene = bpy.context.scene
    out = []
    for frame in action.frame_range:
        scene.frame_set(round(frame))
        out.append({b.name: b.matrix.copy() for b in source.pose.bones})
    return out


def export(arm, actions, out):
    """Write the armature and the fixed clips, with a one-triangle skin so Godot makes a Skeleton3D of every bone."""
    arm.name = "Armature"  # the track paths are `Armature/Skeleton3D:<bone>`, as the libraries'
    assert arm.name == "Armature", arm.name
    mesh = bpy.data.meshes.new("FixedRig")
    mesh.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0, 0.01)], [], [(0, 1, 2)])
    proxy = bpy.data.objects.new("FixedRig", mesh)
    bpy.context.scene.collection.objects.link(proxy)
    proxy.parent = arm
    proxy.vertex_groups.new(name="root").add([0, 1, 2], 1.0, "REPLACE")
    proxy.modifiers.new("Armature", "ARMATURE").object = arm
    arm.animation_data.action = None
    for track in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(track)
    for action in actions:
        track = arm.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 0, action)
        strip.action_slot = action.slots[0]
    for action in list(bpy.data.actions):
        if action not in actions:
            bpy.data.actions.remove(action)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (arm, proxy):
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = out / "fixed.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_skins=True,
        export_materials="NONE",
        export_yup=True,
    )
    return path


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(HERE))
    parser.add_argument("--only", action="append", default=[])
    args = parser.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = RATE
    clear = [limb_overlap.load_body(path, name) for name, path in CLEAR.items()]
    keep = [limb_overlap.load_body(path, name) for name, path in KEEP.items()]
    sources = {}
    for file in sorted({file for file, _ in FIXES.values()}):
        assert limb_overlap.clip_rate(LIBRARIES / file) == RATE, f"{file} is not keyed at {RATE} frames a second"
        before = set(bpy.data.objects)
        actions = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=str(LIBRARIES / file))
        new = [o for o in bpy.data.objects if o not in before]
        arm = next(o for o in new if o.type == "ARMATURE")
        for track in arm.animation_data.nla_tracks:
            track.mute = True
        sources[file] = (arm, new, {a.name: a for a in bpy.data.actions if a not in actions})
    first_arm = next(iter(sources.values()))[0]
    for arm, _new, _actions in sources.values():  # one rig: the clips of both files go out on the first
        for bone in first_arm.data.bones:
            other = arm.data.bones[bone.name].matrix_local
            assert np.allclose(np.array(bone.matrix_local), np.array(other), atol=1e-6), bone.name

    report, fixed, failed = {}, [], []
    for clip, (file, swings_of) in FIXES.items():
        if args.only and clip not in args.only:
            continue
        arm, _new, actions = sources[file]
        action = actions[clip]
        first, last = (round(f) for f in action.frame_range)
        frames = range(first, last + 1)
        was = limb_overlap.measure(arm, action, frames, clear + keep)
        ends = end_poses(arm, action)
        entry = {"library": file, "first_frame": first, "last_frame": last, "fps": RATE, "swings": []}
        for bone, end, way, *timing in swings_of:
            raw, swings, axes = solve(arm, action, clear, bone, end, way, *timing)
            key(arm, action, bone, swings, axes)
            entry["swings"].append(
                {
                    "bone": bone,
                    "way": way,
                    "peak_degrees": round(float(swings.max()), 2),
                    "frames_swung": [first + int(np.flatnonzero(swings)[0]), first + int(np.flatnonzero(swings)[-1])]
                    if swings.any()
                    else [],
                    "frames_crossing": [first + i for i, d in enumerate(raw) if d > 0.0],
                    "degrees": [round(float(d), 2) for d in swings],
                }
            )
            print(
                f"SWING {clip} {bone} {way}: clear at up to {max(raw):.0f} degrees, keyed up to "
                f"{swings.max():.1f} on frames {entry['swings'][-1]['frames_swung']}"
            )
        now = limb_overlap.measure(arm, action, frames, clear + keep)
        for (frame, pose), label in zip(zip(action.frame_range, end_poses(arm, action)), ("first", "last")):
            del frame
            want = ends[0] if label == "first" else ends[1]
            off = max((pose[name].translation - want[name].translation).length for name in pose)
            assert off < 1e-6, f"{clip}: the {label} pose moved {off * 1000:.3f} mm from the library's"
        entry["before"], entry["after"] = brief(was), brief(now)
        for body in clear + keep:
            before_mm, after_mm = was[body.name]["deepest_mm"], now[body.name]["deepest_mm"]
            limit = LIMIT_MM if body in clear else max(LIMIT_MM, before_mm + KEEP_SLACK_MM)
            verdict = "ok" if after_mm <= limit else "CROSSES"
            if verdict != "ok":
                failed.append(f"{clip} on {body.name}: {after_mm} mm ({now[body.name]['pair']}), limit {limit}")
            print(
                f"FIXED {clip} {body.name}: {before_mm} mm -> {after_mm} mm "
                f"(frame {now[body.name]['frame']}, {now[body.name]['pair']}) {verdict}"
            )
        report[clip] = entry
        fixed.append(action)
    if failed:
        sys.exit("limbs still pass through each other:\n" + "\n".join(failed))
    if args.only:
        print("--only: nothing written")
        return
    export_arm = first_arm
    for arm, new, _actions in sources.values():
        for obj in new:
            if obj is not export_arm:
                bpy.data.objects.remove(obj, do_unlink=True)
    for body in clear + keep:
        for obj in body.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    path = export(export_arm, sorted(fixed, key=lambda a: a.name), out)
    sidecar = {
        "measured": {
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "limit_mm": LIMIT_MM,
            "clear_on": sorted(CLEAR),
            "not_worse_on": sorted(KEEP),
        },
        "clips": report,
    }
    (out / "fixed_clips.json").write_text(json.dumps(sidecar, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"BUILT {path} ({path.stat().st_size} bytes), {len(fixed)} clips")


if __name__ == "__main__":
    main()
