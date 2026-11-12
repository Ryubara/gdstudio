"""Measure limbs passing through each other in animation clips, on the skinned meshes (kit #1016).

A clip keyed by script can put a shin through a thigh on frames nobody looks at. This measures it: on every frame
of every clip, on each mannequin's real skinned mesh, how deep any body part is inside another.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P limb_overlap.py -- --clips <clips.glb> --model <mannequin.glb> [--model ...]
        [--clip <name> ...] [--limit <mm>] [--fps <rate>] [--json <file>] [--brief] [--self-test]

It exits 1 when a clip goes deeper than `--limit` (default `LIMIT_MM`). With `--brief` the `--json` file holds only
each clip's deepest crossing a body and the clip file's SHA-256, so a Godot test can read it and tell when the file
it was measured on has changed (`prone/<clip file>_overlap.json`, one a body's file, and `vault/bodies_overlap.json`,
kit #1286). A build that keys clips imports this file and calls `measure()` on its baked actions before it exports
(`vault/build_vault.py`).

Which frames it measures: every key, at the clips' own frame rate. A glb stores key times in seconds and no frame
rate, and Blender puts a key at its seconds times the scene's rate. So the command line reads the rate from the
file's key times (`clip_rate()`: the lowest usual rate at which every key is a whole frame) and sets the scene to
it before the import; the frames it prints are then the frames the build keyed, and both read the same depth
(`test_limb_overlap.py` runs a clip both ways). `--fps` names the rate for a file whose keys fit none. A script
that calls `measure()` itself has the scene at the clip's rate first (kit #1035: the scene was at 24 for every
file, so a 30 frames a second clip was measured between its keys and a crossing read 7.0 mm for 13.2).

How it measures. The mesh is cut into parts by each vertex's heaviest bone (`PARTS`): the pelvis, the chest, the
head, and each upper arm, forearm, hand, thigh, calf and foot. On a frame, every part's deformed triangles go into a
BVH. Every pair of parts that is not joined by a joint (`JOINED`) is then tested both ways: each sample of one part
(its vertices, edge middles and triangle middles) counts as inside the other part when rays from it first meet the
back of that part's faces (the part is closed for this with a fan over each rim where it was cut from its neighbour;
an open rim alone reads a point beyond a limb's end as inside it). The depth is the distance to the other part's
nearest skin: how far the sample would have to move to be out. The deepest sample of a pair is the pair's depth.

The clips play on a model as Godot plays them: each bone's rotation relative to its parent, on the model's own bone
lengths, and the pelvis's place. So the male mannequin is measured with his longer arms, not the female's. A body
with twist bones (the prototype mannequins, kit #1149) has them turned as the game's `MannequinTwist` turns them
(`apply_twist`), since no clip keys them and the forearm's and the thigh's skin follows them (kit #1293).
"""

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

## The deepest a part may be inside another (mm): skin touching skin and no more. The Universal Animation Library's
## own Sprint, Jog and Crouch clips read 0 on both mannequins, and none of its 43 clips crosses the legs.
LIMIT_MM = 5.0
## The most the rest pose may read (mm): the prototype male's thighs meet at the crotch by 1.9 mm at rest (kit #1286),
## every other body reads 0. The clips' depths include it, under `LIMIT_MM`.
REST_MM = 2.5
## The ways a sample looks to tell inside from outside (all but one must first meet the back of a face).
## The frame rates a clip file is tried at, lowest first (`clip_rate`).
RATES = (24, 25, 30, 48, 50, 60, 120)
RAYS = [Vector(v) for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]

