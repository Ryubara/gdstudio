---
areas: [gameplay, tests]
---
# A purchase that now takes 2.5 s left the balance simulator buying past it, and a 60-night gap moved by chance

2026-11-03

- **Saw:** Deadnight #912 (a perk is drunk for 2.5 s before it is had, and the counter refuses any purchase from a
  player with a bottle in hand) turned CI red on `test_the_same_climb_goes_less_far_when_the_re_cut_and_the_tonic_do_nothing`:
  `average:4: 14.27 rounds without the re-cut and the tonic, 14.77 with` (the gap had been 0.82 on `main`).
- **Cause:** two things. The simulator's `_shop` bought a tonic and then the next item in the same instant; the rules
  now answered `DRINKING` and the purchase silently did not happen. And the test compares two means of 60 seeded nights:
  any change that shifts the random draws moves each mean by a few tenths, so a gap checked against 0.5 moved with it.
  Over 300 nights the gap is 0.72 on `main` and 0.66 with the drink, 1.22 and 1.06 for eight players: the upgrade
  carries the climb as before.
- **Fix:** the simulator drinks the tonic down in the break before it buys again (`NightSim._drink_out`, as the crane
  already ticks the rules), and a cell of the climb test that misses at 60 nights is read again at 300 nights. The
  threshold was not moved.
- **Check for next time:** when the rules gain a state that blocks purchases, read what the simulator and the bots do
  when a purchase is refused (a refused buy is `0`, not an error). When a gate that compares two means turns red by a
  few tenths after an unrelated change, measure it with 300 nights on `main` and on the branch before touching the
  threshold or the tuning.
- **Docs:** the game's `docs/design/rounds.md` (balance gate).
