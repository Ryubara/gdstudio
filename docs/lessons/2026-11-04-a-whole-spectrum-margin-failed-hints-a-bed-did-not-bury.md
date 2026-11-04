---
areas: [audio]
---
# A margin over the whole spectrum failed hints that a menu bed did not bury

2026-11-04

- **Saw:** the first speaker check of the menu's ambience bed gave the quieter "Coming" hints 1.0 and 1.6 dB over the
  bed (gate 3) on a flat speaker. The bed was a low motor and
  quiet crickets; the hints are a 2.5 kHz ring and a 3.5 to 6.5 kHz click.
- **Cause:** the second margin compared the hint's loudest 50 ms with the bed's loud 50 ms in K-weighted loudness over
  the whole spectrum, so the motor (under 300 Hz, the loudest part of the bed) counted against a hint it cannot mask.
- **Fix:** the second margin is read in the hints' own band (1.5 to 8 kHz): the hint's loudest 50 ms rms over the bed's
  95th percentile 50 ms rms in that band, gate 6 dB; the first margin (hint peak over the bed's loudest 400 ms) stays
  as the kit's rule. Both are in `tools/audio/menu_speakers.py` and pinned by `test_menu_bed_levels.gd`.
- **Docs:** [Menu and interface sounds, level](../audio/ui-sounds.md#4-level-the-bus-and-the-mix).
