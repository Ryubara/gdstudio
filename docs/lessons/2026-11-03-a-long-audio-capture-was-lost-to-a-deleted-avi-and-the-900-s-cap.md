---
areas: [audio, tools]
---
# A long audio capture was lost to a deleted .avi and the 900 s cap

2026-11-03

- **Saw:** a Movie Maker run of 30 cells (five minutes of sound) was stopped by `gds godot` ("did not finish within 900
  s") and left no `.wav`; the next three runs finished and my script then deleted `mix.avi` to save disk, and there was
  no `mix.wav` beside it (Deadnight #718, 40 minutes lost).
- **Cause:** `--write-movie x.avi` puts the audio inside the avi (only `x.png` writes a `.wav` file beside the frames),
  and the wav is finished only when the run ends; `gds godot` stops a run at 900 s and an avi encodes at about 15 ms a
  frame, so 18 000 frames do not fit.
- **Fix:** split a long capture into runs of a few minutes of sound (one per case, three at a time), extract the track
  at once (`ffmpeg -i x.avi -vn -c:a pcm_s32le x.wav`) and delete the avi only after the wav exists.
- **Docs:** [Audio](../engines/godot/audio.md#capturing-sound).
