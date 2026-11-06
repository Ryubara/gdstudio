---
areas: [tests, input, web]
---
# Two phone probes waited on the wrong page, and a drag began before the touch layer was up

2026-11-06

- **Saw:** on Deadnight's main `touch_melee.py` failed with "the bench never got ready: {}" after 240 s, and
  `touch_assist.py`'s `off` run turned the view 0.087 rad in three drag steps and then not at all while the finger kept
  moving. Neither had been looked at; the guess was "stale for the new Strike button" for the first and "a game fault in
  the look" for the second.
- **Cause:** neither. (1) `touch_assist.export_bench(godot, work, scene=BENCH_SCENE)` bound its default when the
  function was defined, so a probe that set `touch_assist.BENCH_SCENE = ...` afterwards (`touch_melee.py`,
  `bot_wheel.py`) exported the assist bench and waited for a `window.__melee` that page never publishes; the bench itself
  was fine (a page of its own got ready in 42 s). (2) The bench called the night "ready" while the helicopter drop still
  played: the touch layer is down for the show (`TouchControls.live`), the finger landed on a layer that was not up, the
  browser's emulated mouse turned the view for two moves, and when the show ended 0.3 s later the layer owned no finger
  that had not landed on it, so every later drag turned nothing. A page that asks for the probes should skip the show
  (`WebProbe.asked`), and here it played anyway. The layer is right: `test_touch_slow_drag.gd` drags at the probe's pace
  and no move is lost. The first fix of the melee bench also showed the next layer: one blow killed the held zombie, the
  Strike button (which shows only with a living dead in reach) went, and the taps "inside the cooldown" pressed free
  ground, so the probe would have passed without testing the cooldown.
- **Fix:** read the failure against the page before the game: print what the page published (`window.__*` keys), and
  trace the state each step (`active`, `live`, the finger's role), as a debug script on the same export. Then make the
  bench ready only when it can be driven (the layer is up and the Strike button shows), pass a scene by argument or read
  the module variable at call time, make the probe fail on its own reason (the layer took no look finger; Strike was not
  up for a tap; the page published another bench's names), and keep the held zombie alive so every tap has a target.
- **Docs:** Deadnight `docs/research/aim-assist.md` ("In a browser") and `docs/research/web-smoke-probes.md`.
