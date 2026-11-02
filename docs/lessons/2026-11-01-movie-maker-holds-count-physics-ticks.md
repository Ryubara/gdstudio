---
areas: [godot, tests]
---
# A capture scene's waits were ten times too short in Movie Maker

2026-11-01

- **Saw:** a capture script that waits `await get_tree().physics_frame` 150 times to film a 2.5 second action ended
  after 25 frames of a `--fixed-fps 10` movie.
- **Cause:** Movie Maker renders one image per `1 / fixed-fps` seconds, but the physics step stays 60 a second, so six
  physics frames pass between two images. Waits counted in physics frames are 60 a second, not 10.
- **Fix:** count waits in physics ticks and size `--quit-after` (which counts rendered frames) as ticks / 6. A look at
  the frames of the capture itself shows when the sequence is cut short.
- **Docs:** [greybox and captures](https://github.com/Ryubara/deadnight) in Deadnight's research; the kit's
  [Godot docs hub](../godot/index.md).
