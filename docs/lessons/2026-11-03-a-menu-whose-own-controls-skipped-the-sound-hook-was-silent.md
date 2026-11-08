---
areas: [audio, godot-ui]
---
# A menu whose own controls skipped the sound hook was silent

2026-11-03

- **Saw:** a walk over Deadnight's main menu made 2 sounds in its first 26 seconds (the tab bar, the tickets, the
  chips and the map cards made none), while the Settings screen clicked on every hover and ticked 37 times under one
  slider drag.
- **Cause:** sound lived in the controls. The addon's controls called `UIAudio`, and the game's own drawn controls
  (plain `Button`s) never did; no table said what each control plays, so nothing found a control with no sound, and
  nothing capped the ones that had it.
- **Fix:** the cue carries its source (`UIAudio.play(cue, source)`); a role per kind of control and one table of role
  and cue to sound, trim, weight or a written silence; one service with the rules; a test that walks every screen and
  fails on a control with no role or a role with no row, one that sends each control its events, and one that reads
  the code for a cue with no source.
- **Docs:** [Menu and interface sounds](../gamedev/audio/ui-sounds.md#7-how-to-wire-it-roles-cues-and-one-table).
