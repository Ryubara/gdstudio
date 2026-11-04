---
areas: [godot]
---
# `set_process(false)` in `_init` was turned back on at ready and freed an effect early

2026-11-03

- **Saw:** a one-shot effect that counted its live parts freed itself after 0.5 s instead of 7 s; its scorch mark
  disappeared with the fireball.
- **Cause:** a node whose script defines `_process` gets `set_process(true)` when it is ready (it is part of the ready
  notification), after `_init` ran. `set_process(false)` in `_init` was undone, and the one empty `_process` call counted
  down the "parts playing" total.
- **Fix:** turn it off in `_ready` (after Godot has turned it on), and let only the code that needs it turn it on. A test
  that holds a part to its full length (the scorch outlives the light) catches it; a test that only counts nodes at the
  end does not.
- **Docs:** [Pooled and one-shot effects](../godot/one-shot-effects.md#_process-is-on-after-ready).
