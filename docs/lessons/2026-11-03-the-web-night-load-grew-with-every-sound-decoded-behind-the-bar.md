---
areas: [web, audio, ci]
---
# The web night load grew with every sound decoded behind the loading bar

2026-11-03

- **Saw:** the `web` job failed four times in one day on `[loading] the night took 75 to 89 s` (limit 72 s), on pull
  requests that touched bots, glow panes and weapon models: none of them loaded anything new (Deadnight #828).
- **Cause:** two things. The runner pool: 28 runs of one day took 25 to 75 s for much the same build, and the 36 s
  baseline (limit 72 s) was the mean of a good morning. And the content: the loading bar read every sound file and
  decoded every short one to samples (a GDScript loop, one pass per sample), 166 s of sound at the cut (#509) and 297 s
  now (seven firearms, the energy weapons, a second soldier's voice lines), played or not. A browser A/B on a shared
  machine could not tell the two apart by total seconds (20 s of noise), only by the step.
- **Fix:** a `SoundBank` can be `deferred`: the bar only queues its files and the service reads and decodes them a few
  ms a frame while the night runs (a sound played first goes to the front). Weapons' and voices' banks are deferred, and
  a test caps the seconds decoded behind the bar, so a new weapon's sounds must go in a deferred bank.
- **Docs:** Deadnight `docs/research/web-export.md`, "Loading a night". Check: a new family of sounds (a weapon, a
  voice, a map's set) goes in a bank with `deferred = true`; compare web load times as a ratio to the same run's time to
  the menu, or interleaved in one session, never as seconds across runs of a shared runner.
