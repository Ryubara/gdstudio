---
areas: [tests, net, gameplay]
---
# A hand-driven test client was sent no events because it sent no command

2026-11-03

- **Saw:** a two-client online test fired from the server (`server._combat(...)`) and the other client heard only
  `zombie_spawn_requested`: no `shot_fired`, no `element_burst`, though the server's outbox held them.
- **Cause:** the night server waits for each player's command every tick and answers with the tick's events; a test
  client that never sends one (an empty `NightCommand`) is not served, and a shot made beside the step has no origin
  the server accepts (the view must agree with the shot).
- **Fix:** connect the client's `ticked` to `link.send(command.to_dict())`, keep one `NightCommand` per client, aim it
  with `aim_along(direction)` and set `fire`, as a player's input would; do not call the combat server by hand.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#events-reach-a-client-only-through-its-command-loop).
