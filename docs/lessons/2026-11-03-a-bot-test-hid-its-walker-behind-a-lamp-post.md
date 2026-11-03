---
areas: [tests, gameplay]
---
# A bot test hid its walker behind a lamp post, and the maintainer moved the post

2026-11-03

- **Saw:** after the maintainer's hand edits to the drive-in map, `test_bot_night.gd` failed six times in CI
  ("a walker behind a wall is never believed or aimed at"): the premise check, that the wall hides the walker, was false
  (Deadnight #719).
- **Cause:** the "wall 4.5 m from home" in the test was the field's first lamp post (a 0.1 m cylinder) on the line from
  home to the walker; the comment called it a wall and the test wrote the post's spot as numbers. The maintainer moved
  the post 1.27 m in the editor, so the line no longer met it. The local run before the push covered the light, fuel and
  navmesh tests but not the bot suites, which read the map.
- **Fix:** the test reads the post's position from the loaded lot and stands the walker on the line through it; the
  premise asserts stay, so a moved post fails them at once, loudly. A test that needs cover names the node that is the
  cover.
- **Docs:** this lesson. Check: when a hand edit moves lamps, props or walls, run every suite that raycasts the lot
  (`tests/night`, `tests/bots`), not only the world tests, and write a test's cover as a lookup, not as coordinates.
