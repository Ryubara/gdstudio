---
areas: [godot-ui, net, tests]
---
# A menu pushed on the router froze the night behind it

2026-11-02

- **Saw:** Deadnight's in-game menu (#471) had to open Settings without stopping a night played with others. Pushing
  the settings screen with `UIRouter.push` was the obvious route, and it would have frozen that night: the router
  covers the screen below with `process_mode = PROCESS_MODE_DISABLED`, so the `Night` node under it stops reading the
  socket and the player is dropped by the server.
- **Cause:** the router's stack is built for screens that replace each other. "Covered" means "off", for the node
  and everything under it, whatever the screen thinks about pausing.
- **Fix:** a menu over a live game holds its sub-screens as children of itself (the settings screen has an `embedded`
  flag and a `closed` signal instead of `UIRouter.pop()`), so the game screen stays on top of the stack and keeps
  running. A test joins a real server over loopback, opens the menu and the settings, and checks the server's tick
  still climbs. The same suite hung once on `await UIRouter.idle` after a click: `idle` is emitted once, when the
  queue empties, and a click that already finished the pop never emits it again. Wait for it only while
  `UIRouter.busy`.
- **Docs:** [UI controls](../godot/ui-controls.md#a-menu-over-a-live-game).
