---
areas: [tests, blender]
---
# A kit test claimed every file in a shared folder

2026-11-03

- **Saw:** Deadnight's cover and clutter props (#656) failed CI in the walls group's test
  (`test_smallmap_kit_walls.gd`): seven failures on the helmet, lantern, radio and rubble (no collision), then
  `Invalid access to property or key 'chair'` on the walls build report.
- **Cause:** the test listed its pieces with `DirAccess.get_files_at("res://world/smallmap/fixtures")`, a folder all
  five kit groups write into, and held every file there to the walls' rules and the walls' report. It passed while the
  walls were the only group merged.
- **Fix:** a group's test reads its own pieces from its own build report (the report's keys) and checks that each has
  a fixture; each group has its own test. Never enumerate a shared folder to find "my" files.
- **Docs:** [Modular kits: building props](../tools/blender/modular-kits.md#building-props).
