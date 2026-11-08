---
areas: [godot-ui, tests]
---
# A new match setting took a sixth row and a selector label too wide for its cell

2026-11-03

- **Saw:** the perk limit (Deadnight #913) was first a row of its own on the Play screen and the lobby: the 720p fit
  test and the phone-height test failed (the panel ran 1 unit past 720 and needed more than the phone's 540). Paired
  with the intensity in one row, its label "Unlimited perks" was clipped under the selector's arrows in the capture
  while every headless test passed.
- **Cause:** the panel is full (a lesson and a code comment in `MatchSettingsPanel` already say a sixth row does not
  fit); a selector cell is about 146 px wide and a headless run measures text as nothing, so only a capture shows a
  label that does not fit.
- **Fix:** a setting that is one choice of two or three shares an existing row (`bots` and `bot_skill`, now
  `count_multiplier` and `perk_limit`), with one-word labels (`Default`, `Unlimited`) and the row's hint saying what
  they are; look at the 1280x720 and 1168x540 captures before the first push. Read `gds lessons godot-ui` before
  adding a control to a settings form.
- **Docs:** [two option selectors in one row](../engines/godot/ui-controls.md#two-option-selectors-in-one-row).
