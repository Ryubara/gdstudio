---
areas: [audio, godot]
---
# A pooled 3D player kept the last sound's max_db, so a gun's trim capped the dead

2026-11-03

- **Saw:** after lowering the guns' trims 4 dB, every zombie voice, board and door in the same capture read 3.7 to 4.3 dB
  lower, and a headroom run that played each zombie voice once passed (-3.8 dBFS under the player's gun) while a run
  that played them on a fresh service peaked at 0.0 dBFS. The same zombie cell alone and after the cell with a
  teammate's guns differed by 4 to 10 dB on the same sounds (Deadnight #718).
- **Cause:** the audio service reuses its `AudioStreamPlayer3D` nodes and sets `max_db = volume_db + near_cap_db` only
  for a sound that has a near cap; a sound without one (`near_cap_db = INF`, "up to +3 dB") left the player's `max_db`
  as the last sound that used the slot had set it, here a gun's trim. Whatever played after a gun, a reload step or
  an impact in the same slot was capped at that trim, so the dead's level depended on the pool's history and moved
  when a gun trim did.
- **Fix:** every pooled property that a play may set is set on every play (here `max_db`, back to the engine default
  when the sound has no cap), with a test that plays a capped sound and then an uncapped one on one slot. It changes the
  dead's loudness (their warm-pool level was the quiet one), so it is a mix decision and its own issue (Deadnight
  #752), not part of the headroom change. Found by comparing a cell played alone with the same cell played after
  others, which is the check for any pooled node.
- **Docs:** [Audio](../engines/godot/audio.md#headroom-without-a-limiter).
