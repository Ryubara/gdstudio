---
areas: [gameplay, tests]
---
# A Follow bot ran 30 to 90 m from the person because the pull toward them was one number against a sum of pushes

2026-11-03

- **Saw:** the Follow soak with a person (Deadnight #784) broke "a bot beyond 25 m of the person for 20 s outside an
  errand" in about one night in ten: a bot at 30 to 90 m, running at 7 m/s, not stuck, note `retreat` and `fight` in
  turn, six to twenty-four dead within 12 m of it.
- **Cause:** a retreat picks one of twelve headings; the steering adds up what each of the eight nearest dead pushes,
  and the pull toward the person was a flat `HOME_BEND` of 0.9. With a pack on the bot's heels the sum is ten to
  thirty and the pull never decides anything, so the bot ran straight away from the pack for minutes, which is the
  way away from the person whenever the pack stands between. A probe of the steering showed a flat pull of 8 still
  ran straight away from eight dead; it takes 15 to 30. Two reading mistakes cost time: the first far-bot lines were
  taken for the gate's cases though the stand-in was down (the gate counts persons on their feet), and the catch-up
  run after a far errand looked like a stray (`follow` at 7 m/s for 7 to 9 s is inside the gate's 20 s).
- **Fix:** the retreat's pull grows with the distance from the person, from 16 m to 36 m, to 4 for each dead felt
  (`BotFightBrain.far_bend`); the steering's rule that a heading may not close on the dead stays the guard, so the
  pull only turns the flight round the pack. A steering test sends eight dead between the bot and a person 30 m off
  and expects the far pull to go round (it failed first with the flat number). The soak report counts `far_seconds`
  per bot and `--watch=far` prints a line a second for each bot far from a person who is up.
- **Check for next time:** a pull added to a weighted sum is tested against the biggest push it will meet (a crowd,
  not one zombie), and its weight scales with that sum. A watch for a gate is filtered by the gate's own conditions
  (person up, not on an errand) before its lines are read.
- **Docs:** Deadnight `docs/research/bots.md`, "A Follow bot far from the person (#784)".
