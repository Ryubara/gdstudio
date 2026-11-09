"""Remove the animations from a .glb and keep everything else byte for byte.

The Quaternius Universal Animation Library glb files hold the male mannequin together with 43 clips.
The template plays the clips from its own animation libraries, so the model file keeps only the mesh,
the skin and the skeleton: nothing is re-exported, the mesh, node and skin data are copied as they are
and only the animation accessors and buffer views are dropped.

    python tools/models/strip_glb_animations.py <in.glb> <out.glb>
"""

import json
import struct
import sys
from pathlib import Path

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def read_glb(data: bytes) -> tuple[dict, bytes]:
    magic, version, _length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF" or version != 2:
        raise ValueError("not a glTF 2.0 binary")
    offset = 12
    document, binary = None, b""
    while offset < len(data):
        size, kind = struct.unpack("<II", data[offset : offset + 8])
        chunk = data[offset + 8 : offset + 8 + size]
        offset += 8 + size
        if kind == JSON_CHUNK:
            document = json.loads(chunk)
        elif kind == BIN_CHUNK:
            binary = chunk
    if document is None:
        raise ValueError("no JSON chunk")
    return document, binary


def used_accessors(document: dict) -> list[int]:
    """Every accessor the meshes and skins still need, in their old order."""
    used: set[int] = set()
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            used.update(primitive["attributes"].values())
            if "indices" in primitive:
                used.add(primitive["indices"])
            for target in primitive.get("targets", []):
                used.update(target.values())
    for skin in document.get("skins", []):
        if "inverseBindMatrices" in skin:
            used.add(skin["inverseBindMatrices"])
    return sorted(used)


def strip(document: dict, binary: bytes) -> tuple[dict, bytes]:
    document.pop("animations", None)
    keep = used_accessors(document)
    accessor_map = {old: new for new, old in enumerate(keep)}
    views = sorted({document["accessors"][a]["bufferView"] for a in keep})
    view_map = {old: new for new, old in enumerate(views)}

    out = bytearray()
    new_views = []
    for old in views:
        view = dict(document["bufferViews"][old])
        start = view.get("byteOffset", 0)
        while len(out) % 4:
            out.append(0)
        view["byteOffset"] = len(out)
        out += binary[start : start + view["byteLength"]]
        new_views.append(view)
    while len(out) % 4:
        out.append(0)

    new_accessors = []
    for old in keep:
        accessor = dict(document["accessors"][old])
        accessor["bufferView"] = view_map[accessor["bufferView"]]
        new_accessors.append(accessor)
    document["accessors"] = new_accessors
    document["bufferViews"] = new_views
    document["buffers"] = [{"byteLength": len(out)}]

    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {
                k: accessor_map[v] for k, v in primitive["attributes"].items()
            }
            if "indices" in primitive:
                primitive["indices"] = accessor_map[primitive["indices"]]
    for skin in document.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = accessor_map[skin["inverseBindMatrices"]]
    return document, bytes(out)


def write_glb(document: dict, binary: bytes) -> bytes:
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    body = struct.pack("<II", len(text), JSON_CHUNK) + text
    body += struct.pack("<II", len(binary), BIN_CHUNK) + binary
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def main() -> None:
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    document, binary = strip(*read_glb(source.read_bytes()))
    target.write_bytes(write_glb(document, binary))
    print(f"{target}: {target.stat().st_size} bytes, from {source.stat().st_size}")


if __name__ == "__main__":
    main()
