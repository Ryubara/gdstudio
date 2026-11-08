---
areas: [audio]
---
# A capture of the second map's night carried the lot's crickets and highway

2026-11-03

- **Saw:** the first runs of a capture meant to measure the second map's wind (Deadnight #809) started the night's
  beds the way `NightSounds` does, the crickets and the highway, under the map's own sound. They were read, the swell
  looked small (0.1 to 0.2 LU on the bus through a boarded window), and the runs were stopped before the numbers were
  used: the map's design says its sound starts **in place of** those two beds (the yard is frosted and still), so the
  quiet the loops play in was never the quiet that was measured.
- **Cause:** the capture was copied from the drive-in's wind capture, which has those beds, and its beds were taken
  for "the night's beds" without asking which beds the map under test plays.
- **Fix:** the capture starts only what the map starts (its room tone, roof wind, yard and the night's wind); `--beds`
  adds the lot's two for the louder case. All six runs were done again.
- **Check:** before measuring a thing in a place, list what plays in that place from the place's own design page, and
  start exactly that; a bed judged against the quiet it plays in (the cricket corrections of 2026-11-03) is judged
  against that place's quiet, not the first map's.
- **Docs:** [Swelling a bed with an event](../engines/godot/audio.md#swelling-a-bed-with-an-event).
