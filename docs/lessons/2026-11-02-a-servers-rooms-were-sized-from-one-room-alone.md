---
areas: [net, backend, tests]
---
# A server's room count was sized from one room benched alone

2026-11-02

- **Saw:** `ROOM_CAPACITY` 4 was written from "a night costs about 3 ms of a 16 ms step" and never revisited when a night
  grew to 120 zombies (7 ms median, 15 ms p95 on Railway): four such rooms in one process need about 28 ms of a 16.7 ms
  tick. Nothing failed until a crowd above 40 was allowed, because the bench ran one room.
- **Cause:** a game server runs its rooms one after the other in one thread, so the tick that has to fit is the sum of
  the rooms, and the heavy ticks of every room fell on the same frame (they all began on the same parity of the 30 Hz
  zombie step). A per-room bench cannot show either.
- **Fix:** bench the process, not a room (Deadnight `crowd_server_bench.tscn --rooms=K`: K nights each in its own
  `SubViewport`, all stepped in one frame, the process's tick reported); read p95 and the ticks over budget; give rooms
  alternate halves of the frames for their heavy tick (about 30 percent off the p95 at four rooms); size the rooms and
  the alive budget from the worst allowed load on the slowest processor seen (a ratio from a single-room run, as
  Railway does not let you choose the host).
- **Docs:** [Deadnight crowd budget](https://github.com/Ryubara/deadnight/blob/main/docs/research/crowd-budget.md).
