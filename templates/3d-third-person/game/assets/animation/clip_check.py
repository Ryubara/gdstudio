"""The `--check` mode every clip build of the template shares (kit #1481).

A build given `--check` writes nothing beside itself: `Check.file` and `Check.folder` turn each path it would write
into one in a temporary folder, the build runs as it always does, and `Check.finish` compares every file it wrote
with the file of the same name on disk, prints a line for each, a last line `CHECKED <n> same` or
`CHECKED <n> different`, and exits 1 when one differs. A file is `SAME` when its bytes are (a text file's once its
line ends are folded to LF, the way git stores it: a build on Windows writes CRLF where it names no line end).

`CLIP_CHECK_TOLERANCE=<x>` in the environment lets a file that is not the same bytes pass as `CLOSE` when it holds
the same thing to within rounding, for a build run on another platform than the one that wrote the committed files:
Blender on Linux and on Windows rounds the last bit of a float differently, so every clip comes out a few bytes
apart (kit #1481 measured at most 7e-7, one float32 step). A glTF file is close when its JSON is the same but for
numbers within `x` (a transform left out is its default) and every accessor holds as many values, each within `x`
(whole-number accessors exactly). A JSON file is close when it is the same but for each number within one step of
its last printed digit (a measure rounded to 0.1 mm can land on the other side of a half) or within `x`, whole
numbers exactly, and the SHA-256 strings, which name files that are themselves only close.

`CLIP_CHECK_KEEP=<folder>` keeps each file that is not the same bytes there, to read or upload it.
`check_clip_builds.py` runs every build this way.
"""

import json
import os
import re
import shutil
import struct
import sys
import tempfile
from pathlib import Path

