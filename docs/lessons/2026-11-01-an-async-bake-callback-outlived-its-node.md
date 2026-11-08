---
areas: [godot, blender]
---
# An async navigation bake called back into a freed node

2026-11-01

- **Saw:** `SCRIPT ERROR: Attempt to call function 'null::_on_baked (Callable)' on a null instance.` from the
  completion lambda of an async navmesh bake, in tests that ended a night right after a door was bought.
- **Cause:** `NavigationServer3D.bake_from_source_geometry_data_async` calls its completion callable later on the main
  thread, whatever happened to the node that asked; the lambda called a Callable of a freed object.
- **Fix:** guard the call with `done.is_valid()` (false once the object is freed); keep a test that frees the owner
  during a bake.
- **Docs:** [Zombie crowds](../engines/godot/crowds.md).
