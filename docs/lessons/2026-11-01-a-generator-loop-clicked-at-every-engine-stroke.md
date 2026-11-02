---
areas: [tools, audio]
---
# A looped synthesised hum had a click at every stroke

2026-11-01

- **Saw:** The loop's last and first samples differed by 0.1 of full scale, a click the spectrogram showed as a vertical
  line.
- **Cause:** The engine-stroke envelope `exp(-phase * k)` jumps from near zero back to one at each stroke start, a step;
  the seam of a 2 s loop is one of those steps.
- **Fix:** Add a 2 ms attack to the stroke envelope. Make every component a whole number of cycles in the loop length
  (and filter noise in the frequency domain) so the loop is periodic by construction.
- **Docs:** [Audio](../godot/audio.md#making-sounds-with-code)