## The part of each bone of the universal rig; a bone not named takes its parent's part. The lowest spine bone
## goes with the pelvis: on the female mannequin it carries the hips' skin down to the top of the thighs.
PARTS = {
    "pelvis": "pelvis",
    "spine_02": "chest",
    "neck_01": "head",
    "upperarm_l": "upperarm_l",
    "lowerarm_l": "lowerarm_l",
    "hand_l": "hand_l",
    "thigh_l": "thigh_l",
    "calf_l": "calf_l",
    "foot_l": "foot_l",
    "upperarm_r": "upperarm_r",
    "lowerarm_r": "lowerarm_r",
    "hand_r": "hand_r",
    "thigh_r": "thigh_r",
    "calf_r": "calf_r",
    "foot_r": "foot_r",
}
## Parts joined by a joint: their skins meet there, so the pair is not measured.
JOINED = [
    ("pelvis", "chest"),
    ("chest", "head"),
    ("chest", "upperarm"),
    ("upperarm", "lowerarm"),
    ("lowerarm", "hand"),
    ("pelvis", "thigh"),
    ("thigh", "calf"),
    ("calf", "foot"),
]
LEG = ("thigh", "calf", "foot")
ARM = ("upperarm", "lowerarm", "hand")
## The twist bones of the prototype mannequin rig, as `mannequin_twist.gd` drives them: the twist bone's name, the
## bone whose roll it reads, and whether it takes that roll back out (true) or copies it (false).
TWISTS = [
    (f"{twist}_twist_01_{side}", f"{source}_{side}", counter)
    for side in ("l", "r")
    for twist, source, counter in (
        ("upperarm", "upperarm", True),
        ("thigh", "thigh", True),
        ("lowerarm", "hand", False),
    )
]


def _kind(part):
    return part[:-2] if part[-2:] in ("_l", "_r") else part


def _joined(a, b):
    ka, kb = _kind(a), _kind(b)
    same_side = a[-2:] == b[-2:] or ka in ("pelvis", "chest", "head") or kb in ("pelvis", "chest", "head")
    return same_side and ((ka, kb) in JOINED or (kb, ka) in JOINED)


def pair_class(a, b):
    """The kind of crossing a pair is: `leg/leg`, `arm/leg`, `arm/arm`, `leg/torso` or `arm/torso`."""
    kinds = sorted("leg" if _kind(p) in LEG else "arm" if _kind(p) in ARM else "torso" for p in (a, b))
    return "/".join(kinds)


def roll_about_y(turn):
    """The part of a quaternion that is a roll about the bone's length, its Y axis (the swing-twist split, as
    `MannequinTwist.twist_about_y` does it)."""
    roll = Quaternion((turn.w, 0.0, turn.y, 0.0))
    return roll.normalized() if roll.magnitude > 1e-6 else Quaternion()


def twist_turns(turn_of, rest_of):
    """Each twist bone's rotation relative to its parent, as the game's `MannequinTwist` sets it for a pose.
    `turn_of(bone)` and `rest_of(bone)` give a bone's posed and rest rotation relative to its parent, as quaternions
    in the file's own bone axes (Blender's importer keeps them with `bone_heuristic="BLENDER"`, its default)."""
    out = {}
    for twist, source, counter in TWISTS:
        if counter:
            # the limb's turn from its rest, in its own axes; its roll is taken back out at the shoulder or hip
            out[twist] = rest_of(twist) @ roll_about_y(rest_of(source).inverted() @ turn_of(source)).inverted()
        else:
            # the hand's turn from its rest, in the forearm's axes; the wrist end of the forearm takes its roll
            out[twist] = roll_about_y(turn_of(source) @ rest_of(source).inverted()) @ rest_of(twist)
    return out


def apply_twist(arm):
    """Turn the twist bones of an armature for the pose its limbs hold now (nothing on a rig without them)."""
    bones = arm.pose.bones
    if TWISTS[0][0] not in bones:
        return
    rest = {}
    for twist, source, _ in TWISTS:
        for name in (twist, source):
            bone = arm.data.bones[name]
            rest[name] = (bone.parent.matrix_local.inverted() @ bone.matrix_local).to_quaternion()

    def turn_of(name):
        return rest[name] @ bones[name].matrix_basis.to_quaternion()

    for twist, turn in twist_turns(turn_of, rest.__getitem__).items():
        bones[twist].rotation_mode = "QUATERNION"
        bones[twist].rotation_quaternion = rest[twist].inverted() @ turn
    bpy.context.view_layer.update()


