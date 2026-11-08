---
areas: [tests, tools]
---
# Merging main into a worktree while its soak ran broke the soak's later chunks

2026-11-03

- **Saw:** a parity soak started from the game worktree reported two cells with a median round of 1 and a Kolmogorov
  distance of 1.00; the log held `Identifier "BotHunt" not declared in the current scope` and `Failed to compile
  depended scripts` for every chunk started after the merge.
- **Cause:** `gds merge-main` (run for a pull request) pulled in a new `class_name` (`BotHunt`) while chunks were still
  being started from the same folder; the global class cache is only rebuilt by an import, so every script that named it
  failed to compile, and the soak counted a crashed night as round 1.
- **Fix:** run a long soak from its own checkout (a detached worktree of the commit under test), never the worktree that
  is being merged or edited; after a merge run `godot --headless --path game --import` before any test, and read a median
  of 1 as a crashed run, not a result.
- **Docs:** [Probes and tools in headless Godot](../engines/godot/headless-probes.md).
