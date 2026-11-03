---
areas: [audio, tests]
---
# A shared sound helper changed for one caller moved the others

2026-11-03

- **Saw:** to play the player's own reload steps flat (Deadnight #683), `WeaponSounds._at_player` was changed to skip
  the position for the own player; the full run then failed `test_an_empty_trigger_clicks_where_the_shooter_stands`:
  the click and the swap rustle, which use the same helper, had gone flat too.
- **Cause:** the helper places every per-player sound, not only the one the change was for; only the reload tests
  were run before committing.
- **Fix:** leave the shared helper as it was and give the one caller its own (`_reload_step`); before committing a
  change to a shared helper, grep its callers and run their suites.
- **Docs:** none needed beyond this lesson.
