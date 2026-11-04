---
areas: [godot, tests]
---
# A trial edit on a loaded resource was lost with its last reference

2026-11-04

- **Saw:** a probe that added 10 degrees to every hold's `stance_turn_deg` before posing the soldier printed exactly
  the numbers it printed without the change.
- **Cause:** the probe loaded each `.tres`, changed it and let the variable go; with no reference left the resource
  was freed and dropped from the loader's cache, so the next `load()` of the path read the file again, unchanged.
- **Fix:** keep the edited resources in an array for the probe's life (`_kept` in Deadnight
  `game/tests/art/measure_arms.gd`). A change meant for later loads lives only as long as something holds the
  resource.
- **Docs:** this lesson.
