---
areas: [audio, tests]
---
# New sounds and groups were in the catalog but not in the tuning tables

2026-11-03

- **Saw:** the game's `godot` check failed on `test_no_sound_is_in_the_catalog_but_not_the_table` (ten new sounds) and
  `test_the_sound_mix_file_holds_the_old_constants` (two new voice groups), after a green local run on the old branch.
- **Cause:** main gained the sound tuning tables (`tests/tuning/sound_defaults.json`, `default_values.gd`) after the
  branch was cut; the branch added a bank and groups without a row in them. Merging main was not followed by the
  `tests/tuning` suite.
- **Fix:** one row per new sound in the json (the bank's values, `near_cap_db` `"inf"` for infinity), the sound count in
  `test_every_sound_has_the_values_it_had_in_code`, and each new group in `SOUND_MIX.group_limits`.
- **Check:** after `gds merge-main`, run the suites of the areas main touched (`tests/tuning` for any sound, bank or
  mix change), not only your own.
