# A Callable made from a RefCounted's method went invalid

2026-11-01

- **Saw:** a line-of-sight check stored as `WorldProbe.new(space).callable()` silently answered "clear" for every shot
  (`Callable.is_valid()` was false).
- **Cause:** a Callable holds its object by id, not by reference, so the temporary `WorldProbe` was freed at once.
- **Fix:** keep the object in a member (`_sight := WorldProbe.new(...)`) and hand out `_sight.callable()`.
- **Docs:** [Godot testing](../godot/index.md#testing-and-capture); Deadnight `docs/design/slice.md`.
