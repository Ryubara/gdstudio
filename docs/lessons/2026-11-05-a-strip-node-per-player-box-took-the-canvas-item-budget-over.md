---
areas: [godot-ui, godot, ci]
---
# A strip node on every player box took the night's canvas-item budget over

2026-11-05

- **Saw:** Deadnight #1199 added a `Control` (a strip behind the level and name) to each plated player box and CI
  `godot (1)` failed with `OVER BUDGET: canvas_items peaked at 233, over its limit 230`. Main peaks at 229, four boxes
  in the late-round night; the one new node a box was the whole difference.
- **Cause:** the late-round budget (`tools/perf/budget.json`) counts every `CanvasItem` in the tree, not draw calls. A
  tab behind a label is a node, and the node count a box has is multiplied by the party. The headroom is 1 (229 of 230).
- **Fix:** draw the strip in a canvas item the box already had, the points tab (same colour, drawn right after it,
  `draw_set_transform` to the box's coordinates), and make the strip a `RefCounted` that holds its rect, colour and
  visibility and emits `changed`. Peak back to main's 229 (the same local run of the CI command: 218 with the node, 214
  without, four boxes). Never raise the limit for a look.
- **Check for next time:** before adding a node per box, per seat or per card, count it against the budget (limit
  minus main's peak, from the last green `godot (1)` job summary); run the CI command locally
  (`--autopilot --rounds=12 --startround=12 ... --sample=1 --out=<json>`, then `tools/perf/check_budget.py`). Prefer
  a second `_draw` shape in a neighbour over a new node.
- **Docs:** [Canvas draw calls](../engines/godot/canvas-draw-calls.md#a-node-per-box-counts-against-the-canvas-item-budget).
