"""The glb with a frozen clip list, and `clips.json`.

The file is written here, byte by byte, not exported from Blender: the same clips give the same bytes, a track holds
only the keys the reducer kept, and a clip holds only the tracks of the bones it names. It carries the body's
skeleton with a one-triangle mesh skinned to the root in place of the body's mesh, because Godot makes its
`Skeleton3D` from a skin and the track paths (`Armature/Skeleton3D:<bone>`) come from it.

A looping clip is named `<Name>_Loop` in the file: Godot's importer drops the suffix and makes it loop, as it does
for the Universal Animation Library's clips beside ours.

`write_model_with_clips` writes the other kind of file: a body's own glb with clips added to it, for a renderer
that wants the mesh and the clips in one file (the review sheet's strip). It is never shipped.
"""

import json
import struct
from pathlib import Path

import numpy as np

from . import FPS
from .rig import Rig

_FLOAT, _UBYTE, _USHORT = 5126, 5121, 5123


class _Buffer:
    """A glb's binary chunk as it is built: accessors, each in its own view, the same bytes stored once."""

    def __init__(self):
        self.data = bytearray()
        self.views, self.accessors, self._seen = [], [], {}

    def add(self, array: np.ndarray, kind: str, component: int = _FLOAT, bounds: bool = False) -> int:
        dtype = {_FLOAT: "<f4", _UBYTE: "u1", _USHORT: "<u2"}[component]
        raw = np.ascontiguousarray(array, dtype=dtype).tobytes()
        key = (raw, kind, component)
        if key in self._seen:
            return self._seen[key]
        while len(self.data) % 4:
            self.data.append(0)
        self.views.append({"buffer": 0, "byteOffset": len(self.data), "byteLength": len(raw)})
        self.data += raw
        accessor = {
            "bufferView": len(self.views) - 1,
            "componentType": component,
            "count": int(len(array)),
            "type": kind,
        }
        if bounds:
            cast = np.asarray(array, dtype=dtype).reshape(len(array), -1)
            accessor["min"] = [float(v) for v in cast.min(axis=0)]
            accessor["max"] = [float(v) for v in cast.max(axis=0)]
        self.accessors.append(accessor)
        self._seen[key] = len(self.accessors) - 1
        return self._seen[key]


def _pack(gltf: dict, binary: bytearray) -> bytes:
    while len(binary) % 4:
        binary.append(0)
    gltf["buffers"] = [{"byteLength": len(binary)}]
    text = json.dumps(gltf, separators=(",", ":"), ensure_ascii=True).encode("ascii")
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    return (
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(text), b"JSON")
        + text
        + struct.pack("<I4s", len(binary), b"BIN\x00")
        + bytes(binary)
    )


def _animation(buffer: _Buffer, rig: Rig, clip: dict) -> dict:
    """One clip as a glTF animation. `clip` has `name`, `loop`, `rotation` and `translation` ([frame, node, ...]),
    and `kept`, the frames each track keeps (`{"rotation": {bone: frames}, "place": {bone: frames}}`)."""
    samplers, channels = [], []
    rows = [("rotation", "rotation", "VEC4", clip["rotation"]), ("place", "translation", "VEC3", clip["translation"])]
    for kind, path, shape, values in rows:
        for bone in sorted(clip["kept"][kind], key=lambda n: rig.index[n]):
            kept = np.asarray(clip["kept"][kind][bone])
            times = buffer.add((kept / FPS).reshape(-1, 1), "SCALAR", bounds=True)
            output = buffer.add(values[kept, rig.index[bone]], shape)
            samplers.append({"input": times, "interpolation": "LINEAR", "output": output})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": rig.index[bone], "path": path}})
    name = clip["name"] + ("_Loop" if clip["loop"] else "")
    return {"name": name, "samplers": samplers, "channels": channels}


def glb_bytes(rig: Rig, clips: list, mesh_name: str = "OwnClips") -> bytes:
    """The bytes of a clip file: the rig's skeleton, a one-triangle stand-in mesh skinned to the root, the clips."""
    source = rig.glb.json
    buffer = _Buffer()
    skin = source["skins"][0]
    root_slot = skin["joints"].index(rig.index[rig.parent["pelvis"]])
    nodes, mesh_nodes = [], 0
    for node in source["nodes"]:
        copy = {k: node[k] for k in ("name", "children", "translation", "rotation", "scale") if k in node}
        if "mesh" in node:
            mesh_nodes += 1
            if mesh_nodes == 1:
                copy["name"], copy["mesh"], copy["skin"] = mesh_name, 0, 0
        nodes.append(copy)
    assert mesh_nodes >= 1, f"{rig.path.name} has no mesh node to stand in for"
    position = np.array([[0.0, 0.0, 0.0], [0.01, 0.0, 0.0], [0.0, 0.01, 0.0]])
    attributes = {
        "POSITION": buffer.add(position, "VEC3", bounds=True),
        "NORMAL": buffer.add(np.tile([0.0, 0.0, 1.0], (3, 1)), "VEC3"),
        "JOINTS_0": buffer.add(np.tile([root_slot, 0, 0, 0], (3, 1)), "VEC4", _USHORT),
        "WEIGHTS_0": buffer.add(np.tile([1.0, 0.0, 0.0, 0.0], (3, 1)), "VEC4"),
    }
    inverse_bind = rig.glb.accessor(skin["inverseBindMatrices"]).reshape(-1, 16)
    gltf = {
        "asset": {"version": "2.0", "generator": "gdsanim (GDStudio)"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": list(source["scenes"][source.get("scene", 0)]["nodes"])}],
        "nodes": nodes,
        "meshes": [{"name": mesh_name, "primitives": [{"attributes": attributes, "mode": 4}]}],
        "skins": [{"joints": list(skin["joints"]), "inverseBindMatrices": buffer.add(inverse_bind, "MAT4")}],
    }
    if "name" in skin:
        gltf["skins"][0]["name"] = skin["name"]
    gltf["animations"] = [_animation(buffer, rig, clip) for clip in clips]
    gltf["bufferViews"], gltf["accessors"] = buffer.views, buffer.accessors
    return _pack(gltf, buffer.data)


def model_with_clips_bytes(rig: Rig, clips: list) -> bytes:
    """The body's own glb with `clips` in place of whatever clips it had (a review file, never shipped)."""
    source = json.loads(json.dumps(rig.glb.json))
    buffer = _Buffer()
    buffer.data = bytearray(rig.glb.bin[: source["buffers"][0]["byteLength"]])
    buffer.views, buffer.accessors = source["bufferViews"], source["accessors"]
    source["animations"] = [_animation(buffer, rig, clip) for clip in clips]
    return _pack(source, buffer.data)


def write_clips_json(path: Path, records: dict) -> None:
    """`clips.json`: what the game needs to know of each clip that the glb cannot say."""
    Path(path).write_text(json.dumps(records, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def read_keys(path: Path) -> dict:
    """The clips of a glb as `{name: {(bone, path): (times, values)}}`, for comparing two builds key by key."""
    from .rig import audit_clips

    glb = audit_clips.Glb(Path(path))
    out = {}
    for anim in glb.json.get("animations", []):
        tracks = {}
        for channel in anim["channels"]:
            sampler = anim["samplers"][channel["sampler"]]
            bone = glb.json["nodes"][channel["target"]["node"]]["name"]
            tracks[(bone, channel["target"]["path"])] = (
                glb.accessor(sampler["input"])[:, 0],
                glb.accessor(sampler["output"]),
            )
        out[anim["name"]] = tracks
    return out
