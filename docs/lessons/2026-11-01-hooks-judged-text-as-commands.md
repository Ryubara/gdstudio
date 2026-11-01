# Hooks judged text as commands

2026-11-01

- **Saw:** the hooks refused harmless commands: a Python heredoc line starting `blender = ...`, and a `grep -E "a|godot"`.
- **Cause:** the guard split shell lines on `|` inside quotes and read heredoc bodies as commands.
- **Fix:** split only outside quotes; drop heredoc and here-string bodies before judging.
- **Docs:** Hooks (`docs/hooks.md`).
