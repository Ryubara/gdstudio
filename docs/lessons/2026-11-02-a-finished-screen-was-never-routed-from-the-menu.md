---
areas: [godot-ui, tests]
---
# A finished screen was never routed from the menu, and a headless layout test cannot see text

2026-11-02

- **Saw:** the maintainer pointed out that the game settings a host sets when creating a lobby, such as the
  multipliers, should also be available in a solo game (Deadnight #620).
- **Cause:** #449 built the Play screen with the shared settings panel and left its route as "a one-line change left to
  the menu work"; the menu rework (#466) wrote "Solo opens the night", the scenes table called the screen "an old
  placeholder, nothing routes to it", and no issue held the line. The screen's own tests opened it by path, so they
  passed while no player could reach it.
- **Fix:** Solo opens the Play screen (Deadnight #620); a test presses Solo from the menu and runs the night under the
  chosen values; another fails when a `MatchSettings` key has no row in the panel, solo's or the room's.
- **General:** a screen is shipped when a player reaches it from the menu: a hand-off to "the menu work" becomes an issue
  in the same pull request, and the screen's test starts from the menu's button, never from the scene path. A
  headless run measures text as nothing, so a fit test there passes on a layout a phone cuts off: check the fit in a
  windowed capture (real fonts) and in the web build.
- **Docs:** [Headless renderer](../engines/godot/headless-renderer.md), [What the maintainer caught](../studio/maintainer-corrections.md).
