---
areas: [net, tests]
---
# A prop that was solid on the client only drifted the predicted body 2.2 m from the server

2026-11-03

- **Saw:** the bots-slots soak failed on `main` and on three branches with "client N is 2.5 m from the server" (bound
  2.5 m), late in a night, and only under load; alone it passed (Deadnight #748, #754). Traces showed the client body
  standing still against an invisible wall while the server body walked on through the same spot.
- **Cause:** the prize crane is a drawing the client builds (`CraneView`), and its script gave itself a `StaticBody3D`
  ("a player and a shot meet the cabinet"). A game server draws nothing, so its world had no cabinet: a sprint past the
  crane stopped on the client and not on the server. The earlier guess (a stall guard skipping ticks) was wrong, the
  trace of what each world held at the server's spot found it.
- **Fix:** a solid thing lives in the world both sides build (`CraneBlock` in `NightWorld`, moved by the rules' event on
  the server and by the frame on a client); the drawing has no collision. `test_world_parity.gd` joins a real client to
  a real host and asks that every solid thing in the client's viewport is in the server's at the same place (it failed
  on `main`: 227 against 226).
- **Docs:** [Multiplayer: same physics world](../godot/multiplayer.md#the-two-worlds-must-hold-the-same-solid-things).
  Check: a node a view script adds with `.new()` gets no collision; a solid thing is built where the server builds it.
