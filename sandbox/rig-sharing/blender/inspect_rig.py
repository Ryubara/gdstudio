"""Print what a Quaternius character file holds: objects, armature transform, bones, actions and root motion.

    blender -b --factory-startup -P sandbox/rig-sharing/blender/inspect_rig.py -- <model.glb> [...]
"""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import riglib


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for path in argv:
        objs = riglib.import_glb(path)
        arm = riglib.armature_of(objs)
        print(f"== {path}")
        for o in objs:
            par = f"{o.parent.name}:{o.parent_bone}" if o.parent and o.parent_type == "BONE" else (o.parent and o.parent.name)
            tris = riglib.tris(o) if o.type == "MESH" else 0
            print(f"  {o.type:9} {o.name:28} parent={par} scale={tuple(round(s, 3) for s in o.scale)} tris={tris}")
        print(f"  bones ({len(arm.data.bones)}): {[b.name for b in arm.data.bones]}")
        root = arm.data.bones[0]
        print(f"  root bone {root.name} head={tuple(round(v, 3) for v in root.head_local)}")
        for a in bpy.data.actions:
            paths = {fc.data_path for fc in riglib.fcurves(a)}
            locs = sorted(p for p in paths if p.endswith(".location"))
            # root motion: how far the hips/root bones travel over the clip in local space
            moves = []
            for fc in riglib.fcurves(a):
                if fc.data_path.endswith(".location") and any(k in fc.data_path for k in ("Root", "Hips", "Body")):
                    vals = [k.co[1] for k in fc.keyframe_points]
                    moves.append(f"{fc.data_path.split('\"')[1]}[{fc.array_index}] {min(vals):.3f}..{max(vals):.3f}")
            print(f"  action {a.name:40} frames={tuple(a.frame_range)} loc-channels={len(locs)} {moves}")


main()