TEXT = {".json", ".txt", ".md", ".tres"}
HASH = re.compile(r"^[0-9a-f]{64}$")
DEFAULTS = {"translation": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0, 1.0], "scale": [1.0, 1.0, 1.0]}
COMPONENTS = {5126: "f", 5125: "I", 5123: "H", 5122: "h", 5121: "B", 5120: "b"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


class Check:
    """Where a build writes in `--check` mode, and the comparison after it (does nothing when `on` is false)."""

    def __init__(self, on):
        self.on = bool(on)
        self.root = Path(tempfile.mkdtemp(prefix="clip-check-")) if self.on else None
        self.files = []  # (on disk, written instead)
        self.folders = []

    def file(self, path):
        """The path the build writes `path` to: a file of the same name in a folder of its own."""
        if not self.on or not path:
            return path
        written = self.root / str(len(self.files) + len(self.folders)) / Path(path).name
        written.parent.mkdir(parents=True)
        self.files.append((Path(path), written))
        return str(written)

    def folder(self, path):
        """The folder the build writes into in place of `path`; every file written there is compared."""
        if not self.on:
            return path
        written = self.root / str(len(self.files) + len(self.folders))
        written.mkdir(parents=True)
        self.folders.append((Path(path), written))
        return str(written)

    def pairs(self):
        found = [(disk, written) for disk, written in self.files if written.exists()]
        for disk, written in self.folders:
            for each in sorted(p for p in written.rglob("*") if p.is_file()):
                found.append((disk / each.relative_to(written), each))
        return found

    def finish(self):
        """Compare, print, remove the temporary folder and exit 1 on a difference (a no-op without `--check`)."""
        if not self.on:
            return
        pairs = self.pairs()
        different = 0
        keep = os.environ.get("CLIP_CHECK_KEEP", "")
        tolerance = float(os.environ.get("CLIP_CHECK_TOLERANCE", "0") or 0)
        for disk, written in pairs:
            verdict, how = compare(disk, written, tolerance)
            different += verdict == "DIFFERENT"
            if verdict != "SAME" and keep:
                Path(keep).mkdir(parents=True, exist_ok=True)
                shutil.copyfile(written, Path(keep) / written.name)
            size = f"{written.stat().st_size} bytes, on disk {disk.stat().st_size if disk.exists() else 'none'}"
            print(f"{verdict} {disk.name} ({size}{'; ' + how if how else ''})", flush=True)
        shutil.rmtree(self.root, ignore_errors=True)
        if not pairs:
            print("CHECKED nothing: the build wrote no file", flush=True)
            sys.exit(1)
        print(f"CHECKED {different} different" if different else f"CHECKED {len(pairs)} same", flush=True)
        if different:
            sys.exit(1)


def read(path):
    data = path.read_bytes()
    return data.replace(b"\r\n", b"\n") if path.suffix in TEXT else data


def compare(disk, written, tolerance):
    """`SAME`, `CLOSE` or `DIFFERENT`, and what was found (the largest difference, or the first that is too big)."""
    if not disk.exists():
        return "DIFFERENT", "not on disk"
    if read(disk) == read(written):
        return "SAME", ""
    if not tolerance or disk.suffix not in (".glb", ".json"):
        return "DIFFERENT", ""
    try:
        if disk.suffix == ".glb":
            largest = glb_close(disk.read_bytes(), written.read_bytes(), tolerance)
        else:
            a, b = (json.loads(p.read_text(encoding="utf-8")) for p in (disk, written))
            largest = close(a, b, tolerance, "", steps=True)
    except Apart as apart:
        return "DIFFERENT", str(apart)
    return "CLOSE", f"largest difference {largest:.2g}, tolerance {tolerance:g}"


class Apart(Exception):
    """Two files that hold different things."""


def close(a, b, tolerance, where, steps=False):
    """The largest difference between two JSON values that are the same to within rounding; Apart when not."""
    if isinstance(a, bool) or isinstance(b, bool) or a is None or b is None:
        if a is not b and a != b:
            raise Apart(f"{where}: {a!r} against {b!r}")
        return 0.0
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        if isinstance(a, int) and isinstance(b, int):
            if a != b:
                raise Apart(f"{where}: {a} against {b}")
            return 0.0
        off = abs(a - b)
        allowed = max(tolerance, 1.0001 * max(step(a), step(b)) if steps else 0.0)
        if not off <= allowed:
            raise Apart(f"{where}: {a!r} against {b!r}")
        return off
    if isinstance(a, str) and isinstance(b, str):
        if a != b and not (HASH.match(a) and HASH.match(b)):
            raise Apart(f"{where}: {a!r} against {b!r}")
        return 0.0
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            raise Apart(f"{where}: {len(a)} values against {len(b)}")
        return max((close(x, y, tolerance, f"{where}[{i}]", steps) for i, (x, y) in enumerate(zip(a, b))), default=0.0)
    if isinstance(a, dict) and isinstance(b, dict):
        largest = 0.0
        for key in sorted(set(a) | set(b)):
            if key not in a or key not in b:
                if key in DEFAULTS:  # glTF leaves out a transform that is its default
                    largest = max(largest, close(a.get(key, DEFAULTS[key]), b.get(key, DEFAULTS[key]), tolerance, key))
                    continue
                raise Apart(f"{where}/{key}: in one file only")
            largest = max(largest, close(a[key], b[key], tolerance, f"{where}/{key}", steps))
        return largest
    raise Apart(f"{where}: {type(a).__name__} against {type(b).__name__}")


def step(number):
    """One unit of a printed number's last digit (0.1 for 4.6); a whole number's is 1."""
    text = repr(float(number))
    if "e" in text or "." not in text:
        return 0.0
    digits = len(text.split(".")[1].rstrip("0"))
    return 10.0**-digits if digits else 1.0


def glb_close(a, b, tolerance):
    """The largest difference between two glTF binaries that hold the same clips to within `tolerance`."""
    (doc_a, bin_a), (doc_b, bin_b) = glb(a), glb(b)
    largest = close(layout_free(doc_a), layout_free(doc_b), tolerance, "")
    for index, accessor in enumerate(doc_a.get("accessors", [])):
        values_a, values_b = values(doc_a, bin_a, index), values(doc_b, bin_b, index)
        whole = accessor["componentType"] != 5126
        for x, y in zip(values_a, values_b):
            off = abs(x - y)
            if (whole and off) or not off <= tolerance:
                raise Apart(f"accessor {index}: {x!r} against {y!r}")
            largest = max(largest, off)
    return largest


def layout_free(doc):
    """The glTF JSON without where the values lie in the binary and their bounds, which the values decide."""
    doc = json.loads(json.dumps(doc))
    for key, drop in (
        ("buffers", ("byteLength",)),
        ("bufferViews", ("byteLength", "byteOffset")),
        ("accessors", ("byteOffset", "min", "max")),
    ):
        for each in doc.get(key, []):
            for name in drop:
                each.pop(name, None)
    return doc


def glb(data):
    return glb_doc(data), glb_bin(data)


def glb_doc(data):
    length = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20 : 20 + length])


def glb_bin(data):
    start = 20 + struct.unpack_from("<I", data, 12)[0]
    if start >= len(data):
        return b""
    length = struct.unpack_from("<I", data, start)[0]
    return data[start + 8 : start + 8 + length]


def values(doc, binary, index):
    accessor = doc["accessors"][index]
    if "bufferView" not in accessor:
        return []
    view = doc["bufferViews"][accessor["bufferView"]]
    kind = COMPONENTS[accessor["componentType"]]
    width = WIDTH[accessor["type"]]
    size = struct.calcsize(kind)
    stride = view.get("byteStride", 0) or size * width
    base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    out = []
    for item in range(accessor["count"]):
        out.extend(struct.unpack_from(f"<{width}{kind}", binary, base + item * stride))
    return out
