+++
agent = "blender-artist"
kind = "blender"
deliver = ["humanoid_rigged.glb", "build.py", "preview.png"]
read = ["tools/blender/rig-sharing.md#what-broke", "tools/blender/variants.md#modular-parts"]
+++

# Rig a humanoid

`humanoid.glb` in this folder is a blocky 1.8 m humanoid in a T-pose, facing -Y in Blender (+Z in glTF and Godot),
its left side on +X. Give it an armature and skin the mesh to it so it bends cleanly at every joint.

The armature has exactly these 17 bones, each with its head on the joint it is named for:

| Bone | Parent |
| --- | --- |
| `hips` | none (the root) |
| `spine`, then `chest`, `neck`, `head` | each the one before (`spine` under `hips`) |
| `upper_arm.L`, `upper_arm.R` | `chest` |
| `forearm.L`, `forearm.R` | the `upper_arm` of its side |
| `hand.L`, `hand.R` | the `forearm` of its side |
| `thigh.L`, `thigh.R` | `hips` |
| `shin.L`, `shin.R` | the `thigh` of its side |
| `foot.L`, `foot.R` | the `shin` of its side |

Deliver, in this folder:

- `humanoid_rigged.glb`: the armature and the skinned mesh, exported for Godot.
- `build.py`: the Blender script that makes it from `humanoid.glb`, run headless from this folder as
  `blender -b --factory-startup -P build.py -- --out <path>.glb`.
- `preview.png`: a render of the rig in a bent pose (elbows and knees bent) that you looked at, at least 512 px wide.

## The numbers it must meet

| Measure | Limit |
| --- | --- |
| Bones | exactly the 17 above, with those parents |
| Joints | every bone's head within 6 cm of the body's joint |
| Unweighted vertices; vertices on more than 4 bones; weights not summing to 1 | 0 each |
| Vertices whose largest weight is their body part's bone (away from the joints) | at least 95% |
| Mirrored vertices with mirrored weights (within 0.05) | at least 95% |
| Elbow bent 90 degrees: the hand moves with the forearm | within 1 cm; the right side moves at most 1 mm |
| Knee bent 90 degrees: the foot moves with the shin | within 1 cm; the left side moves at most 1 mm |
| `build.py` | rebuilds the same bones, joints and vertex count |
| `preview.png` | at least 512 px wide |

`gds eval check rig-humanoid <this folder>` measures all of them through the pinned Blender. Work from the brief and
the mesh, not from the check script.
