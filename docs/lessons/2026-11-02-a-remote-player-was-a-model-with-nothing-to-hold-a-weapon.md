---
areas: [net, gameplay]
---
# A remote player was a model with nothing to hold a weapon

2026-11-02

- **Saw:** online, a client drew every other player without a gun; no swap, aim, fire, reload, swing or throw showed on
  them (the maintainer, Deadnight #518).
- **Cause:** the frames already named each player's weapon and every event reached every client, but all the code that
  draws a weapon asks `Night._body_of(id)` for a `Player` with a `PlayerAnimation`. Online that was null for everyone
  but the local body, because a remote player was a separate bare model that only played Idle, Walk and Run. The client
  received everything and applied nothing. Each piece was tested on the local body; nothing looked at another client's
  screen.
- **Fix:** a remote player is the same scene as a played body (a puppet `Player`: no input, collision, camera or
  simulation), so the same animation draws it; the frame gains the two small fields the pose needs (`aim`, `pitch`),
  delta-coded. A test with two clients and a late joiner over the real socket fails when `_body_of` is put back to null.
- **Also:** a presenter that works through a node type (`as Player`) turns "no such body" into a silent skip: say it
  loudly, or make the remote thing the same type. A bump of the protocol version for the new frame fields collided with
  two other branches in one afternoon: merge `origin/main` right before the last push and bump past it.
- **Docs:** Deadnight `docs/research/multiplayer.md` (Other players' weapons); [What to plan from the
  start](../studio/plan-from-the-start.md).
