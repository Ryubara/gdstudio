---
areas: [tests, ci]
---
# A test that only named a script failed its shard on the leak gate while Godot exited 0

2026-11-04

- **Saw:** a CI shard (Deadnight #1100, `godot (2)`) exited 1 with no test FAILED. Its log ended with
  `ObjectDB instances were leaked at exit` and hundreds of `Resource still in use` lines; run locally, the same shard
  printed the same lines and exited 0.
- **Cause:** the shard's last line is `! grep -E "leaked at exit|still in use" tests.log`, so those lines fail it, not
  Godot's exit code. One test only named a script (`WarmupManifest`, which loads `PlayerAnimation` and the scripts under
  it), and a test with no night left them in use at exit. I had read those lines in my own log and called them usual.
- **Fix:** bisect with a prefix of the test file, then one line at a time; the test now reads the script's source
  instead of loading it. Run the shard's own command, then CI's gate grep, before pushing a new test: the count of
  matching lines is 0, whatever the exit code.
- **Docs:** [the hand-over lesson](2026-11-04-a-hand-over-was-green-only-where-it-had-run.md) carries the check.
