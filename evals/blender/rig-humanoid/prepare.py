"""Input of the rig-humanoid eval: humanoid.glb, the blocky humanoid's mesh with no armature."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bpy  # noqa: E402
import humanoid  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1 :]
out = Path(argv[argv.index("--dir") + 1])
bpy.ops.wm.read_factory_settings(use_empty=True)
humanoid.build_mesh()
bpy.ops.export_scene.gltf(filepath=str(out / "humanoid.glb"), export_format="GLB")
