"""Measure where a limb passes through another part of the body in a file of clips (kit #1009).

Plays every frame of every clip of a clip file on a mannequin the way Godot does (the clip's local bone rotations and
the pelvis's place on the model's own bones), skins the model's mesh, cuts it into parts by the bone that owns each
vertex (forearm and hand, upper arm, head, trunk, thigh, shin and foot) and, for every pair of parts that are not
joined at a joint, reports whether their surfaces cross and how deep one goes into the other. Run it with the pinned
Blender, headless, every path absolute, once for each mannequin:

    blender -b --factory-startup -P measure_limb_overlap.py -- --model <mannequin.glb> --clips <prone.glb>
        [--report <numbers.json>] [--limit 0.005]

The depth is the farthest a vertex of one part lies under the surface of the other (along that surface's normal at
its nearest point), counted only on a frame where triangles of the two parts cross and only for
vertices that rays along the axes find enclosed. With `--limit` the script exits 1
when any pair goes deeper than that many metres. The report also holds the lowest vertex of each part, for the floor.
"""

import argparse
import json
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_prone_clips import FPS, Overlap, Rig, import_glb


def read_clips(path):
    """Every clip of a file as frames of local bone rotations and the pelvis's place."""
    arm, objects = import_glb(path)
    clips = {}
    for action in bpy.data.actions:
        arm.animation_data.action = action
        arm.animation_data.action_slot = action.slots[0]
        for track in arm.animation_data.nla_tracks:
            track.mute = True
        first, last = (round(v) for v in action.frame_range)
        frames = []
        for frame_no in range(first, last + 1):
            bpy.context.scene.frame_set(frame_no)
            bpy.context.view_layer.update()
            local, pelvis = {}, None
            for pb in arm.pose.bones:
                m = (
                    (pb.parent.matrix.inverted() @ pb.matrix)
                    if pb.parent
                    else pb.matrix
                )
                local[pb.name] = np.array(m.to_quaternion().to_matrix())
                if pb.name == "pelvis":
                    pelvis = np.array(pb.matrix.translation)
            frames.append({"local": local, "pelvis": pelvis})
        clips[action.name] = frames
    for obj in objects:
        bpy.data.objects.remove(obj)
    return clips


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--clips", required=True)
    parser.add_argument("--report")
    parser.add_argument("--limit", type=float)
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    clips = read_clips(args.clips)
    arm, objects = import_glb(args.model)
    mesh = next(o for o in objects if o.type == "MESH" and o.parent == arm)
    rig = Rig(arm, mesh)
    overlap = Overlap(rig, mesh)

    report = {"model": Path(args.model).name, "clips": {}}
    worst_all = 0.0
    for name, frames in sorted(clips.items()):
        found = overlap.clip(frames)
        pairs, deepest = found["pairs"], found["deepest"]
        worst_all = max(worst_all, deepest)
        report["clips"][name] = found
        print(f"OVERLAP {report['model']} {name}: deepest {deepest * 1000:.1f} mm")
        for pair, entry in sorted(pairs.items()):
            print(
                f"  {pair}: {entry['frames']} frame(s), deepest {entry['deepest'] * 1000:.1f} mm"
                f" at frame {entry['at_frame']} ({entry['where']})"
            )
    if args.report:
        Path(args.report).write_text(
            json.dumps(report, indent=1) + "\n", encoding="utf-8"
        )
    if args.limit is not None and worst_all > args.limit:
        print(
            f"OVERLAP FAILED: {worst_all * 1000:.1f} mm is over {args.limit * 1000:.1f} mm"
        )
        raise SystemExit(1)
    print("OVERLAP DONE")


if __name__ == "__main__":
    main()
