"""Build GDStudio's prototype mannequins (kit #1149): every body in every look, rigged, with three levels of detail.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_mannequins.py -- [--out <folder>] [--body <name> ...] [--look <name> ...]

It writes `<look>_<body>.glb` (the armature and `Body_LOD0`, `Body_LOD1`, `Body_LOD2`), `rig_<body>.json` (the body's
whole rest pose, for clip tools and tests) and `report.json` (triangles, vertices, bones and bytes of every file).
A rebuild writes the same bytes.

The body's numbers are `bodies.py`, the looks `styles.py`, the skin `shapes.py`, the skeleton `skeleton.py`; the
contract of the rig is the kit page `docs/tools/blender/mannequin-rig.md`. Before a file is kept it is read back and
checked (`check_file`): the library's 65 bones with their rest rotations, the 82 bones in all, the triangle budget of
each level, the lowest vertex on the floor, at most four bones a vertex with weights that sum to one, and the left
side the mirror of the right.
"""

import argparse
import json
import struct
import sys
from pathlib import Path

import bpy

sys.dont_write_bytecode = True
import numpy as np
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import bodies  # noqa: E402
import shapes  # noqa: E402
import skeleton  # noqa: E402
import styles  # noqa: E402

## Triangles a level of detail may have (the web's player budget is 6,000 near and 2,000 far:
## docs/tools/blender/optimisation.md#budgets). The lay figure's ball joints make it the heaviest look.
BUDGET = (8000, 4000, 2200)
## The distance (m) from which the import script shows each level.
LOD_DISTANCE = (0.0, 9.0, 22.0)
GRID = 4
CELL_PX = 8

## glTF (and Godot) to Blender: (x, y, z) is (x, -z, y).
TO_BLENDER = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])


def make_palette(colours, path):
    size = GRID * CELL_PX
    image = bpy.data.images.new("palette", size, size, alpha=False)
    pixels = np.zeros((size, size, 4), np.float32)
    pixels[..., 3] = 1.0
    for i, colour in enumerate(colours):
        rgb = [int(colour[k : k + 2], 16) / 255.0 for k in (1, 3, 5)]
        col, row = i % GRID, i // GRID
        # Row 0 is the image's top; Blender's pixel rows run from the bottom. sRGB bytes go in as they are.
        top = size - (row + 1) * CELL_PX
        pixels[top : top + CELL_PX, col * CELL_PX : (col + 1) * CELL_PX, :3] = rgb
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    return image


def make_material(image):
    material = bpy.data.materials.new("Mannequin")
    material.use_nodes = True
    tree = material.node_tree
    shader = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
    texture = tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.7
    shader.inputs["Metallic"].default_value = 0.0
    return material


def make_armature(rest, parents, motion_scale):
    data = bpy.data.armatures.new("Armature")
    rig = bpy.data.objects.new("Armature", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    deform = set(skeleton.deform_bones())
    children = {}
    for name, parent in parents.items():
        children.setdefault(parent, []).append(name)
    for name in rest:
        place, basis = rest[name]
        bone = data.edit_bones.new(name)
        head = Vector(TO_BLENDER @ place)
        axes = TO_BLENDER @ basis
        # A bone's length is not exported; it is drawn to its first child, for the rig views.
        reach = [np.linalg.norm(rest[c][0] - place) for c in children.get(name, []) if c in skeleton_names()]
        length = max(0.02, min(reach[0] if reach else 0.04, 0.5))
        bone.head = head
        bone.tail = head + Vector(axes[:, 1]) * length
        matrix = Matrix.Identity(4)
        for r in range(3):
            for c in range(3):
                matrix[r][c] = axes[r, c]
            matrix[r][3] = head[r]
        bone.matrix = matrix
        bone.use_deform = name in deform
        if parents[name] is not None:
            bone.parent = data.edit_bones[parents[name]]
            bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def skeleton_names():
    return {n for n, _p, _r, _l in skeleton.LIBRARY_BONES}


def make_mesh(name, soup, style, material, rig):
    mesh = bpy.data.meshes.new(name)
    verts = [tuple(TO_BLENDER @ v) for v in soup.verts]
    mesh.from_pydata(verts, [], soup.faces)
    uv = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        cell = soup.cells[polygon.index]
        col, row = cell % GRID, cell // GRID
        for loop in polygon.loop_indices:
            uv.data[loop].uv = ((col + 0.5) / GRID, 1 - (row + 0.5) / GRID)
        polygon.use_smooth = not style["flat"]
    mesh.materials.append(material)
    mesh.update()
    mesh.validate()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    groups = {}
    for i, weights in enumerate(soup.weights):
        # At most four bones a vertex, the heaviest kept, summing to one.
        kept = sorted(weights.items(), key=lambda item: -item[1])[:4]
        total = sum(w for _b, w in kept)
        for bone, w in kept:
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([i], w / total, "REPLACE")
    obj.parent = rig
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    return obj


def read_glb(path):
    data = Path(path).read_bytes()
    length = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20 : 20 + length]), data[20 + length + 8 :]


