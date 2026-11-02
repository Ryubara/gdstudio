---
areas: [gameplay, tests]
---
# A carry limit broke the balance simulator and every test that assumed all weapons were held

2026-11-02

- **Saw:** with a two-weapon carry (Deadnight #410) the balance gate failed ("median round average:1 is 8, wanted 10 to
  14") and about fifty tests failed, among them crane tests that expected a player to win every prize.
- **Cause:** the simulator's players bought every weapon on offer and kept all of them, so with a limit they bought the
  same weapon again and again (79 shotguns in 60 nights, replacing what they had just bought) and wasted their points.
  The tests had been written when a player carried everything, so they took "owns the weapon" and "the crane runs dry"
  as facts of the game.
- **Fix:** model the rule in the simulator with a margin (a weapon replaces the weakest only when it is worth 1.5 times
  more; the crane is played only when a prize would qualify), then retune only what the gate named (the stampede count).
  Rework the tests to the rule rather than loosening them, and add a rule test, a combat test and a night test that
  play it. Before changing a limit on what players hold, grep the tests and the simulator for "carried", "owned" and
  pool-size assumptions.
- **Docs:** [the balance simulator, the two-weapon carry](https://github.com/Ryubara/deadnight/blob/main/docs/research/balance-simulator.md).
