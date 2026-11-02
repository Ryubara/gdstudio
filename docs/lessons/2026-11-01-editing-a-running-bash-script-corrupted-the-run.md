---
areas: [blender]
---
# Editing a running bash script corrupted the run

2026-11-01

- **Saw:** a long render batch printed `line 44: ue: command not found` after its script was edited while it ran
  (Deadnight #438).
- **Cause:** bash reads a script file as it executes it, so an edit shifts the bytes under the part not yet run.
- **Fix:** wait for the run to end, or run a copy of the script and edit the original.
- **Docs:** [Key art](../blender/key-art.md).
