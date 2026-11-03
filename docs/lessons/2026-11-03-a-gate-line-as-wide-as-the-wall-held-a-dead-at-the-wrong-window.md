---
areas: [gameplay, tests]
---
# A gate line as wide as the wall held a dead at the wrong window

2026-11-03

- **Saw:** a night stopped closing a round on the second map: one dead left, 1.5 m outside the east wall between two
  windows, out of sight, tearing the boards of window 4 while the bot's note said `boards start_4` for eight minutes
  (mend, tear, mend). The same kind of stall was seen once on the undressed map and was never repeatable by seed
  (Deadnight #810).
- **Cause:** the sim's gate was a line across the gap with no width, so on a wall of windows it was the whole wall. A
  dead that came for window 4 whose path led along the wall to window 5 met the clamp 0.9 m short of that line, 3.6 m
  from window 4's gap, and tore window 4's boards from there. Once they were gone it crossed the infinite line, its gate
  was cleared and it walked through window 5's standing boards without touching them. The pure tests had one gate on a
  straight-line field, so no test had a second gap on the same wall or a path that did not lead straight at the gate.
- **Fix:** a gate has the width of its gap (the barricade's `board_half`): a dead is held and tears only in front of
  it, takes the gate whose gap it has come up to, and is held by none beside the wall. A pure test with two windows on
  one wall and a path along it fails on `main` (the near window's boards are torn, 10 `zombie_tore`); a probe in the
  real map shows the far window's boards, not the near one's, coming down. Rare stalls are found by comparing sets of
  nights, and understood by dropping the dead where the trace put it.
- **Docs:** Deadnight `docs/research/zombies.md`, "A dead tearing the boards of a window it was not at". Check: a
  rule that reads a line, a zone or a range in the world gets its extent from the thing it stands for (here the gap),
  and its test has two of the thing side by side.
