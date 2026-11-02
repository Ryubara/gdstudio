# A static path set by the game root outlived the root in a test run

2026-11-02

- **Saw:** in a test run a static path set by the game root was still set after that root was gone (Deadnight
  challenges, #429).
- **Cause:** statics live for the whole process; in a test run many roots come and go, so a value one root set
  outlives it and later suites read it.
- **Fix:** reset the static in the root's `_exit_tree`.
- **Docs:** none yet; a GdUnit rule.
