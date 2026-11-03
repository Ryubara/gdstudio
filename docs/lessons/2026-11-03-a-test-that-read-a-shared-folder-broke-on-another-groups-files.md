---
areas: [tests, blender]
---
# A test that read a shared folder broke when another group added its files

2026-11-03

- **Saw:** after merging main, Deadnight's `test_smallmap_kit_walls.gd` failed on `pendant_lamp` and
  `wall_lantern`: `Invalid access to property or key 'pendant_lamp'` (Deadnight #636).
- **Cause:** the walls suite listed every scene in the kit's shared `fixtures/` folder as one of its own pieces and
  looked each up in its own build report; five groups of the kit write fixtures into that folder.
- **Fix:** a suite checks the pieces its own build reports (the report's keys) and that each has its fixture, never
  "every file in the folder". Merge main and run the neighbouring groups' suites before each push.
- **Docs:** [modular kits](../blender/modular-kits.md).
