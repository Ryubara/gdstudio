---
areas: [tests, input, web]
---
# Four phone probes went stale after the rework, because no CI runs them

2026-11-06

- **Saw:** on the combined main of Deadnight's phone rework (#1317) `touch_right_side.py` failed on a Strike button that
  held `''`, `touch_sprint.py` read 0.00 m/s for a stick that never came down (`down: false`), `night_taps.py` failed
  on the same Strike button, and `phone_layout.py` failed four floors on a tablet page. The game was right each time.
- **Cause:** CI runs no browser probe, so each pull request ran its own probes on its own base and nothing ran the rest
  after the next pull request landed. `touch_hits` lists every circle of the layout, the contextual Strike and Interact
  too, drawn or not (a probe pressing "every button" pressed one that is not there); a stick finger placed at a fixed
  spot (0.13 across, 0.74 down) was on the players' column, which a later pull request made the scoreboard's place; a
  tablet page is the desktop's layout, and the phone's floors do not apply to it.
- **Fix:** read each failure against the game first (what the page published, a screenshot of the finger down), then
  change the probe to the new fact: skip a contextual button unless `touch_strike` is true, start the stick on free
  ground, leave the tablet snaps out of the phone floors. Run the whole phone list on one export of main after a rework
  (the table in the page below), and never loosen a limit to get a pass.
- **Docs:** Deadnight `docs/research/web-smoke-probes.md`, "The phone probes, run together on one export (#1317)".
