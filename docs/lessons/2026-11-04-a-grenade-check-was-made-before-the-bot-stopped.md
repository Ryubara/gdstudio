---
areas: [gameplay, tests]
---
# A bot checked its throw from where it ordered it, and a soak that "was fixed" failed again on CI

2026-11-04

- **Saw:** `test_bot_grenade_soak.gd` failed on main's CI on seed 11 (0.830, then 0.255 of the thrower's health, limit
  0.1) after #872 had fixed the bots hurting themselves; locally the same code passed, with a different number of
  blasts every run. The issue guessed a regression and listed six merges to bisect.
- **Cause:** not a merge. The night is not repeatable to the blast (a millionth of a metre apart by tick 90, so every
  run and every machine plays another night), and #872's own notes had counted a leftover "grenade hit a wall 0.7 m
  from the thrower" in 24 nights. A probe printing, per throw, the bot's place at the order and at the release showed it:
  the bot orders a throw while it walks and slides 0.3 to 1 m before it stands, and the arc (six chords of one ray) was
  checked from the order's place, so a lamp post a hand's breadth from the line was missed and the grenade fell at the
  bot's feet.
- **Fix:** plan the throw from where the bot will stand (`BotGrenadier.stop_point`) and keep strips 0.3 m either side
  of the arc clear as far out as a blast reaches the bot. When a test that "passes locally" fails in CI, first ask
  whether its number is repeatable (run it twice, with the per-tick state hash); if not, do not bisect, read one
  failing case in detail with a probe over 20 or more nights, and compare the check with what really happened.
- **Docs:** Deadnight `docs/research/grenades.md`, "The grenade that hit a post at the bot's feet (#1019)".
