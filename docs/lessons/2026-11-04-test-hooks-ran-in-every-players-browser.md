---
areas: [web, godot, tests]
---
# A browser test's probes crossed the JavaScript bridge in every player's page

2026-11-04

- **Saw:** the review of #907 found four probe nodes added to every web page that read `window.deadnight` (a property
  get over the bridge, and a new `Array` for the pads) in every frame, for tests that only run under `?probe`; counted
  with a proxy, a plain menu made 430 bridge calls a second and a night 141.
- **Cause:** the probes were added unconditionally ("it only reads, nothing depends on it") and the snapshot wrote
  every key four times a second whether or not anyone read it. A cost nobody measured was free by default.
- **Fix:** add test hooks only when the page asks (`WebProbe.asked`: `?probe`), write only changed keys, list pads on
  `Input.joy_connection_changed`; the web job counts the plain page's bridge calls and fails above a ceiling. Same
  task: a local named `delta` inside `_process(delta)` was a parse error that made the whole class unresolvable, and a
  GdUnit run started with `-d` sat at the debugger prompt (see the `-d` lesson of 2026-11-01): run
  `-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a <test> -c --ignoreHeadlessMode` without `-d`.
- **Docs:** `docs/engines/godot/web-heap.md` (test hooks cost the player's page).
