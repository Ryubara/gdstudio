---
areas: [gameplay, tests]
---
# A removed field or a stand-in table left its callers behind in the tests

2026-11-03

- **Saw:** after merging main into a feature branch, three suites failed: `Invalid access to property or key 'weapons'
  on a base object of type 'Resource (UpgradeTuning)'`, a catalogue-wide test missing `ray_gun` in a sound table, and a
  weapon-hold test that expected the old stand-in size factors. Main itself had two tests still reading the removed
  `UpgradeTuning.weapons`, because two pull requests that each passed alone were merged one after the other.
- **Cause:** a field, a table entry or a stand-in (a model, a sound row) was removed or replaced in a source file and the
  tests that read it were not searched for. Tests that loop over a whole catalogue (`WeaponCatalog.IDS`) also pick up
  every new id, so they fail on the first weapon a branch adds.
- **Fix:** after every `gds merge-main`, and before removing or renaming a field, grep the whole `game/` folder (tests
  included) for its name (`rg "\.weapons\b|bloom_multiplier"`), read the catalogue-wide tests (`test_weapon_equip`,
  `test_weapon_sounds`, `test_weapon_hold`, the re-cut layer test) for what a new id must add, and run those suites
  before pushing; do not chase a failure that main already has, name it in the pull request instead.
- **Docs:** Deadnight `docs/design/weapon-hold.md` and the weapon list in its `docs/design/weapons.md`.
