---
areas: [tests, web, godot-ui]
---
# A web probe walked the focus by counting key presses and a parallel pull request added a control

2026-11-03

- **Saw:** Deadnight #730 went red on the `web` job after main moved: "the night did not seat 3 bots: ['0']", the
  probe's twelve reads all `bots: 0`. The same probe was green on the branch before the merge.
- **Cause:** the probe pressed Up once from Start and Right three times, taking the first Up to be the Bots row. #715
  put the bot skill selector under the count in that row and made it the panel's last control, so the Rights changed
  the skill and left the count at 0. Nothing in the probe named the control it expected to be on.
- **Fix:** one more Up and one more Down (`camera_owner.py`, `solo_settings.py`). Reproduced first: the old script on a
  fresh web export reads 0 bots twelve times, the fixed one reads 3 and the frame lists three bots. A probe that
  walks the focus reads which control has it (the game's `play_focus` field) before it presses a value key.
- **Docs:** Deadnight `docs/research/bots.md`. Check: after a pull request that adds a control to a screen, grep
  `tools/web_smoke` for the key walks of that screen (`ArrowUp`, `ArrowDown`) and run the probe before opening.
