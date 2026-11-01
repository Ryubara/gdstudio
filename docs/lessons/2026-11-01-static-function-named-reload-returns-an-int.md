# A static function named `reload` on a script class returned an int

2026-11-01

- **Saw:** `CombatAction.reload(1)` failed with `Invalid type in function 'apply'. Cannot convert argument 1 from int to
  Dictionary`.
- **Cause:** a script class is itself a `GDScript` object, and `GDScript.reload()` (returns an `Error`) wins over a
  `static func reload`. The same trap exists for `new`, `free`, `get_script` and other Object or Script methods.
- **Fix:** name static builders for what they build (`reload_weapon`), never after Object or Script methods.
- **Docs:** Deadnight `docs/research/weapon-firing.md`.
