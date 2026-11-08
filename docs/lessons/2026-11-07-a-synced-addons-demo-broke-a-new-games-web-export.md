---
areas: [godot, web]
---
# A synced addon's demo broke a new game's web export

2026-11-07

- **Saw:** a game made from the 3D Blank template imported, ran and passed its tests with no `ERROR`, but
  `--export-release Web` printed 20 lines: `Identifier "UIRouter" not declared` and `Failed to load script
  "res://addons/gds_ui/demo/demo.gd"` for the five demo scripts.
- **Cause:** `gds sync` writes the whole `gds_ui` addon into every game, demo included; the demo names the `UIRouter`
  autoload, which a game registers only when it wants the addon. Import and a run load scripts on use, the export loads
  every one under "Export all resources".
- **Fix:** the preset's `exclude_filter` holds `addons/gds_ui/demo/*` (the demo is the kit's own tour, never game
  content), and a template test reads the filter. The template's CI job fails on any `ERROR` in the
  export log, which is what caught it.
- **Docs:** [Prototype surfaces and daylight](../engines/godot/prototype-surfaces.md#smaller-findings), [Sync](../studio/sync.md#addons).
