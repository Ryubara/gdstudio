---
areas: [input, tests]
---
# A matrix row for an edge action failed on its second binding only

2026-11-02

- **Saw:** adding `ping` to Deadnight's input matrix (#642) passed for the first key and failed for the next
  ("keyboard/mouse: ping never reached the night's command"), though both bindings are in the map and the night marks a
  place from either.
- **Cause:** the night reads the ping key as its own edge (`HumanController.ping_pressed`, once a tick beside
  `command`), and the matrix called `command()` every tick but `ping_pressed()` only on the ticks it asserted. The
  controller keeps the last state of the key (`_was_down`), so the first binding's release was never seen, the key still
  counted as down, and the second binding's press made no rising edge. An action that is a level (fire) hides this; an
  edge does not.
- **Fix:** one helper reads every per-tick input the way the night does (`_tick_command`: the command and the ping
  edge), used for the held ticks and the let-go ticks alike, so the controller sees every release.
- **General:** a test that stands in for a loop reads each edge source on every tick of it, not only when it asserts; a
  new edge action's row is run through two bindings in a row before it is trusted.
- **Docs:** Deadnight `docs/research/input-tests.md`; the double-read side of the same trap is
  [a test read the controller twice](2026-11-02-a-test-read-the-controller-twice-and-lost-the-press.md).
