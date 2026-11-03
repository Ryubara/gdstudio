---
areas: [tests, gameplay, ci]
---
# A "worst tick under N ms" budget failed on a shared machine, and so did a 99th percentile one

2026-11-02

- **Saw:** Deadnight `test_bot_server_cost.gd` (three bots, 40 zombies, 900 ticks, worst tick under 1.5 ms scaled by a
  reference piece of GDScript) passed at 1.25 ms alone, then failed after a merge of main with worst ticks of 3 to 70 ms
  while the machine ran other agents' jobs (CPU about 60%). Judging the 99th percentile failed once too (3.4 ms against
  2.4 ms).
- **Cause:** one tick in a few hundred is lost to the scheduler whatever the code does (the median stayed at 0.73 ms
  with the new flare rule on and off alike). The reference scale reads the speed of a short burst, not preemption. Bots
  think about one tick in six, so the 99th percentile still lands on think ticks that were preempted.
- **Fix:** judge the 95th percentile (about 1.2 to 1.6 ms measured, budget 1.5 ms scaled), print the 99th and the worst
  tick without judging them, and say why in the test's header and the research page. Measure in alternation (rule on,
  off, on, off) before blaming a code change for a jump in a wall-clock number.
- **Check for next time:** a wall-clock budget on a shared machine is a statement about a typical tick (a percentile
  below the scheduler's share of ticks), never the single worst; pick the percentile after a few runs under load, and
  compare the median to tell the code from the machine.
- **Docs:** `docs/research/bots.md` in the game (the bots' own cost).
