---
areas: [tests, tools]
---
# A windowed capture in a checkout with a stale class cache never quit

2026-11-03

- **Saw:** a tour copied into another worktree for a baseline printed a screenful of `Parse Error: Could not find
  type "UseSight"` and `Identifier "DualClips" not declared`, then ran until the 20 minute timeout with no PNG. The
  next command in the same chain waited behind it.
- **Cause:** that checkout had been imported before main gained those `class_name` scripts, so its global class cache
  did not list them; headless `-s` tools worked (they load by path), the scene did not. The capture's `_ready` failed
  on a nil `Night.server` and nothing called `quit()`, so the process idled.
- **Fix:** run `godot --headless --path game --import` in a checkout before its first windowed run, and give every
  capture a watchdog (`get_tree().create_timer(60).timeout.connect(get_tree().quit)`) or a short `gds godot --timeout`;
  look at the first lines of the log within a minute, not at the end. Stop a stuck run by its PID.
- **Docs:** [no-focus](../godot/no-focus.md). Check: a windowed run that has printed no `SHOT`/frame line after a
  minute is stuck, not slow.
