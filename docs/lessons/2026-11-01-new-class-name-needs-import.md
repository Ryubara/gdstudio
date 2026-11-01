# A new `class_name` is unknown to headless runs until an import

- **Saw:** a GdUnit4 run (or any headless script run) of code using a freshly added `class_name` printed `Could not find
  type "ZombieState" in the current scope`, then `Failed to compile depended scripts` for every suite. A `SceneTree`
  script run with `godot --headless -s` printed `Identifier "TuningOverrides" not declared in the current scope`.
- **Cause:** the global class list (`.godot/global_script_class_cache.cfg`) is only rebuilt by the editor or an import;
  a headless run, `-s` included, reads the stale cache and does not scan for new scripts.
- **Fix:** run `godot --headless --path game --import` after adding or renaming a `class_name` script, then the tests.
  CI imports first; a report script that launches Godot should do the same.
- **Docs:** Deadnight `docs/research/rules-engine.md`.