def roll_about(turn, axis):
    """The part of `turn` that is a roll about `axis` (a unit vector): the swing-twist split."""
    along = Vector((turn.x, turn.y, turn.z)).dot(axis)
    roll = Quaternion((turn.w, *(axis * along)))
    if roll.magnitude < 1e-6:
        return Quaternion()
    return roll.normalized()


def twist_bones(rest_rel):
    """The twist bones of a prototype body, which no clip keys and the game turns from the limbs' pose
    (`assets/characters/prototype/mannequin_twist.gd`): `[twist bone, the limb it follows, that limb's length axis in
    the limb's (for a hand, the forearm's) own frame, take the limb's roll out (True) or copy the hand's (False)]`.
    Empty on a body without them."""
    out = []
    for side in "lr":
        for limb, child in (("upperarm", "lowerarm"), ("thigh", "calf")):
            if f"{limb}_twist_01_{side}" in rest_rel:
                axis = rest_rel[f"{child}_{side}"].translation.normalized()
                out.append((f"{limb}_twist_01_{side}", f"{limb}_{side}", axis, True))
        if f"lowerarm_twist_01_{side}" in rest_rel:
            axis = rest_rel[f"hand_{side}"].translation.normalized()
            out.append((f"lowerarm_twist_01_{side}", f"hand_{side}", axis, False))
    return out


def twist_roll(rest_rel, source, rel, axis, counter):
    """The roll a twist bone takes, in its limb's frame: `rel` is the followed bone's rotation from its parent."""
    rest = rest_rel[source].to_quaternion()
    if counter:
        return roll_about(rest.inverted() @ rel, axis).inverted()
    return roll_about(rel @ rest.inverted(), axis)


