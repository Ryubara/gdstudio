---
areas: [tests, process]
---
# Tests wrote the player's real settings file

2026-11-02

- **Saw:** the maintainer's game lost its camera shake: `%APPDATA%/Godot/app_userdata/Deadnight/settings.cfg` read
  `camera_shake=0`, tests on other branches then failed for no visible reason, and two agents edited the real file to
  "fix" them.
- **Cause:** suites saved through the game's `Settings` autoload, which writes `user://settings.cfg`. Under the test
  runner and the editor, `user://` is the player's own data folder, and nothing redirected it for tests. Branches made
  before the fix kept writing it until they merged main.
- **Fix:** tests and captures use their own settings store, and a test fails if a suite run changes the real file
  (Deadnight #418, #446). Agents never edit `app_userdata`; they report it.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
