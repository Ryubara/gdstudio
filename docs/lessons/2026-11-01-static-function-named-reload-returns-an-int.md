# A static function named `reload` on a script class returned an int

2026-11-01

- **Saw:** `CombatAction.reload(1)` failed with `Invalid type in function 'apply'. Cannot convert argument 1 from int to
  Dictionary`.
- **Cause:** a script class is itself a `GDScript` object, and `GDScript.reload()` (returns an `Error`) wins over a
  `static func reload`. The same trap exists for `new`, `free`, `get_script` and other Object or Script methods.
- **Fix:** name static builders for what they build (`reload_weapon`), never after Object or Script methods.
- **Same trap, virtuals:** a static helper named `_set(...)` broke compilation (Deadnight #462): `_set`, `_get`,
  `_get_property_list`, `_validate_property`, `_notification`, `_init` and `_ready` are Object or Node virtuals, and a
  method of the same name overrides one with the wrong signature. Never name a helper after one; a grep in
  pre-commit can catch it. (The same agent briefly committed with hooks off, `core.hooksPath=/dev/null`, and then
  amended: hooks are never bypassed, not even for a local work-in-progress commit.)
- **Docs:** Deadnight `docs/research/weapon-firing.md`.
