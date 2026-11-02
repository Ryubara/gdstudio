---
areas: [net, tools]
---
# A correction that moves the body must move the history it is judged against

2026-11-02

- **Saw:** a client with a round trip near 200 ms (or a short freeze of its own loop) flew across the map, kilometres
  off and growing, and never came back: the camera ended in the skybox. Local tests with no delay, and the bad-network
  tests that held packets back, were all green.
- **Cause:** client prediction compared each server answer with the position it had recorded for the acknowledged
  command, and corrected the body by a share of the difference, but left the recorded positions of the later, still
  unanswered commands as they were. Answers arrive a round trip late, so each one measured the same error again: the
  correction was applied once per frame in flight. With 0.25 of the error per frame and six or more frames in flight
  the repeats outgrow the error, and a snap (the whole error) repeated per frame grows exponentially. A freeze
  triggers it (eight catch-up ticks sent together, the server uses the newest), but any push over the deadzone does at
  that round trip.
- **Fix:** shift the remembered positions by every correction; snap a body far from the server when there is nothing
  to judge it by; after a freeze put the body where the server says and skip the catch-up ticks. Test the loop closed,
  in one dimension, at 50 to 400 ms, and freeze the client's own thread (not the link) over a real socket.
- **Docs:** [Deadnight multiplayer research, "A client that
  freezes"](https://github.com/Ryubara/deadnight/blob/main/docs/research/multiplayer.md).
