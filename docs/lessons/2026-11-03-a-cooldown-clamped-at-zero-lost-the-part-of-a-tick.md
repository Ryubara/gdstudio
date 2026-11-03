---
areas: [gameplay, tests]
---
# A cooldown clamped at zero lost the part of a tick, so every weapon fired on whole ticks

2026-11-03

- **Saw:** measuring a faster-fire perk (x1.33) in Deadnight (#708): the Tommy gun gave 1.2 times its shots instead of
  1.33, and every gun fired below its nominal rate (SMG: 360 shots in 30 s at 60 Hz, nominal 400; with the perk 450,
  nominal 532).
- **Cause:** `WeaponState.tick` ran `cooldown = maxf(cooldown - delta, 0.0)` and `fire()` set `cooldown = interval`.
  A wait that ends part way through a tick throws the rest of the tick away, so each interval is rounded up to a
  whole number of ticks (4.5 ticks became 5, 4.06 became 5). The old test accepted it: its range started four shots
  under the paper rate, with the comment "a 60 Hz step lands a shot every fifth step".
- **Fix:** keep the leftover of the tick in which the cooldown ran out and take it off the next shot's wait, so the
  rate is exact on average. Two limits keep it honest: a weapon that was already ready keeps nothing (a pause banks no
  early shot), and the wait is never shorter than the tick (one shot a tick at most).
- **General:** a timer driven by a fixed step must carry its remainder (`t -= interval`, not `t = interval` after a
  clamp), or its rate is quantised to the step and a multiplier on it is quietly diluted. Test shots (or spawns,
  pulses) over a long run against the nominal rate for each definition, and never widen a range to fit what the
  code does; a comment explaining a loss in a test's tolerance is the cue.
- **Docs:** Deadnight `game/tests/weapons/test_weapon_fire_rate.gd`.
