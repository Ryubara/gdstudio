# A shake under reduced motion printed "Tween started with no Tweeners"

2026-11-01

- **Saw:** with reduced motion on, a refused action printed `Tween (bound to ...): started with no Tweeners`.
- **Cause:** `UIMotion.shake` returned a tween it had made but given no step.
- **Fix:** add `tween.tween_interval(0.0)` before returning, so the tween is valid and does nothing.
- **Docs:** [UI controls](../godot/ui-controls.md).
