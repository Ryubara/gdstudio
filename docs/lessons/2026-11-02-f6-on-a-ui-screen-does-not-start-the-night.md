---
areas: [godot, godot-ui]
---
# F6 on a screen scene shows the screen but never starts what it hosts

2026-11-02

- **Saw:** a developer pressed F6 on Deadnight's `night_screen.tscn` to play a night and got only the loading card.
- **Cause:** a screen of the router starts its work in `screen_enter`, which the `UIRouter` calls when it enters the
  screen; F6 only instances the scene, so `_ready` ran and `screen_enter` never did.
- **Fix:** a dev entry scene that builds the same parts and starts the night itself (`game/dev/play_night.tscn`, with
  its options in the inspector); the tuning guide says to use it or go through the menu.
- **Docs:** [Screenshots of the editor's inspector](../engines/godot/editor-screenshots.md) (how the guide's pictures were
  made); Deadnight `docs/design/tuning.md`.
