---
areas: [tests, godot-ui]
---
# UI suites copied into a new Godot project failed on the pad buttons, and a new helper class was not found

2026-11-07

- **Saw:** `gds_ui`'s suites, copied from Deadnight into the kit's own project, failed four checks that press Enter,
  Space and the pad's A button (`Expecting: 'true' but is 'false'`), and a helper added to the copy was "not declared in
  the current scope" in a run with no import before it.
- **Cause:** the controls act on `ui_accept` and `ui_cancel`, and the pad buttons those suites press are bound by the
  game's `project.godot` (Deadnight adds Start to accept), not by the addon. A new `class_name` is known only after an
  import has refreshed the class cache.
- **Fix:** the kit's project declares the same two actions, and its CI job and the docs run `--import` before the
  GdUnit run. When suites move to a new project, list what they read from the old one (input map, autoloads, project
  settings, helper classes) and run them once with nothing else around them: what fails names what is missing.
- **Docs:** [UI controls](../godot/ui-controls.md#where).
