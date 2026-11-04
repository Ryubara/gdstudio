---
areas: [tests]
---
# A test zombie stood behind a wall and a wall's stop read as the zombie's

2026-11-03

- **Saw:** an online test put a walking zombie 12 m ahead of the spawn and the sprinting body stopped 1.3 m short of it,
  the same on the client and the server, as if the dead stopped a body at its reach (Deadnight #914).
- **Cause:** a fence stood 8.4 m ahead; the zombie was on the other side of it and the body was stopped by the wall. The
  distance read like a result of the rule under test. The failed run also left the sprint key held, so the next arm of
  the test started already running.
- **Fix:** print a trace (body, zombie, its mode) every quarter second once before trusting a placement, put the walker
  where a ray from the body reaches it, and release every key in `after_test` and before each arm.
- **Docs:** Deadnight `tests/net/test_dead_online.gd` (`DEAD_TRACE=1` prints the trace).
