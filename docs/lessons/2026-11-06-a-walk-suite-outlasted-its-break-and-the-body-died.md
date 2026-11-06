---
areas: [tests, gameplay]
---
# A suite that walked 880 paths outlasted its "long" break, and the stops it counted were a dead body

2026-11-06

- **Saw:** a suite that sets a body down on every roam spot and walks it to every other (Deadnight #1334) reported
  1 700 of 1 892 walks stopped, most "against nothing", standing exactly where the body had been set down.
- **Cause:** the night's break was set to 3 000 s ("long enough"), which is 180 000 ticks; the walks took 400 000. The
  round began halfway, the dead came and the body died (`health_of` 0), and a dead body never moves again, so every
  later walk stood at its start. The first reading blamed the walker.
- **Fix:** read the body's state in the first failing line (the failure message of the stalls carried hit points and
  the tick), size a break for the longest run of the suite (`1.0e6` s), and keep a walk short: start `RUN_UP` metres
  before the prop and end `RUN_ON` after it instead of walking 100 m paths (880 walks took 3 min, the windows 8 s).
- **Docs:** Deadnight `docs/research/zombies.md`, "A solid prop that is not CSG is not in the mesh either".
