---
areas: [godot, tools]
---
# A Python edit of a GDScript file made Godot refuse the script

2026-11-02

- **Saw:** `ERROR: Script 'res://gameplay/zombies/zombie_tuning.gd' contains invalid unicode (UTF-8), so it was not
  loaded`, then every class that used it failed to compile (Deadnight #415).
- **Cause:** a Python script rewrote the file with `open(path, "w")`, which on Windows writes the locale's code page
  (a `²` and a `°` in a tooltip became single Windows-1252 bytes) and `
` line ends.
- **Fix:** open with `encoding="utf-8", newline=""` (read and write), keep tooltip units ASCII (`deg`, `m/s^2`), and
  run a headless import after any scripted edit: it prints the broken file's name.
- **Docs:** [Godot index](../engines/godot/index.md).
