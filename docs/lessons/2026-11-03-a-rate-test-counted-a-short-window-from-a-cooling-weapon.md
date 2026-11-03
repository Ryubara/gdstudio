---
areas: [gameplay, tests]
---
# A rate test counted a two-second window from a weapon that was still cooling

2026-11-03

- **Saw:** after merging main into the cooldown-carry fix (Deadnight #734), `test_faster_fire_shoots_more_often_through_the_real_trigger`
  failed: ratio 1.125, wanted over 1.2. I had run the weapon suites but not the perk suite that main had just added.
- **Cause:** the perk was fine (a held trigger from a ready weapon gives 8 shots plain and 10 with the perk). The test ran
  the two rounds back to back, so round two began while round one's last shot was still cooling, and a 2 s window held
  only 8 to 10 shots, so one lost shot was an eighth. The carry made the plain count exact, which exposed it.
- **Fix:** start each round with `cooldown` and `carry` at 0 and run 5 s. Before a merge, run every suite that touches
  the changed class (`grep -l WeaponState tests`), not only the folder of the change.
- **Check:** a test of a rate resets the state it carries between rounds and counts enough events that one is a few
  percent of the total.
