---
areas: [tests, general]
---
# A new action and a new sound bank each broke an older suite that loops over the whole registry

2026-11-04

- **Saw:** Deadnight #1057 added a rules action and an on-demand sound bank. My new suites passed. Whole-folder runs then
  failed `test_validation.gd` (three cases: every action type needs a sample) and `test_load_cost.gd` (the background
  load must leave 0 files to load for every sound).
- **Cause:** both suites iterate a registry (`RulesAction.REQUIRED`, `SoundCatalog.ids()`) and assert something about
  every entry. A new entry is held to every such assertion, and I had run only the suites I wrote.
- **Fix:** a sample for the action; the load test loops over `SoundCatalog.ids_for_night()`, the list the night loads
  (the on-demand bank is excluded by design). Teeth: the failures came from running `tests/rules` and `tests/night` whole.
- **Check next time:** when adding to a registry (actions, sounds, wire types, snapshot keys), grep the tests for loops
  over it (`grep -rn "REQUIRED\|SoundCatalog.ids()" game/tests`) and run those folders whole before the first push.
  The same task also wrote CRLF into GDScript with a Python edit: see the existing lesson on opening files with
  `newline=''`.
