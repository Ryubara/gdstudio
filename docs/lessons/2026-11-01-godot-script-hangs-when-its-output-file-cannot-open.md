# A headless Godot script idled at full CPU when its output file could not be opened

2026-11-01

- **Saw:** `godot --headless -s tool.gd -- --out=cell.json` never exited; nine of them were left running after a report
  script passed a relative `--out`. The log showed `Cannot call method 'store_string' on a null value`.
- **Cause:** `--path` starts the run inside the project, so a relative path resolves there (or nowhere);
  `FileAccess.open` returned null, the script errored before `quit()`, and a `SceneTree` script that never quits keeps
  the engine looping.
- **Fix:** check `FileAccess.open` for null, `push_error` and `quit(1)`; resolve relative paths against the caller's
  directory (the `PWD` environment variable) or have the launcher pass an absolute path.
- **Same hang, parse error (Deadnight #460):** `godot --headless -s res://tool.gd` printed
  `SCRIPT ERROR: Parse Error` and sat idle until the 30-minute timeout: a SceneTree script that fails to compile
  never reaches `quit()` either. Give every headless tool run a short timeout and look for `SCRIPT ERROR` in the
  first seconds (or run `--check-only` first); `:=` from a Dictionary value is a warning treated as an error in
  projects that turn warnings up.
- **Docs:** none yet; the pattern is in the deadnight `tools/balance/balance_cli.gd`.
