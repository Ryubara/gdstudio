---
areas: [tests, godot, tools]
---
# A capture awaited a signal its own call had already emitted, and recorded 3000 frames of nothing

2026-11-05

- **Saw:** Deadnight #1278's capture printed `arriving true` and then recorded until `--quit-after` ended it: 3000 frames
  of a night that never began, enough to fill the disk.
- **Cause:** the script called `arrival_show.skip_now()` and then `await night.arrival_ended`. `skip_now` ends the show
  inside the call and `arrival_ended` is emitted from there, so the await began after the signal and waited for ever.
  Movie Maker recorded every frame of the wait.
- **Fix:** do not await a signal after the call that emits it (check the state, `is_arriving()`, or connect before the
  call); every capture script has its own hard stop in frames (a counter in `_process` that quits) besides
  `--quit-after`, and every wait loop a bound. Run a new capture with a small `--quit-after` first, and delete the
  frames as soon as the sheet or clip is made.
- **Docs:** the mistakes glossary (`gds lessons <area>`), areas `tests`, `godot`.
