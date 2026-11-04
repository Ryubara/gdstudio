---
areas: [ci, tests, godot]
---
# Dev scripts in a scanned test folder leaked at exit on some CI runners only

2026-11-04

- **Saw:** Deadnight #1014. Shard 5 failed three unrelated pull requests with every test green and `1216 ObjectDB
  instances were leaked at exit`, `154 ... DummyTexture`, `49 ... ShapedTextDataAdvanced` and `384 resources still in
  use` (fonts, textures, audio banks, hundreds of scripts). Main's shard 5 was clean, as were most runs of the same
  code; the suspects named in the issue (the newest UI suites) were not even in the failing runs.
- **Cause:** only runs on Amazon EC2 runners failed (3 of 3; none of about 60 on Azure). The folder scan opens every
  script in `tests/art`, in the filesystem's order, and `solve_grips.gd` (a `-s` dev tool with no `class_name`) was
  loaded first there; loading it left four scripts in use at exit and, through their statics, the rest. Loaded alone,
  by a ten-line probe, it leaks 12 objects on Linux and none on Windows; four more dev scripts under `tests/` did the
  same.
- **Find it:** the logs gave no suite. What worked: a temporary workflow that exits early on Azure (the machine type
  differs by the DMI vendor), and on the others runs each folder alone, then removes files of the leaking folder while
  the leak stays (the minimal set: the muzzle suite plus three art helpers), then a local `load()` probe under WSL
  with the pinned Linux Godot. Local runs of the exact failing suite order, on Windows and on Linux limited to four
  cores, never reproduced it; they passed the suites as file arguments, while the runner scanned folders, so the scan
  (which loaded the dev tool first) was the variable, not the hardware or the suite order.
- **Fix:** the five scripts moved to `game/tools/` (not scanned); the sharding change that hands GdUnit script paths
  (Deadnight #1018) removes the scan altogether.
- **Check for next time:** a script under `tests/` that is not a suite does not belong to a test run. Before blaming
  the newest suite for a leak that comes and goes between runs, compare the passing and failing logs' runner (`Cloud:`
  in the job's setup log) and the order of their `Run Test Suite` lines.
- **Docs:** [Leaks at exit in a GdUnit run](../godot/test-exit-leaks.md); related: [a capture script's preload kept
  the lot scene alive](2026-11-03-a-capture-script-preload-kept-the-lot-scene-alive-at-exit.md).
