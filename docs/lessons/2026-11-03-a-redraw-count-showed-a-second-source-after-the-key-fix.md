---
areas: [godot-ui, godot, web]
---
# After the redraw key was added, a board still drew 4 times a second, not 3

2026-11-03

- **Saw:** the special-round marquee (Deadnight #934) was cut from 60 draws a second to a key check on the bulbs'
  chase, which steps 3 times a second; a count of the engine's `draw` signal on a real 60 fps clock read 3, 4, 4, 4.
- **Cause:** a second, forgotten source: `refresh()` (run when the round changes, and once a second for the "IN 14"
  countdown) ended in `queue_redraw()`, although that text is drawn by child labels and `_draw` reads only the size and
  the bulb phase. Reading the code had found the loop in `advance`, not this call; only the count showed it.
- **Fix:** a part records what it drew (`_drawn_phase = phase` inside `_draw`, so any source of a redraw is counted) and
  `advance` queues a redraw only when the phase it would draw differs; the `queue_redraw()` in `refresh` was removed.
  3 a second, and the saved frames are pixel-identical to the unfixed ones. The test counts `draw` signals with the part's
  own `_process` off, and fails on the old code (5 of 7 cases).
- **Check:** after a "redraw by key" fix, count the `draw` signal over a few seconds against the key's rate; any
  surplus is another `queue_redraw()` (a refresh, a setter, an event). Remove the ones whose drawn things the key
  already covers; letters and bars that are child nodes (a label's `modulate`) never need their parent to redraw.
- **Docs:** [The web page's heap](../godot/web-heap.md); Deadnight `docs/research/web-heap.md`.
