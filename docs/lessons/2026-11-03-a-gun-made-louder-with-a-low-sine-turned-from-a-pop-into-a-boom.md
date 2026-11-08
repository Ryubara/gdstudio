---
areas: [audio]
---
# A gun made louder with a low sine turned from a pop into a boom

2026-11-03

- **Saw:** the first reshape of the flare gun's report (Deadnight #761) met the burst and peak numbers offline, but its
  energy under 250 Hz was 91 percent (the other guns 44 to 69) and its centroid fell from 3000 to 2580 Hz: a boom, not
  the hollow pop the sound is meant to be.
- **Cause:** the loudness rule is met cheapest by raising the heaviest, longest component (the 65 Hz thump, 0.7 to 1.4),
  and the offline search scored loudness and peak only.
- **Fix:** the search also printed the low-end share and the centroid, and the final recipe raises the puff and the bark
  (the mids) with the thump unchanged: 63 percent, 3043 Hz. The gun bench's `low_end_share` and centroid are read beside
  the LU for any reshape.
- **Docs:** [Audio: headroom without a limiter](../engines/godot/audio.md#headroom-without-a-limiter).
