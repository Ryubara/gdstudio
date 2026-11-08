---
areas: [godot-ui, godot, ci, tests]
---
# Hidden HUD cards held a fifth of the night's canvas-item budget, and four fixes had only looked for one node each

2026-11-05

- **Saw:** Deadnight's late-round budget read `canvas_items` 230 of 230 on main; three pull requests in one day
  (#1199, #1191, #1204) went over it by 1 to 3 and each found its own room by hand. Three lessons on exactly this
  (a node per box, a strip built in the small night, two containers on a hidden board) had each fixed the node a
  pull request added, never the 230.
- **Cause:** nobody had split the peak by part. The budget counts every `CanvasItem` of the tree, shown or not, and
  the night builds every HUD part when the HUD is made and hides most of them: counted by part (`--canvasparts=1`,
  `tools/perf/canvas_parts.py`) the end board held 21 items, the challenge prompt 9, the scoreboard 7, the marquee 6
  and the boss bar 5, all hidden for the whole of the budget's night: 43 of 215 locally. A popup card made all of
  its kinds' parts (the next-unlock line, the thumbnail chip, the poster and its prizes) for every card.
- **Fix:** each part makes its words the first time it is needed (a property whose getter builds, or `_build()` at
  the start of the method that shows it) and keeps the layout it had once built; `HudTicket.body` makes its padding
  and box on first use, so a hidden ticket is one item. 215 locally became 172, with captures identical to the
  pixel for what is visible. A test checks both ends (nothing built while idle, the whole card once used).
- **Check for next time:** when a budget sits at its limit, measure what makes it up by part first (a row's
  `canvas_parts`), then ask of each hidden part whether the budget's night needs it built. A hidden node is not free
  in a budget that counts nodes, and an out-of-tree node is an orphan (the budget limits those too), so build late,
  never build and park. Read the CI peak after the push: it differs from a local run's.
- **Docs:** Deadnight `docs/research/performance.md`, "Canvas items by part"; the kit's
  [Canvas draw calls](../engines/godot/canvas-draw-calls.md#a-node-per-box-counts-against-the-canvas-item-budget).
