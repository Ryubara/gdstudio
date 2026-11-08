---
areas: [audio, general]
---
# A bench run measured a bank I had not finished writing

2026-11-03

- **Saw:** the first full bench run of the new guns (Deadnight #790) had to be killed twice: once because it wrote a
  PNG for every frame (a 100 s bench is 6000 files; the bench's own header said `--write-movie out.png`), once because
  the tails of the fast guns had no cooldown yet, so a burst stacked a tail on every shot and the numbers described
  another game.
- **Cause:** the bank was written from a script that I changed after the run started, and the usage line in the bench
  predates the `.avi` advice of `docs/engines/godot/audio.md`.
- **Fix:** write the bank, the table rows and the tests first, run the bench once, and start it with
  `--write-movie <abs>/x.avi` and `ffmpeg -vn -c:a pcm_s32le`; the bench's header says so now. Stop a stale run by its
  PIDs (`Get-CimInstance Win32_Process` on the scene's name), not by name.
- **Docs:** [audio](../engines/godot/audio.md), Deadnight `game/tools/bench/audio_gun_bench.gd`.
