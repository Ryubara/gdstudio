---
areas: [gameplay, tests]
---
# The start weapon one-tapped the first two rounds because no number stated its shots to kill

2026-11-03

- **Saw:** the maintainer on Deadnight found the revolver far too strong for the first rounds (one head shot killed on
  rounds 1 and 2), and asked for a lighter starter pistol that takes at least 3 head
  shots and 7 body shots on round 1.
- **Cause:** the start weapon did 24 with a head multiplier of 2.5 = 60 on a head hit, over a round-1 walker's 50 health
  and round 2's 58 (`RoundTuning.health_for_round`); the head zone had grown to half the figure (#694, #745), so a
  chest-aimed shot lands on it most of the time. Every number was reasonable alone (damage, multiplier, health), and
  no test or doc stated the shots to kill the start weapon should take, so nothing joined them.
- **Fix:** a feel target written as a table and tested through the real damage path: shots to kill per zone (head,
  body, limb) on rounds 1, 2, 5 and 10 for the start weapon (`test_starter_pistol.gd`: the House Pistol's 8 a hit,
  head x2.5, limb x0.85 gives 3 / 7 / 8 on round 1), and a test that no start-weapon hit kills a round 1 or 2 walker
  outright. Moving the start weapon touched about thirty tests that said `&"pistol"` for "the start weapon": they read
  `WeaponCatalog.START_WEAPON`, or the new id, where the start is meant.
- **Check next time:** when a weapon, a zone multiplier or the health curve changes, print the shots to kill per zone
  for the first rounds and compare them with the stated feel target; a game states, for its start weapon, how many hits
  round 1 takes. Aim tests at the zones the game fits, not the plain standing set: a body shot at chest height lands on
  the head.
- **Docs:** [Deadnight's weapons page, "The House Pistol and the hit zones"](https://github.com/Ryubara/deadnight/blob/main/docs/design/weapons.md).