class Body:
    """A mannequin: its armature, its skinned mesh, and the mesh cut into parts."""

    def __init__(self, arm, mesh, name):
        self.arm, self.mesh, self.name = arm, mesh, name
        bones = arm.data.bones
        self.order = [b.name for b in bones]
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        rest = {b.name: b.matrix_local.copy() for b in bones}
        self.rest_rel = {
            n: (rest[self.parent[n]].inverted() @ rest[n]) if self.parent[n] else rest[n].copy() for n in self.order
        }
        part_of = {}
        for name_ in self.order:  # parents come before children
            part_of[name_] = PARTS.get(name_) or part_of.get(self.parent[name_]) or "pelvis"
        self.part_names = sorted(set(part_of.values()))
        index = {p: i for i, p in enumerate(self.part_names)}
        data = mesh.data
        # Weld the vertices the file split at UV seams, so a part's open rims are only where it was cut.
        flat = np.empty(len(data.vertices) * 3)
        data.vertices.foreach_get("co", flat)
        _, first, welded = np.unique(np.round(flat.reshape(-1, 3), 5), axis=0, return_index=True, return_inverse=True)
        welded = welded.reshape(-1)
        self.first = first
        weights = np.zeros((len(first), len(self.part_names)))
        groups = [g.name for g in mesh.vertex_groups]
        for vertex in data.vertices:
            for g in vertex.groups:
                bone = groups[g.group]
                if bone in part_of:
                    weights[welded[vertex.index], index[part_of[bone]]] += g.weight
        vertex_part = weights.argmax(axis=1)
        data.calc_loop_triangles()
        triangles = welded[np.array([t.vertices[:] for t in data.loop_triangles], dtype=np.int64)].reshape(-1, 3)
        flat_ones = (triangles[:, 0] == triangles[:, 1]) | (triangles[:, 1] == triangles[:, 2])
        triangles = triangles[~(flat_ones | (triangles[:, 2] == triangles[:, 0]))]
        whole = (vertex_part[triangles] == vertex_part[triangles][:, :1]).all(axis=1)
        self.parts = {}
        for part, i in index.items():
            tris = triangles[whole & (vertex_part[triangles[:, 0]] == i)]
            if not len(tris):
                continue
            used = np.unique(tris)
            local = np.searchsorted(used, tris)
            directed = np.concatenate([local[:, [0, 1]], local[:, [1, 2]], local[:, [2, 0]]])
            edges, counts = np.unique(np.sort(directed, axis=1), axis=0, return_counts=True)
            # Close each open rim (where the part was cut from its neighbour) with a fan to the rim's middle, so
            # a point can be told inside from outside. The fans are only for that: depth is measured to the skin.
            open_edges = {tuple(e) for e in edges[counts == 1].tolist()}
            rim = [e for e in directed.tolist() if tuple(sorted(e)) in open_edges]
            group = {}

            def find(v, group=group):
                while group.setdefault(v, v) != v:
                    group[v] = group[group[v]]
                    v = group[v]
                return v

            for u, v in rim:
                group[find(u)] = find(v)
            loops = {}
            for u, v in rim:
                loops.setdefault(find(u), []).append((u, v))
            caps, fans = [], []
            for n, loop in enumerate(loops.values()):
                caps.append(sorted({v for edge in loop for v in edge}))
                fans += [[v, u, len(used) + n] for u, v in loop]
            self.parts[part] = {
                "verts": used,
                "local": local.tolist(),
                "closed": local.tolist() + fans,
                "caps": caps,
                "edges": edges,
            }

    def pose_from(self, source):
        """Take the source armature's pose as Godot would play it here: each bone's rotation relative to its
        parent on this body's own bone lengths, and the pelvis's place."""
        if source is self.arm:
            apply_twist(self.arm)
            return
        bones = source.pose.bones
        for name in self.order:
            bone = self.arm.pose.bones[name]
            parent = self.parent[name]
            if name not in bones or parent is None or parent not in bones:
                bone.matrix_basis = Matrix.Identity(4)
                continue
            rel = bones[parent].matrix.inverted() @ bones[name].matrix
            offset = rel.translation if name == "pelvis" else self.rest_rel[name].translation
            local = Matrix.LocRotScale(offset, rel.to_quaternion(), None)
            bone.matrix_basis = self.rest_rel[name].inverted() @ local
        bpy.context.view_layer.update()
        apply_twist(self.arm)

    def skinned(self):
        """Every welded vertex of the deformed mesh, in the world (an N x 3 array)."""
        graph = bpy.context.evaluated_depsgraph_get()
        obj = self.mesh.evaluated_get(graph)
        mesh = obj.to_mesh()
        flat = np.empty(len(mesh.vertices) * 3)
        mesh.vertices.foreach_get("co", flat)
        obj.to_mesh_clear()
        world = np.array(obj.matrix_world)
        return flat.reshape(-1, 3)[self.first] @ world[:3, :3].T + world[:3, 3]

    def overlaps(self):
        """How deep each pair of parts that no joint joins is inside each other now: `{(a, b): (metres, place)}`,
        only the pairs that cross."""
        coords = self.skinned()
        built = {}
        for part, info in self.parts.items():
            own = coords[info["verts"]]
            local = np.array(info["local"])
            samples = np.concatenate([own, own[local].mean(axis=1), own[info["edges"]].mean(axis=1)])
            built[part] = {
                "low": own.min(axis=0),
                "high": own.max(axis=0),
                "samples": samples,
                "own": own,
                "info": info,
            }
        out = {}
        names = sorted(built)
        for i, a in enumerate(names):
            for b in names[i + 1 :]:
                if _joined(a, b):
                    continue
                pa, pb = built[a], built[b]
                if (pa["low"] > pb["high"]).any() or (pb["low"] > pa["high"]).any():
                    continue
                deepest, place = 0.0, None
                for inner, outer in ((pa, pb), (pb, pa)):
                    points = inner["samples"]
                    near = points[((points >= outer["low"]) & (points <= outer["high"])).all(axis=1)]
                    if not len(near):
                        continue
                    if "skin" not in outer:
                        own, info = outer["own"], outer["info"]
                        outer["skin"] = BVHTree.FromPolygons(own.tolist(), info["local"])
                        middles = [own[cap].mean(axis=0).tolist() for cap in info["caps"]]
                        outer["solid"] = BVHTree.FromPolygons(own.tolist() + middles, info["closed"])
                    find, cast = outer["skin"].find_nearest, outer["solid"].ray_cast
                    for point in near.tolist():
                        location, normal, _index, distance = find(point)
                        if location is None or distance <= deepest:
                            continue
                        if (Vector(point) - location).dot(normal) >= 0.0:
                            continue
                        # Inside the closed part: from inside, a ray any way first meets the back of a face.
                        backs = 0
                        for way in RAYS:
                            _hit, facing, _face, reach = cast(point, way)
                            backs += reach is not None and way.dot(facing) > 0.0
                        if backs >= len(RAYS) - 1:
                            deepest, place = distance, point
                if deepest > 0.0:
                    out[(a, b)] = (deepest, place)
        return out


