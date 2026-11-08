---
areas: [net, godot-ui]
---
# A test that called the rules directly never reached the HUD

2026-11-01

- **Saw:** points granted with `server.rules.apply(...)` in a night test did not show on the HUD (the prompt read
  "NEED 350 POINTS" with 600 points).
- **Cause:** the server returns only the events of its own `apply` and `step`, and clears its outbox at each step; an
  event from a call made beside it is in no client's stream.
- **Fix:** deliver what the call returns (`night.state.apply_events(rules.apply(action))`), as the link would. The
  server-side half of the same gap is
  [events the server causes alone](2026-11-01-events-the-server-causes-alone-never-reach-the-client.md).
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md); Deadnight `docs/research/hud.md`.
