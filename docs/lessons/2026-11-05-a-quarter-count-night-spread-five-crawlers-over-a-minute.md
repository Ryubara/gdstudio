---
areas: [gameplay, tests]
---
# A night at a quarter of the dead spread five crawlers over more than half a minute

2026-11-05

- **Saw:** a test that put down five crawlers with the crowbar "in thirty seconds" never saw its run, though all five
  were put down (Deadnight #1074).
- **Cause:** a count multiplier below 1 makes a round smaller and divides the spawn interval by it, so at 0.25 the dead
  come four times as slowly. The test had picked 0.25 to make long nights short, and it made a timed window long.
- **Fix:** a test that is about a time window sets the count to 2 (the interval halves); a test that is about many
  rounds sets 0.25. Check for next time: when a window is in seconds, print the seconds between the events the test
  makes before trusting the window.
- **Docs:** [Multiplayer](../godot/multiplayer.md#a-room-test-that-needs-a-map-or-a-fast-round).
