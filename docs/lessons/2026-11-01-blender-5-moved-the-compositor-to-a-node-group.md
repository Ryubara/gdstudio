---
areas: [godot, blender]
---
# Blender 5 moved the compositor to a node group

2026-11-01

- **Saw:** a compositor setup written for Blender 4 failed in the pinned Blender 5.2: `scene.use_nodes` and
  `scene.node_tree` no longer exist (Deadnight #438).
- **Cause:** Blender 5's compositor is a node group assigned to `scene.compositing_node_group`, and nodes such as
  Glare take their settings as input sockets, not properties.
- **Fix:** create a compositor node group, assign it to `scene.compositing_node_group`, and set Glare's values on
  its inputs. Check the pinned version's API (`gds tool path blender`), not memory.
- **Docs:** [Key art](../blender/key-art.md).
