"""Input of the clip-walk eval: humanoid_rigged.glb, the blocky humanoid skinned to its 17-bone armature."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bpy  # noqa: E402
import humanoid  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1 :]
out = Path(argv[argv.index("--dir") + 1])
bpy.ops.wm.read_factory_settings(use_empty=True)
body = humanoid.build_mesh()
humanoid.build_rig(body)
bpy.ops.export_scene.gltf(filepath=str(out / "humanoid_rigged.glb"), export_format="GLB", export_animations=False)
