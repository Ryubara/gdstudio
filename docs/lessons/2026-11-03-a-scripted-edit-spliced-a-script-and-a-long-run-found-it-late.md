---
areas: [tests, process]
---
# A scripted edit duplicated half of a script and two long runs failed to start

2026-11-03

- **Saw:** two soak runs of ten minutes each printed `Could not resolve class "SoakWatch", because of a parser error`
  and nothing else; the output was only read when the runs ended.
- **Cause:** a Python one-off cut a function body between two `index()` calls on markers, and the first marker also
  occurred earlier in the file, so the slice `s[:a] + new + s[b:]` had `b < a` and copied half the file twice.
- **Fix:** rewrote the splice from the intact copy. After any scripted edit of a `.gd` file, run `gdformat` on it (it
  parses) before starting a run that takes minutes, and start such runs with a first look at their log after ten
  seconds, not at the end.
- **Docs:** [Headless probes](../engines/godot/headless-probes.md) (every run gets a timeout and a look at its first seconds).
