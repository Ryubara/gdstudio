---
areas: [tests, audio]
---
# A GdUnit4 run printed leaks at exit that no test reported

2026-11-01

- **Saw:** after the results, `WARNING: N ObjectDB instances were leaked at exit` and `ERROR: N resources still in use
  at exit`, with every test passing, so nothing failed and nobody looked.
- **Cause:** the lines belong to whichever suite left something alive: a test lambda that held itself through an array
  (`chain[0] = func ...`, a cycle that keeps the test script in use), and nights whose ambience beds only fade out when
  the night is freed, so their streams were playing at quit. A whole-run log does not say which suite; running the
  folders one at a time with `--verbose` names the stream or script.
- **Fix:** cut the cycle at the end of the test; stop the audio after each test that builds a night and wait
  `Audio.wait_for_mixer()` once; CI greps the test log for `leaked at exit|still in use` like the night step
  (Deadnight #378).
- **Docs:** [Audio](../godot/audio.md#leaks-at-exit-in-a-test-run); related: [a lambda
  cycle](2026-11-01-refcounted-lambda-cycle-leaks-at-exit.md) and [quitting right after stopping a
  sound](2026-11-01-quitting-right-after-stopping-a-sound-leaks-its-stream.md).
