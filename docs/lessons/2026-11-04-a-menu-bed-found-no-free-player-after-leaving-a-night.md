---
areas: [audio, godot]
---
# A menu bed started on returning from a night found no free player and stayed silent

2026-11-04

- **Saw:** a test that left a night at once and expected the menu's ambience bed back failed: `MenuAmbience.is_playing()`
  was false with the menu on top and nothing in the log.
- **Cause:** the night's beds (up to seven) fade out over two seconds after the night and keep their players until
  silent; the service had six bed players, so `start_bed` found none free and returned null, which nothing reported.
  The menu's bed is started once, on the menu's resume, so it never tried again.
- **Fix:** `AudioService.POOL_BEDS` 10 (the night's seven still fading plus the menu's two), and
  `test_menu_ambience.gd` pops the night at once and expects the bed. A new bed is a count to check against the pool.
- **Docs:** [Godot audio, menu sounds](../godot/audio.md#menu-sounds).