def key_times(path):
    """Every key time, in seconds, of every animation in a glb (read from the file, without Blender)."""
    data = Path(path).read_bytes()
    magic, _version, _length, json_length, _json_type = struct.unpack_from("<5I", data, 0)
    assert magic == 0x46546C67, f"{path} is not a glb"
    doc = json.loads(data[20 : 20 + json_length])
    binary = 20 + json_length + 8
    times = set()
    for index in {s["input"] for a in doc.get("animations", []) for s in a["samplers"]}:
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        offset = binary + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        times.update(np.frombuffer(data, "<f4", accessor["count"], offset).tolist())
    return sorted(times)


def clip_rate(path):
    """The frame rate a glb's clips were keyed at: the lowest of `RATES` at which every key time is a whole
    frame. A glb has no frame rate of its own, only key times. None when the keys fit no rate."""
    times = np.array(key_times(path))
    for rate in RATES:
        frames = times * rate
        if not len(frames) or np.abs(frames - np.round(frames)).max() < 0.01:
            return rate
    return None


def measure(source, action, frames, bodies):
    """Play `action` on the `source` armature over `frames` and measure every body on every frame. The frames are
    the scene's: the caller has the scene at the clip's frame rate, so each whole frame is a key. Returns
    `{body name: {"deepest_mm", "frame", "pair", "place", "by_class": {class: [mm, frame, pair]}, "frames": [mm],
    "pairs": {pair: [mm, frame]}}}`."""
    scene = bpy.context.scene
    source.animation_data.action = action
    source.animation_data.action_slot = action.slots[0]
    out = {
        body.name: {
            "deepest_mm": 0.0,
            "frame": None,
            "pair": None,
            "place": None,
            "by_class": {},
            "frames": [],
            "pairs": {},
        }
        for body in bodies
    }
    for frame in frames:
        scene.frame_set(frame)
        for body in bodies:
            body.pose_from(source)
            report = out[body.name]
            worst = 0.0
            for (a, b), (depth, place) in body.overlaps().items():
                mm = round(depth * 1000.0, 1)
                pair = report["pairs"].setdefault(f"{a} in {b}", [0.0, frame])
                if mm > pair[0]:
                    pair[:] = [mm, frame]
                worst = max(worst, mm)
                kind = pair_class(a, b)
                if mm > report["by_class"].get(kind, [0.0])[0]:
                    report["by_class"][kind] = [mm, frame, f"{a} in {b}"]
                if mm > report["deepest_mm"]:
                    report.update(deepest_mm=mm, frame=frame, pair=f"{a} in {b}", place=[round(x, 3) for x in place])
            report["frames"].append(worst)
    return out


