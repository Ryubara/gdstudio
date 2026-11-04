---
areas: [tests, godot-ui]
---
# A lock on every wearable failed the tests that were not about it

2026-11-04

- **Saw:** after the ladder put a level on 26 wearables and 10 colours, 88 assertions failed across the look, loadout,
  menu and network suites: a preset put on a screen, saved, loaded or sent through the look hub came back with its jacket
  and boots swapped for starting pieces.
- **Cause:** the tests used presets, which wear gated pieces, and every default (a screen's unlocks, `LookStore.load_look`,
  the hub's server) now meant "a level 1 player". Only a handful of the tests were about the lock.
- **Fix:** each test that is not about the lock says what the player owns (`LookUnlocks.at_level(55)`, a top-level
  profile for the menu shell, a hub that lets everything through by default) and the few that are ask for a level.
  Anything a test hides behind a default is a decision: write it in the test.
- **Docs:** [Deadnight's customization page](https://github.com/Ryubara/deadnight/blob/main/docs/design/customization.md).
