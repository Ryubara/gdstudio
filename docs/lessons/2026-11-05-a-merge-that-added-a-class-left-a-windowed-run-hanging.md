---
areas: [tests, process]
---
# A merge that added a class left a windowed GdUnit run hanging, and a push met a main that had moved

2026-11-05

- **Saw:** after merging main (a stick rework that added `TouchStick`), a headless suite printed `Could not find type
  "TouchStick"` and exited 105, and a windowed run of the same suites started beside it never ended (two Godot
  processes stayed until stopped by PID). Separately, a push right after a green matrix went out just before main moved
  again, so the pull request was DIRTY and needed a second merge and push.
- **Cause:** the global class cache is not refreshed by a merge: a new `class_name` file needs one `--headless --import`
  before any run ([the older lesson](2026-11-01-new-class-name-needs-import.md)), and a windowed run with parse errors
  waits instead of exiting. The push was not preceded by a fetch.
- **Fix:** after every merge of main that adds a `.gd` file, run `godot --headless --path game --import` first, then the
  suites; give a windowed run `--timeout` and look for `Parse Error` in its log early; `git fetch` and read
  `git log HEAD..origin/main` right before the one push.
- **Docs:** none beyond this lesson and the older one.
