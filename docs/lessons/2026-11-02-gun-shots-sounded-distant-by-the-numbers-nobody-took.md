---
areas: [audio, gameplay]
---
# A close, powerful sound needs its first 50 ms, its low end and its level measured, not only its peak

2026-11-02

- **Saw:** the maintainer, playing: the tommy gun sounded distant, its pitch was uneven, every gun should be
  louder and more powerful (Deadnight #407). No clipping anywhere, every file normalised.
- **Cause:** recorded through the real service, the tommy gun had a third of its energy in the first 50 ms (a
  generated blast with a baked-in room and a tail made the rest), nothing under 120 Hz, a -6 dB trim and a -10.6 dBFS
  mix peak; the shooter's own shot was a centred 3D voice (6 dB under a flat one); pitch was shifted by up to 0.8
  semitones per layer on top of variants whose thump moved 10 percent (a 3.4 semitone spread across a burst). 3D
  attenuation, low-pass and bus effects were not it.
- **Fix:** one close report (click, crack, roar, bark, thump) and a short quiet tail; own shots flat; one pitch rule
  (0.15 semitones) and one level rule (0.5 dB) for every firearm voice; trims with real headroom (no limiter: the web
  build ignores bus effects); a test of the rules and of a measured loudness table against the night's beds;
  `tools/audio/gun_levels.py` and a bench scene that measure it, natively and in the browser (Deadnight #455).
- **Related:** [Close 3D sounds all play at the ceiling](2026-11-01-close-3d-sounds-all-play-at-the-ceiling.md): the
  same general cause, a mix tuned by peak and per-file level instead of by what reaches the player's ears.
- **Docs:** [Audio](../engines/godot/audio.md#close-and-powerful-sounds).