def load_body(path, name=None):
    """Import a mannequin glb and return its `Body` (the skinned mesh is the one parented to the armature)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    mesh = max(
        (o for o in new if o.type == "MESH" and o.parent == arm),
        key=lambda o: len(o.data.vertices),
    )
    body = Body(arm, mesh, name or Path(path).stem)
    body.objects = new
    return body


def self_test(body):
    """The measure reads nothing on the rest pose and a deep crossing when a thigh is swung through the other."""
    for bone in body.arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    rest = max((d for d, _ in body.overlaps().values()), default=0.0)
    thigh = body.arm.pose.bones["thigh_l"]
    side = body.arm.data.bones["thigh_r"].head_local - body.arm.data.bones["thigh_l"].head_local
    down = body.arm.data.bones["calf_l"].head_local - body.arm.data.bones["thigh_l"].head_local
    axis = down.cross(side).normalized()
    turn = Matrix.Rotation(0.5, 4, axis)
    rest_l = body.arm.data.bones["thigh_l"].matrix_local
    pivot = Matrix.Translation(rest_l.translation)
    thigh.matrix = pivot @ turn @ pivot.inverted() @ rest_l
    bpy.context.view_layer.update()
    crossed = body.overlaps()
    deep = max((d for (a, b), (d, _) in crossed.items() if pair_class(a, b) == "leg/leg"), default=0.0)
    thigh.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    print(f"SELFTEST {body.name}: rest {rest * 1000:.1f} mm, a thigh swung through the other {deep * 1000:.1f} mm")
    assert rest * 1000 < REST_MM, f"{body.name}: the rest pose reads {rest * 1000:.1f} mm"
    assert deep * 1000 > 20.0, f"{body.name}: crossed legs read only {deep * 1000:.1f} mm"


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--clips", required=True)
    parser.add_argument("--model", action="append", required=True)
    parser.add_argument("--clip", action="append", default=[])
    parser.add_argument("--limit", type=float, default=LIMIT_MM)
    parser.add_argument("--fps", type=int, default=0)
    parser.add_argument("--json", default="")
    parser.add_argument("--brief", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Blender puts a key at its seconds times the scene's rate: the scene takes the file's rate before any import.
    rate = args.fps or clip_rate(args.clips)
    if not rate:
        sys.exit(f"the keys of {args.clips} are whole frames at none of {RATES} frames a second: name it with --fps")
    bpy.context.scene.render.fps = rate
    print(f"RATE {Path(args.clips).name}: {rate} frames a second ({'--fps' if args.fps else 'from its key times'})")
    bodies = [load_body(path) for path in args.model]
    if args.self_test:
        for body in bodies:
            self_test(body)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=args.clips)
    source = next(o for o in bpy.data.objects if o not in before and o.type == "ARMATURE")
    for track in source.animation_data.nla_tracks:
        track.mute = True
    own = [a for a in bpy.data.actions if not args.clip or a.name in args.clip]
    missing = set(args.clip) - {a.name for a in own}
    assert not missing, f"no clip named {sorted(missing)} in {args.clips}"
    report, failed = {}, False
    for action in sorted(own, key=lambda a: a.name):
        first, last = (round(f) for f in action.frame_range)
        off = max(abs(f - round(f)) for f in action.frame_range)
        assert off < 0.01, f"{action.name} ends {off:.2f} of a frame off a key at {rate} frames a second"
        result = measure(source, action, range(first, last + 1), bodies)
        report[action.name] = result
        for name, entry in result.items():
            entry.update(fps=rate, first_frame=first, last_frame=last)
            verdict = "ok" if entry["deepest_mm"] <= args.limit else "CROSSES"
            failed = failed or verdict != "ok"
            at = entry["frame"]
            when = "" if at is None else f" of {first} to {last} at {rate} fps, {at / rate:.3f} s"
            print(
                f"OVERLAP {action.name} {name}: {entry['deepest_mm']} mm at frame {at}{when} "
                f"({entry['pair']}) {verdict} {json.dumps(entry['by_class'])}"
            )
    if args.json and args.brief:
        report = {
            "clips_file": Path(args.clips).name,
            "sha256": hashlib.sha256(Path(args.clips).read_bytes()).hexdigest(),
            "fps": rate,
            "limit_mm": args.limit,
            "clips": {
                clip: {name: {k: entry[k] for k in ("deepest_mm", "frame", "pair")} for name, entry in on.items()}
                for clip, on in report.items()
            },
        }
    if args.json:
        Path(args.json).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8", newline="\n")
    if failed:
        sys.exit(f"limbs pass through each other by more than {args.limit} mm")


if __name__ == "__main__":
    main()
