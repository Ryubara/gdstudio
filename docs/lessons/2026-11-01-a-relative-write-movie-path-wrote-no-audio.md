---
areas: [audio, tests]
---
# A relative --write-movie path recorded frames to the wrong place and no audio

2026-11-01

- **Saw:** Hundreds of `ERROR: Condition "f_wav.is_null()" is true. Returning: ERR_UNCONFIGURED` at
  `movie_writer_pngwav.cpp:145`, and no `.wav`; the output folder stayed empty.
- **Cause:** The path was relative to the project folder (`--path game`), not the shell's: `../scratch/...` resolved to
  a folder that did not exist, and the writer does not create folders.
- **Fix:** Pass an absolute path to a folder that already exists. Smoke the capture with `--quit-after 25` first: a run
  with script errors still records every frame (a 1500-frame run took 100 s and recorded nothing useful).
- **Docs:** [Audio](../godot/audio.md#capturing-sound)
