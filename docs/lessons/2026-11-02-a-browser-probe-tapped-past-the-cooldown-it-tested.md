---
areas: [input, web]
---
# A browser probe tapped past the cooldown it tested

2026-11-02

- **Saw:** a probe that tapped the touch MELEE button three times "inside the 0.6 s cooldown" counted 2 blows, and a
  fourth tap after it made 3, in both hands. It looked like a tap being queued during the cooldown.
- **Cause:** the probe, not the game. Each tap through the DevTools protocol (touch start, hold, touch end, sleep)
  cost about 230 ms of real time, so the third tap started 781 ms after the first. Logging the page's
  `performance.now()` at every touch start and at every blow showed the second blow 54 ms after that third tap, and
  the server clock 0.766 s after the first blow: the cooldown had run out, and nothing had been queued.
- **Fix:** a probe that tests a window stamps its taps with the page's clock (`stamp()` in
  `tools/web_smoke/touch_melee.py`), keeps the gaps short, and fails when the last tap meant to be inside the window
  started outside it. The bench publishes each blow with the same clock to line them up.
- **Docs:** [touch controls](https://github.com/Ryubara/deadnight/blob/main/docs/design/touch-controls.md), the
  deadnight pull request for #588.
