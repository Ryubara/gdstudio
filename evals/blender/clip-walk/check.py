"""Check of the clip-walk eval (TASK.md beside this file)."""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bpy  # noqa: E402
import evallib  # noqa: E402

opts = evallib.args()
result = evallib.Result("clip-walk")
glb = opts.dir / "walk.glb"
SAMPLES = 24


def clip_durations(path: Path) -> dict[str, float]:
    data = evallib.glb_json(path)
    out = {}
    for anim in data.get("animations", []):
        times = [data["accessors"][s["input"]] for s in anim["samplers"]]
        out[anim.get("name", "")] = max(a["max"][0] for a in times) - min(a["min"][0] for a in times)
    return out


def correlation(a: list[float], b: list[float]) -> float:
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    da = [x - ma for x in a]
    db = [x - mb for x in b]
    den = math.sqrt(sum(x * x for x in da) * sum(x * x for x in db))
    return sum(x * y for x, y in zip(da, db)) / den if den > 1e-9 else 0.0


def forward_angle(direction) -> float:
    """Degrees a limb pointing down swings toward -Y (forward)."""
    return math.degrees(math.atan2(-direction.y, -direction.z))


def sample(rig, mesh_objs, frame: float) -> dict:
    scene = bpy.context.scene
    scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
    bpy.context.view_layer.update()
    world = {pb.name: rig.matrix_world @ pb.head for pb in rig.pose.bones}
    local = {pb.name: pb.matrix_basis.copy() for pb in rig.pose.bones}
    lowest = math.inf
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in mesh_objs:
        ev = obj.evaluated_get(depsgraph)
        mesh = ev.to_mesh()
        lowest = min(lowest, min((obj.matrix_world @ v.co).z for v in mesh.vertices))
        ev.to_mesh_clear()
    return {"world": world, "local": local, "lowest": lowest}


if not glb.is_file():
    result.error("walk.glb is missing")
    result.row("walk.glb delivered", False, "==", True)
else:
    durations = clip_durations(glb)
    result.row("clips in the file", sorted(durations), "==", ["walk"])
    result.row("walk length", durations.get("walk"), "in", [0.98, 1.02], "s")
    evallib.import_glb(glb)
    scene = bpy.context.scene
    rigs = [o for o in scene.objects if o.type == "ARMATURE"]
    rig = rigs[0] if rigs else None
    actions = [a for a in bpy.data.actions if a.name.split("_")[0].split(".")[0] == "walk"] or list(bpy.data.actions)
    need = {"hips", "thigh.L", "thigh.R", "shin.L", "shin.R", "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R"}
    if rig is None or not actions or not need <= {b.name for b in rig.data.bones}:
        result.error("no armature with the brief's bones, or no walk action, after import")
        result.row("rig and walk action imported", False, "==", True)
    else:
        action = actions[0]
        if rig.animation_data is None:
            rig.animation_data_create()
        rig.animation_data.action = action
        if getattr(action, "slots", None) and len(action.slots):
            rig.animation_data.action_slot = action.slots[0]
        start, end = action.frame_range
        meshes = [o for o in evallib.meshes() if any(m.type == "ARMATURE" and m.object == rig for m in o.modifiers)]
        frames = [start + (end - start) * i / SAMPLES for i in range(SAMPLES + 1)]
        poses = [sample(rig, meshes, f) for f in frames]
        first, last = poses[0], poses[-1]
        rot_gap = max(
            math.degrees(first["local"][n].to_quaternion().rotation_difference(last["local"][n].to_quaternion()).angle)
            for n in first["local"]
        )
        loc_gap = max((first["local"][n].to_translation() - last["local"][n].to_translation()).length for n in first["local"])
        result.row("loop seam: rotation gap, first to last frame", rot_gap, "<=", 1.0, "deg")
        result.row("loop seam: location gap, first to last frame", loc_gap, "<=", 0.002, "m")
        hips = [p["world"]["hips"] for p in poses]
        travel = max(max(h.x for h in hips) - min(h.x for h in hips), max(h.y for h in hips) - min(h.y for h in hips))
        bob = max(h.z for h in hips) - min(h.z for h in hips)
        result.row("in place: hips travel in x and y", travel, "<=", 0.02, "m")
        result.row("hips bob", bob, "in", [0.02, 0.08], "m")
        body = poses[:-1]

        def limb(top: str, child: str) -> list[float]:
            return [forward_angle(p["world"][child] - p["world"][top]) for p in body]

        thigh_l, thigh_r = limb("thigh.L", "shin.L"), limb("thigh.R", "shin.R")
        arm_l, arm_r = limb("upper_arm.L", "forearm.L"), limb("upper_arm.R", "forearm.R")
        result.row("left thigh swing, peak to peak", max(thigh_l) - min(thigh_l), ">=", 30.0, "deg")
        result.row("right thigh swing, peak to peak", max(thigh_r) - min(thigh_r), ">=", 30.0, "deg")
        result.row("thighs in opposite phase (correlation)", correlation(thigh_l, thigh_r), "<=", -0.7)
        result.row("left arm swing, peak to peak", max(arm_l) - min(arm_l), ">=", 10.0, "deg")
        result.row("arms swing against the legs (left arm with right thigh)", correlation(arm_l, thigh_r), ">=", 0.5)
        hang = []
        for p in body:
            for side in "LR":
                d = (p["world"][f"forearm.{side}"] - p["world"][f"upper_arm.{side}"]).normalized()
                hang.append(d.z)
        result.row("arms hang (mean downward share of the upper arm)", -sum(hang) / len(hang), ">=", 0.7)
        lowest = [p["lowest"] for p in body]
        result.row("lowest vertex over the clip (nothing under the floor)", min(lowest), ">=", -0.01, "m")
        grounded = sum(1 for z in lowest if z <= 0.02)
        result.row("frames with a foot on the floor (within 2 cm)", 100.0 * grounded / len(lowest), ">=", 90.0, "%")

    def compare(path):
        return clip_durations(path) == durations, f"{clip_durations(path)} against {durations}"

    evallib.rebuild(opts.dir, result, compare)
evallib.preview(opts.dir, result)
result.write(opts.json)
