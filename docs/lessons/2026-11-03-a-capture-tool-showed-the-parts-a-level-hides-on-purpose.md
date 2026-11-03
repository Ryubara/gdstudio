---
areas: [tests, godot]
---
# A capture showed the hidden collision and rails the level had switched off

2026-11-03

- **Saw:** the second map's views showed pillars twice (a hidden collision box drawn over the kit's pillar model) and
  pipe rails on a stair whose `RailLeft` and `RailRight` the scene had set `visible = false`, while a headless probe said
  `is_visible_in_tree()` was false.
- **Cause:** the capture script's plan views hid the upper floor and, when done, set every `VisualInstance3D` and CSG
  shape in the scene visible again, undoing what the level hides on purpose (fixtures keep their collision as invisible
  CSG; a stair's rails are switched off where a wall stands).
- **Fix:** a capture restores only the nodes it hid itself (it keeps the list). A scene that hides parts on purpose is
  checked in the player's view, not by a probe of the tree alone.
- **Docs:** [small map: art and kit, As dressed](https://github.com/Ryubara/deadnight/blob/main/docs/research/maps/small-map-art.md).
