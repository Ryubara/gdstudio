---
areas: [audio, godot]
---
# A Movie Maker recording mixes every bus into one track

2026-11-01

- **Saw:** the soldier voice's level had to be measured against the guns and the beds, but `--write-movie` writes one
  mixed track.
- **Cause:** Movie Maker records the master output only.
- **Fix:** put an `AudioEffectRecord` on each bus to measure (Voice, Effects, Ambience), record during the capture and
  save each stem. It works under Movie Maker; Deadnight #442 measured the voice at 4.8 LU under the guns and 10.6 LU
  over the beds that way.
- **Docs:** [Audio](../godot/audio.md#capturing-sound).
