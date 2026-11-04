---
areas: [gameplay, godot]
---
# A one-shot effect built for a range scene ran for the rest of the night

2026-11-03

- **Saw:** Deadnight's performance review (#907, issue #929): 5 grenade blasts and 9 blast kills left 14 `BlastEffect`
  nodes still there 30 s later; each blast kept three alpha-0 draw calls and an energy-0 `OmniLight3D` (a slot of the
  8-per-mesh cap), each blast-killed zombie 7 nodes and a `_process` that moved six hidden gibs for ever. 20 blasts and
  100 blast kills: +800 nodes, +20 lights, +660 meshes.
- **Cause:** the effect was written for the grenade range, a scene thrown away after a test, and nothing in it or in its
  callers called `queue_free`. The night copied the call (`add_child`, `play`) and so inherited "lives for ever". "Faded
  to alpha 0 / energy 0" was read as "gone".
- **Fix:** a one-shot frees itself. Each part (fireball, ring, light, scorch, gibs) frees itself when its tween ends and
  the effect goes with the last part; gibs are freed at their age instead of hidden, and `_process` is off unless gibs
  fly. A test draws 20 blasts and 100 blast kills in the real night, waits the longest effect out and expects the same
  `BlastEffect`, light, mesh and node counts as before (it fails on `main`: 120 effects, +800 nodes).
- **Docs:** [Pooled and one-shot effects](../godot/one-shot-effects.md). Check: every `*.new()` + `add_child` of an
  effect in a long-lived scene has a line that says when it leaves, and a test that counts nodes before and after.
