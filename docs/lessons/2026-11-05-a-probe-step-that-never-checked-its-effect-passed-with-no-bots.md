---
areas: [tests, web]
---
# A web probe's "set seven bots" step changed nothing and the run still passed on a night with none

2026-11-05

- **Saw:** the real-night probe for the round card (Deadnight #1305) tapped the Play screen's Bots arrow seven times
  at an interface size of 1.25 on a 667 x 375 CSS px page and went on to a night that "passed" every check: the
  round card was one row high, the column under the objective. The night had one person and no bots, a 66 unit
  column, so the busiest case was never on screen. Only reading `result.json` (`"bots": 0, "players": 1`) showed it.
- **Cause:** at 1.25 the Play panel is wider than a 667 px page (the probe's `spots` put Back at 1.08 of the width and
  the Bots arrow under the footer), so the taps landed on nothing, and nothing is logged for a tap that hits nothing.
  The script compared the HUD's cards and never the precondition it had asked for. The existing 844 px touch probe
  (`solo_settings.py`) taps the same arrow because its page is wide enough.
- **Fix:** a probe step that sets a precondition reads the precondition back and fails on a difference (the night
  must seat the bots asked for: `bots`, `players`), and a control that a tap cannot reach is walked to with the keys
  the page also takes (`smoke.focus_control` and `smoke.step_value` on the Bots row). Check for next time: open the
  `result.json` of a first run and read the numbers that define the case before reading the checks.
- **Docs:** [Web export](../godot/web-export.md).
