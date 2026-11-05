---
areas: [net, tests, general]
---
# A room limit was measured for 8 bodies and the cap raised to 15

2026-11-05

- **Saw:** Deadnight's `ROOM_CAPACITY` 3 was sized on three rooms of eight people at 120 alive (p95 11.5 to 13.3 ms of
  the 16.7 ms tick on Railway). #1179 then let a night hold 8 people and 7 bots, and only the bandwidth was measured
  again. The same bench with the bots run as the host runs them: three such rooms took 26.6 to 28.8 ms a tick, every
  tick over budget; one room of 15 at 120 alive was over on 20 to 34 percent of ticks. A bot cost about 0.7 ms of the
  tick, twice a person standing still, because a room with a bot builds the frame on every step and every bot hears it.
- **Cause:** a capacity number carries the cap it was measured under. The bench seated people only and never ran the
  bots, so a change that let a room hold more bodies (and a new kind of body) did not touch any test or number.
- **Fix:** when a seat, bot or crowd cap moves, rerun the capacity bench for the new worst room before the change
  lands, with the new kind of body run as the host runs it (`crowd_server_bench.tscn --bots=N`). Run the old setting
  beside the new one in the same container, interleaved, three times: the host's speed changed by a third between two
  days (the old accepted setting read p95 15.5 to 16.7 ms against 11.5 to 13.3 in the last measurement), so only the
  ratio to the control carries over. Size the settings from the worst load they allow, and put that load in CI.
- **Docs:** Deadnight `docs/research/crowd-budget.md`, "Rooms of fifteen bodies (#1193)".
