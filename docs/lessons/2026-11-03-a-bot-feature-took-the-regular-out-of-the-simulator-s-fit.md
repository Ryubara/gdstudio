---
areas: [gameplay, tests]
---
# A bot feature that played better than the model took the Regular out of its fit

2026-11-03

- **Saw:** after the play states (a hurt bot goes Careful, then Safe, and backs away) landed, four of eight Regular nights
  reached the round cap and the median was 19 against the simulator's 15 (Kolmogorov distance 0.85 alone); the Rookie had
  gone the same way a day earlier (30 boss nights passed of 30 against the level's 40%).
- **Cause:** the simulator's levels are a few numbers (accuracy, dodge, read) and no player manages health, so a bot
  skill that was fitted to them stops matching the moment it gains a behaviour the model has no number for. The fit was
  read once, at the profile's first tuning, and never again after the feature.
- **Fix:** the profile that is meant to match the model does not get the behaviour (`careful_below` and `safe_below` 0
  for the Regular, as for the Rookie): the median came to 14, 17 and 16 for one, two and four bots against 15, 15 and 17.
  The behaviour stays the Veteran's. Run the parity soak (`soak_report.py run --tune name:number`, no edit between runs)
  after every bot feature that changes how long a bot lives, and tune with one field at a time on the same seeds.
- **Docs:** the game's `docs/research/bots.md#phase-7-validation-at-scale-and-tuning`.
