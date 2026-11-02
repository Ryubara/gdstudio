---
areas: [godot, net]
---
# Reduced motion did not reach nodes that were already running

2026-11-01

- **Saw:** a film-grain overlay kept flickering after Reduced motion was switched on.
- **Cause:** the nodes read the static flag `UIMotion.reduced` once in `_ready`, and the overlay lives for the whole
  session; a `static var` cannot declare a signal.
- **Fix:** give the static var a setter that emits through a small `RefCounted` bus (`UIMotion.changed()`); every node
  connects in `_ready` and applies the value at once. Test by flipping the flag while the main scene runs.
- **Docs:** [UI controls](../godot/ui-controls.md).
