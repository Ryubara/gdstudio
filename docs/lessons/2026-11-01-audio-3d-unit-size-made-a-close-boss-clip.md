# A boss with a large unit_size clipped the mix at close range

2026-11-01

- **Saw:** a capture of a horde and a boss reached 0 dBFS with 268 clipped samples, only while the boss roared three
  metres from the listener; the same sound normalised to -2 dB in its file.
- **Cause:** `AudioStreamPlayer3D`'s inverse attenuation is `unit_size / distance`, which is above 1 inside
  `unit_size`: `unit_size` 14 at 3 m is +13 dB, held only by `max_db` (3 dB). A big `unit_size` for a big monster
  makes it loud up close, not "large".
- **Fix:** `unit_size` 7 and the roar and growl trimmed 6 to 7 dB in the catalog; the capture then peaked at -0.4 dBFS
  with no clipped sample. Find it with a per-second peak and clip count of the mix, not the file's peak.
- **Docs:** [A crowd's voices](../godot/audio.md#a-crowds-voices-the-dead).
