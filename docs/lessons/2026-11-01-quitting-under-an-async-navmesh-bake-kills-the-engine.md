---
areas: [godot, gameplay]
---
# A headless night died at exit once a door had been bought

2026-11-01

- **Saw:** a night played headless printed its report, then `corrupted size vs. prev_size in fastbins` and a segmentation
  fault (exit 139 locally, 134 in CI), only in runs where the bot had just bought a door.
- **Cause:** a door starts `NavigationServer3D.bake_from_source_geometry_data_async`, which runs on a worker thread; the
  program quit under it. A change that shifted when the bot bought its first door only made the race show in CI's
  one-round run (the same night on the older code crashed with three rounds).
- **Fix:** before `get_tree().quit()`, wait (a bounded number of `process_frame`s, no busy loop) until the bake's owner
  says it is idle, here `DoorNavigation.is_busy()`. Bisect by turning one feature off at a time: the first suspect (a
  `Callable` into a `RefCounted`) was innocent.
- **Docs:** deadnight's `docs/research/zombies.md`, "The fence's boards".
