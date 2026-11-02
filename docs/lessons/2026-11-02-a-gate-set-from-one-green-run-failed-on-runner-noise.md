---
areas: [ci, web]
---
# A load-time gate set at 30 s plus 75 % failed a main run at 53 s

2026-11-02

- **Saw:** the web smoke's night load gate (last green 30 s, 75 % allowed, 52 s) failed a main run at 53.3 s; the next two
  runs of the same content took 29.9 and 32.1 s.
- **Cause:** a shared CI runner moves the same build by 40 % and more: ten main runs of one morning took 24.3 to 53.3 s,
  and the slow run also reached the menu slowest (19.2 s). The baseline was one green run.
- **Fix:** the baseline is the mean of ten runs (36 s) and the gate twice that (72 s), far under the 82 to 107 s
  before the load was cut; small rises are read from the recorded numbers, not gated.
- **Docs:** [Deadnight web export](https://github.com/Ryubara/deadnight/blob/main/docs/research/web-export.md).
