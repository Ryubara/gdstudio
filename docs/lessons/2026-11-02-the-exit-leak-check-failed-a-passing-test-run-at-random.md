# The exit leak check failed a passing test run, at random

2026-11-02

- **Saw:** CI's `leaked at exit|still in use` grep failed whole runs with every test green (4 objects and 2
  resources; 8 and 2; 1 object), on main and on pull requests, and passed on the next run of the same code. It held
  the merge queue for hours, and people rerun until green and learn to ignore it.
- **Cause:** what is playing, or was stopped a moment ago, when the process quits is still held by the audio server
  until its mixer thread has taken a few steps. One Ogg voice is exactly 4 instances (stream, packet sequence, two
  playbacks) and 2 resources (stream, sequence), which is how the CI counts read. GdUnit quits by itself after the
  last suite, so no suite can wait for the mixer there; whether a voice is in flight at that moment, and whether the
  mixer has stepped since, is a coin flip that load tilts.
- **Find it:** a log without `--verbose` says only counts. Run the engine with `--verbose` (CI: the night and test
  steps, then `grep -E "leaked at exit|still in use|Leaked instance|Resource still in use"` into an uploaded
  `leaks.txt`) and it names every instance and resource. Reproduce without a full run: a ten-line `-s` script that
  starts a sound through the audio autoload and calls `quit()` leaked on every run, with and without `stop_all()`
  first, so the race is "quit before the mixer stepped", not something odd in a suite. A bare `RefCounted` in the
  dump is a script class (the dump prints the native class); it is a different leak, not audio.
- **Fix:** at the source, in the audio autoload's `_exit_tree`: wait for the mixer's own steps (poll
  `AudioServer.get_time_since_last_mix()`, count each fall, about four, with a poll cap), blocking the main thread,
  which is safe because the mixer runs on its own. Only the autoload waits (a service a test frees mid-run would add a
  wait to every test). A test runs a child Godot that starts sounds and quits at once and fails on any leak line: it
  failed before the fix every time and passes after. The grep stays as it was: it is right, and loosening it hides
  the next real leak. A rarer leak of one `RefCounted` (count 0) remained after this fix, open as Deadnight #538.
- **Docs:** [Audio](../godot/audio.md#leaks-at-exit-in-a-test-run); Deadnight `docs/research/audio.md` (#487, #513).
