---
areas: [gameplay, tests]
---
# A new crane prize at any weight tipped the balance gate, which main passes at its edge

2026-11-03

- **Saw:** the dual pistols (Deadnight #789) in the prize crane failed `test_balance_targets`: the strong solo median 19
  against its 12 to 18, and the headliner's time to kill 30.2 to 30.6 s against 30. Three of my guesses did not move it:
  a weaker gun (20 to 18 to 17 a hit), a lower crane weight (3.5, 2.5, 1, 0.5 all read 19), the re-cut allowed or not.
- **Cause:** main sits at the gate's edge (5 / 10 / 15 / 16 / 18 / 18, measured on a detached checkout of `origin/main`),
  so any new prize reshuffles the seeded draws and one cell steps over. It is not the gun's strength: a pair a player never
  takes (it is worth under 1.5 times what it would replace) did it as well as a strong one. The roster research (#785)
  had predicted it, with `health_growth` 1.16 as the lever, which I measured trading the strong cell for the stampede
  (41% against 40%) and the headliner (31.3 s).
- **Fix:** none by me: a gate range or `health_growth` is the maintainer's to choose, so the pull request states it at
  the top and ships the numbers as they are. What did help was measuring a baseline from a separate checkout before the
  first edit and a probe script that prints the six medians for a list of variants (a few minutes under a loaded machine,
  never a full test run per guess).
- **Check next time:** a change to the crane pool, the shop or the carry runs `test_balance_targets.gd` before anything
  else is built on it, and a gate failure is read as "which cell and by how much" first: if the weight does not move
  it, stop tuning and ask.
- **Docs:** Deadnight `docs/design/weapons.md` (the pair's numbers) and `docs/research/weapon-roster.md` (#785).