def accessor(gltf, binary, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    kind = {5126: "<f4", 5123: "<u2", 5125: "<u4", 5121: "u1"}[acc["componentType"]]
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride")
    if stride and stride != np.dtype(kind).itemsize * width:
        raw = np.frombuffer(binary, np.uint8, stride * acc["count"], offset).reshape(acc["count"], stride)
        return np.frombuffer(raw[:, : np.dtype(kind).itemsize * width].tobytes(), kind).reshape(acc["count"], width)
    return np.frombuffer(binary, kind, acc["count"] * width, offset).reshape(acc["count"], width)


def check_file(path, rest, look):
    """Read the written file back and fail on what a mannequin can get wrong. Returns its numbers."""
    gltf, binary = read_glb(path)
    nodes = {n["name"]: n for n in gltf["nodes"]}
    problems = []
    for name, _parent, rotation, _loc in skeleton.LIBRARY_BONES:
        got = np.array(nodes[name].get("rotation", [0, 0, 0, 1]), float)
        want = np.array(rotation, float)
        if min(np.abs(got - want).max(), np.abs(got + want).max()) > 1e-4:
            problems.append(f"{name}: rest rotation {got.round(5)} is not the library's {want}")
    joints = [gltf["nodes"][j]["name"] for j in gltf["skins"][0]["joints"]]
    if len(joints) != len(rest) or set(joints) != set(rest):
        problems.append(f"{len(joints)} bones in the skin, {len(rest)} wanted")
    deform = set(skeleton.deform_bones())
    numbers = {"bones": len(joints), "bytes": Path(path).stat().st_size, "levels": []}
    for level in range(3):
        mesh = next(m for m in gltf["meshes"] if m["name"].endswith(f"LOD{level}"))
        triangles = vertices = 0
        lowest, influences, used = 1e9, 0, set()
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            position = accessor(gltf, binary, attributes["POSITION"])
            weight = accessor(gltf, binary, attributes["WEIGHTS_0"]).astype(float)
            joint = accessor(gltf, binary, attributes["JOINTS_0"])
            if weight.dtype != float:
                weight = weight.astype(float)
            triangles += gltf["accessors"][primitive["indices"]]["count"] // 3
            vertices += len(position)
            lowest = min(lowest, float(position[:, 1].min()))
            influences = max(influences, int((weight > 0).sum(1).max()))
            if np.abs(weight.sum(1) - 1).max() > 1e-3:
                problems.append(f"LOD{level}: weights do not sum to one")
            if "JOINTS_1" in attributes:
                problems.append(f"LOD{level}: more than four bones a vertex")
            used |= {joints[j] for j, w in zip(joint.ravel(), weight.ravel()) if w > 0}
            # The left half is the right half mirrored.
            keys = {tuple(k) for k in np.round(position * 2000).astype(int)}
            lone = sum(1 for k in keys if (-k[0], k[1], k[2]) not in keys)
            if lone:
                problems.append(f"LOD{level}: {lone} vertices have no mirror")
        if used - deform:
            problems.append(f"LOD{level}: skin on bones that carry none: {sorted(used - deform)}")
        if triangles > BUDGET[level]:
            problems.append(f"LOD{level}: {triangles} triangles, over {BUDGET[level]}")
        if abs(lowest) > 0.0006:
            problems.append(f"LOD{level}: the lowest vertex is at {lowest * 1000:.1f} mm, not on the floor")
        numbers["levels"].append({"triangles": triangles, "vertices": vertices, "skin_bones": len(used), "influences": influences})
    if problems:
        raise SystemExit(f"{Path(path).name}:\n  " + "\n  ".join(problems))
    return numbers


def rig_json(body, rest, parents, motion_scale):
    bones = []
    for name, (place, basis) in rest.items():
        parent = parents[name]
        local = basis if parent is None else rest[parent][1].T @ basis
        offset = place if parent is None else rest[parent][1].T @ (place - rest[parent][0])
        quaternion = Matrix(local.tolist()).to_quaternion()
        bones.append(
            {
                "name": name,
                "parent": parent,
                "place": [round(float(x), 6) for x in place],
                "translation": [round(float(x), 6) for x in offset],
                "rotation": [round(q, 7) for q in (quaternion.x, quaternion.y, quaternion.z, quaternion.w)],
            }
        )
    return {
        "body": body["name"],
        "axes": "+Y up, +Z front, +X the character's left, metres",
        "motion_scale": round(motion_scale, 6),
        "reference_hips": skeleton.REFERENCE_HIPS,
        "lod_distance": list(LOD_DISTANCE),
        "bones": bones,
    }


def build(body, look, out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    style = styles.STYLES[look]
    blank = {name: (0, 0, 0) for name, _parent in skeleton.SOCKETS}
    rest, _parents = skeleton.build_rest(body["joints"], body["hand_scale"], blank)
    rest, parents = skeleton.build_rest(body["joints"], body["hand_scale"], bodies.socket_places(body, rest))
    motion_scale = rest["pelvis"][0][1] / skeleton.REFERENCE_HIPS
    # The palette is saved only so the exporter embeds it as the PNG it is; the file itself is not kept.
    palette_path = out / f"palette_{look}.png"
    palette = make_palette(style["palette"], palette_path)
    material = make_material(palette)
    rig = make_armature(rest, parents, motion_scale)
    for level in range(3):
        soup = shapes.build(body, rest, style, level)
        make_mesh(f"Body_LOD{level}", soup, style, material, rig)
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    path = out / f"{look}_{body['name']}.glb"
    path.unlink(missing_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_animations=False,
        export_skins=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_all_influences=False,
        export_tangents=False,
    )
    palette_path.unlink(missing_ok=True)
    numbers = check_file(path, rest, look)
    (out / f"rig_{body['name']}.json").write_text(json.dumps(rig_json(body, rest, parents, motion_scale), indent=1) + "\n", encoding="utf-8", newline="\n")
    return numbers


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=HERE)
    parser.add_argument("--body", action="append", choices=sorted(bodies.BODIES))
    parser.add_argument("--look", action="append", choices=sorted(styles.STYLES))
    args = parser.parse_args(argv)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    report = {}
    for look in args.look or styles.STYLES:
        for name in args.body or bodies.BODIES:
            numbers = build(bodies.BODIES[name], look, out)
            report[f"{look}_{name}"] = numbers
            levels = " ".join(f"LOD{i} {lv['triangles']} tris" for i, lv in enumerate(numbers["levels"]))
            print(f"BUILT {look}_{name}.glb: {numbers['bytes']} bytes, {numbers['bones']} bones, {levels}")
    if not args.body and not args.look:
        (out / "report.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8", newline="\n")
    print("EXPORTED")


main()
