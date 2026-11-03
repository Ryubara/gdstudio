---
areas: [tests, web, godot-ui]
---
# A web probe that walks by control name found two more places where counting had broken

2026-11-03

- **Saw:** moving Deadnight's Play-screen smokes (#743) from counted key presses to "press until the focused control is
  `bots`" failed twice on a build where the count-based fix of #741 was green. The keyboard walk reached `bot_skill`
  and never `bots` going Down, and the touch run of `solo_settings.py` (and `lobby_bots.py`) read 0 bots after three
  taps.
- **Cause:** (1) Down from the break slider lands on the skill selector, the nearer of the two that share the Bots
  row; only Up from the skill reaches the count. (2) the probe's tap spot `bots:end` was the end of the row's control,
  which became the pair of selectors, so each "next arrow" tap hit the skill (three taps wrapped it back to Regular).
  The controls also had no names (`@UIOptionSelector@12`), so the published focus could not say where it was.
- **Fix:** name every control of a settings panel by its setting key and publish the nearest named focus owner; the
  smoke's `focus_control(page, name, key)` presses with a bound and fails naming the wanted control, the reached one
  and the controls passed; the probe's spots look the control up by the same name. Walk the order the focus links
  allow (up from Start), not the visual order.
- **Docs:** Deadnight `docs/research/web-smoke-probes.md`. Check: a probe that taps or walks a control uses the name the
  game publishes for that control, and a name that two controls share (one row, two selectors) is a bug in the probe's
  data, not in the tap.
