---
areas: [godot]
---
# "Cannot infer the type of variable" on arithmetic with a dictionary value

2026-11-01

- **Saw:** `Parser Error: Cannot infer the type of "cooked" variable because the value doesn't have a set type.`
- **Cause:** in `var cooked := now - _cooks[id]["started"]` an element of an untyped `Dictionary` is a Variant, so the
  whole expression is a Variant and `:=` has nothing to infer.
- **Fix:** write the type (`var cooked: float = ...`) or keep the record in a small typed class.
- **Docs:** none.
