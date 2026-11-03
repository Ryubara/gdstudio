---
areas: [tests, gameplay]
---
# Eight nights a cell cannot show a Kolmogorov distance under 0.2

2026-11-03

- **Saw:** with a bot tuned to the simulator's median (14 against 15), eight nights against 300 simulated ones still read
  a curve distance of 0.3 to 0.5, and the same code read 0.35 and 0.47 on two sets of seeds.
- **Cause:** the distance of two empirical curves has a noise floor of about 1.36 over the square root of the smaller
  sample (0.48 at eight nights, 0.14 at a hundred): a gate of 0.2 is below what eight nights can tell apart from the same
  curve.
- **Fix:** tune on the median and the shape read by eye (survival at a few rounds) with eight nights, and judge the 0.2
  gate only on the nightly run's hundred nights; say in the report which sample a number came from.
- **Docs:** the game's `docs/research/bots.md#phase-7-validation-at-scale-and-tuning`.
