---
areas: [camera, gameplay, tests]
---
# A bot's body took the view from the person, and every capture had been made to look away from it

2026-11-03

- **Saw:** "When I play in Godot and set up 3 bots, my camera is stuck to one of the bots instead of my player
  character. I can still control my character" (Deadnight #702). Every test and capture of the night with bots passed.
- **Cause:** every body is the player scene, whose `Camera3D` has `current = true`; a `Camera3D` that enters the tree
  as current takes the viewport's view, so the last body to join (a bot, seated after the person) owned it. This was
  already found once (a second body took the current camera, #430,
  [lesson](2026-11-01-a-second-body-took-the-current-camera.md)), but the fix then was `make_current()` in the
  capture scripts, not in the code that creates bodies: about twenty capture scripts call it, so none of them could
  see the game's own behaviour, and the tests read the player's camera node, never the viewport's current camera.
- **Fix:** only the local person's body owns a camera: a body that is not the person's (a bot, a copy of another
  machine's player) gives the view up before it enters the tree (`Player.release_view()`, called in
  `NightWorld.add_body`). A test asks the viewport (`get_viewport().get_camera_3d()`) which body owns it, after the
  spawn, after a bot is downed and raised, after the person is downed and raised and after a bot seat is filled
  late, and once through the Play screen's own path; the browser probe publishes the owner too.
- **Check for next time:** a workaround made in a capture script is a bug report: the capture's `make_current()`
  line says the game does the wrong thing. Fix the cause where the bodies are made, and a test asserts the thing the
  workaround papered over, on the engine's own answer (the viewport's current camera), not on the node it expects.
- **Docs:** [Camera](../godot/camera.md#one-current-camera-per-viewport).
