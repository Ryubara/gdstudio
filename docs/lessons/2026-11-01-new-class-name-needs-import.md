# A new `class_name` is unknown to headless runs until an import

- **Saw:** a GdUnit4 run (or any headless script run) of code using a freshly added `class_name` printed `Could not find
  type "ZombieState" in the current scope`, then `Failed to compile depended scripts` for every suite.
- **Cause:** the global class list (`.godot/global_script_class_cache.cfg`) is only rebuilt by the editor or an import;
  a headless run reads the stale cache.
- **Fix:** run `godot --headless --path game --import` after adding or renaming a `class_name` script, then the tests.
- **Docs:** Deadnight `docs/research/rules-engine.md`.
