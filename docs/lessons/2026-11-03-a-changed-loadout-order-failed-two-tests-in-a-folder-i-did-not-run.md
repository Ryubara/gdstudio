---
areas: [tests, gameplay]
---
# A changed loadout order failed two tests in a folder that was not run

2026-11-03

- **Saw:** after weapons got stable slots (Deadnight #682: a bought weapon takes the slot of the one it replaces, not the
  end of the list), the suites run for the change (HUD, input matrix, night, touch) were green; the full folder run
  found `tests/weapons/test_weapon_carry.gd` asserting the old order (`[pistol, shotgun]`), twice.
- **Cause:** the order of `CombatServer.carried` was an accident of a dictionary's insertion order that tests had
  pinned; the change was checked against the suites that named it, not against the folders that call the same function.
- **Fix:** when a function's observable order or shape changes, grep its callers' tests (`carried(`, `_ids()`) and run
  those folders at once, then the whole folder set before pushing. The two tests now assert the slot order on purpose.
- **Docs:** Deadnight `docs/design/weapons.md` ("Carrying weapons").
