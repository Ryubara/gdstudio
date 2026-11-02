---
areas: [audio, tests]
---
# Close 3D sounds all played at the ceiling whatever their trim

2026-11-01

- **Saw:** a mix capture of gunfire clipped (0 dBFS, thousands of clipped samples) after cutting every gun's `volume_db`
  by 8 dB, and cutting again changed little; a lone shotgun at -23 dB peaked at -5 dBFS.
- **Cause:** `AudioStreamPlayer3D` boosts a sound by `unit_size / distance` as it comes close, up to `max_db` (+3 dB over
  the file by default) after the trim is added, so any sound inside a few metres sits at the ceiling and the trim does
  nothing; three layers at +3 dB sum past full scale.
- **Fix:** a per-sound `near_cap_db` sets the player's `max_db` to its own `volume_db + near_cap_db` (0): up close the
  sound is as loud as its trim says, far away the attenuation is unchanged. Loops that move their level move `max_db`
  with it. Checked with a capture that plays each gun by itself at 1.7 m at several offsets.
- **Docs:** [Audio](../godot/audio.md).
