---
areas: [tools, godot]
---
# Killing Godot by name stopped other agents' runs

2026-11-01

- **Saw:** a benchmark loop looked stuck, with a dozen `Godot_v4.7.2-stable_win64` processes running; killing them all
  with `taskkill /IM` also ended other agents' runs on the same machine (their spikes had to be restarted). It happened
  again later the same night, to stop a single test run.
- **Cause:** every agent on the workspace shares the machine and the one pinned Godot executable, so the process
  name does not say whose process it is. The "stray" processes were other agents' runs, not leaks of mine.
- **Fix:** stop only processes you started: keep the PID of each background command, or filter by the command line
  (`Get-CimInstance Win32_Process` with the project path), never by image name. The kit's hooks now refuse a kill by
  name of a pinned tool ([Hooks](../hooks.md)). Expect timings on a shared machine to be noisy: repeat a run and
  report the spread.
- **Docs:** [Hooks](../hooks.md); [Zombie crowds](../godot/crowds.md#numbers).
