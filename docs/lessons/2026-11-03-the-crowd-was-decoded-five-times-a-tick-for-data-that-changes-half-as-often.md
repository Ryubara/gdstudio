---
areas: [gameplay, godot]
---
# The crowd was decoded five times a tick, for bytes that change every other tick

2026-11-03

- **Saw:** the performance review of a round-12 night with three bots (Deadnight #907): the client side of the tick
  was 4.4 ms of 11.9 ms, 3.6 ms of it `event.frame`. Four `event.frame` a tick (15,360 in 3,840 ticks): the person's
  `ClientState` and one for each bot each decoded the whole crowd, and the horde decoded it again for the views.
- **Cause:** every consumer of one event did its own work on it, at the rate of the event (60 Hz) and not the rate of
  its data (the simulation steps at 30 Hz, so every second frame holds the bytes of the one before). Nobody saw it
  because each decode was cheap alone (0.15 to 0.29 ms) and was written when there was one reader.
- **Fix:** one cache keyed on the bytes (`ZombieCodec.decode_shared` keeps the last bytes and entries and hands the
  same list out again); the horde skips bytes it has applied and keeps their time for the next, and the voices follow
  the horde. A test counts `ZombieCodec.decode_count` over ticks of a night with three bots (541 before, at most one
  every second tick after). Round 12, 3 bots, headless pair run on a quiet machine: `tick.pump` 2.9 to 1.7 ms.
- **Check for next time:** for every handler of an event that loops over the crowd, ask who else handles the same
  event and what rate its data changes at; share the result and work per change, not per delivery.
- **Docs:** [Crowd budget](https://github.com/Ryubara/deadnight/blob/main/docs/research/crowd-budget.md) in the game.
- **Also hit:** `test_soldier_voice.gd` changed `state.zombies` in place (`assign`), which now changed the list every client
  shares and failed the next frame's test. A shared list is never changed in place: replace it (`state.zombies = [...]`).
