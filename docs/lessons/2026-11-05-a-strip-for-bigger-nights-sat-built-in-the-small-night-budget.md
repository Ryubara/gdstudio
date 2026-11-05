---
areas: [godot-ui, godot, ci, net]
---
# A HUD strip for nights of 15 bodies sat built and empty in the four-body night the budget plays

2026-11-05

- **Saw:** Deadnight #1191 (8 people plus up to 7 bots) failed `godot (1)`: `OVER BUDGET: canvas_items peaked at 232,
  over its limit 230`, main 229. The budget plays 4 bodies, which needs nothing the 15-body work added.
- **Cause:** the bots' chip strip (`HudBotChips`, a container and a grid) was made in `HudPoints._init`, so every HUD
  held its two canvas items with no chips in them; the budget counts every `CanvasItem`, built or empty. Counting
  settled it: the budget's local run peaked at 217 with the strip built and 215 without, main's number; a probe of the
  HUD's canvas items at 4 bodies (one fixture, a `_count(node)` over the HUD's children) reads 164 on main and on the
  fixed branch. The suspects named first (rows built up to `MAX_ROWS`) were not built at all: rows come with members.
- **Fix:** make what only a bigger night needs when the night reaches it, free it on the way down (`HudPoints` makes
  the strip past eight bodies, frees it at eight or fewer; a test checks both ends). The 15-body night is 60 HUD
  canvas items more (224): about 275 at the budget's other conditions, not covered by the budget.
- **Check for next time:** for a feature that serves a larger case, count the nodes it leaves in the small case (a
  probe over the fixture on main and on the branch, then the CI command locally and `check_budget.py`) before pushing.
  Never raise the limit.
- **Docs:** Deadnight `docs/research/performance.md`, "The CI check".
