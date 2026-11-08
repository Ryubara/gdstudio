---
areas: [audio]
---
# A bed cut by 25% on the meter was still too much

2026-11-03

- **Saw:** the maintainer had the crickets bed cut once (-2.5 dB for a 25% cut, Deadnight #382) and came back asking
  for them half as loud and half as frequent (#781). The proof of the first cut was a
  loudness table; the crickets already read 2.6 LU under the highway bed, so by the meter they were quiet.
- **Cause:** a percentage turned into one dB figure and checked against other beds by an integrated loudness meter, never
  against the quiet night they play in. The crickets are a narrow tone at 3.4 to 5.7 kHz and the highway has next to
  nothing there (49.5 dB less), so nothing masks them and the broadband gap says nothing about whether they stand out.
  2.5 dB is also about the smallest step an ear notices, and only the level was cut, never the chirp density (25
  chirps a second scheduled, 14 sung) that makes a tonal bed noticeable.
- **Fix:** cut both things asked (level -6 dB and half the chirps) and measure what the player hears: the bed in its own
  band against what is in that band, a capture of the quiet stretch (beds alone, rules paused) before and after, and
  the rate counted from the recipe's own plan. Two traps on the way: narrowing a random draw (`uniform(2.0, 4.2)` to
  `(1.0, 2.1)`) draws another set of insects (57% fewer chirps, not 50%), so keep the draw and drop every other chirp
  (the scale at 1.0 must render the old file bit for bit); and a loop normalised to its peak gets louder per chirp when
  fewer chirps overlap (2 dB here), so set the entry's peak to keep each chirp as it was and let `volume_db` be the cut.
- **Docs:** Deadnight `docs/research/audio.md#the-crickets-cut-again-781`; the check is in `docs/studio/maintainer-corrections.md`
  once the coordinator publishes the row.
