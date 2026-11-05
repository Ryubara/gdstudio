---
areas: [godot-ui, ci]
---
# Two containers on a hidden end board took the canvas-item budget over by one

2026-11-05

- **Saw:** Deadnight #1204 (the end board's countdown beside a 44 CSS px Leave) failed `godot (1)` with `canvas_items
  peaked at 231, over its limit 230`, main 229, after two lessons on exactly this (a strip node per player box, a
  strip built in the small night).
- **Cause:** the two containers that hold the countdown beside Leave were built with the board, which every HUD holds
  (hidden) in the late-round night the budget plays. The budget counts every `CanvasItem`, shown or not. The case that
  needs them is a phone at the largest interface size with the fullest report.
- **Fix:** keep the column as it was and build the row the first time `_fit_report` needs it (`HudEndBoard._set_beside`
  moves the three parts into it and back); free it with the board (it is out of the tree while they are stacked, so
  `NOTIFICATION_PREDELETE` frees it: the first version left 234 orphans). The local CI command reads 215 (limit 230).
- **Check for next time:** before adding any node to a part every night builds, ask whether the night the budget
  plays needs it; if only a rare case does, build it then. Run the budget's command locally and read the peak from CI
  after the push, not from the local run alone.
- **Docs:** see the lessons on a strip node per player box and on a strip built in the small night.
