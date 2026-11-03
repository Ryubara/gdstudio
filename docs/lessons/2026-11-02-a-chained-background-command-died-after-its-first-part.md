---
areas: [tools, process]
---
# A chain of batches started with `( a; b ) &` in a background command stopped after the first

2026-11-02

- **Saw:** `(./batch.sh off ...; ./batch.sh on ...; echo done > ab.done) &` inside a `run_in_background` Bash call was
  reported "completed" at once. The first batch ran, the second never started, `ab.done` never appeared, and the
  waiting monitors and `sleep` loops ended without the result (one exit 2, from an `ls` of the missing file).
- **Cause:** The tool tracks the foreground command, not the subshell the `&` detached; the detached chain was cut
  with it, and every wait on a marker file looked like progress.
- **Fix:** Run each long step as its own `run_in_background` command with no inner `&` (a script that waits for its own
  children), end it with `echo done > marker`, and check the logs of the second step exist before waiting for it.
- **Docs:** none yet; the shared-machine rules in the Godot engineer agent say "start a background command that
  notifies you when it ends".
