---
areas: [gameplay, tests]
---
# A flank place nobody asked the walk about left a bot standing, and one seed's bar hid it

2026-11-04

- **Saw:** Deadnight #953: the follow share of `test_under_follow_the_bots_stay_with_the_person_who_gave_the_order`
  (seed 53, bar 0.9) read 0.925 on `main` and 0.895 once #923 moved a breaker post, so a PR that had nothing to do
  with bots was blocked. The issue guessed "a spot past the north fence"; the log showed the flank bot standing still
  5 s at a time, 13 to 19 m from the person.
- **Cause:** the flank's place was `project(centre)` (or the choke), cut to 11.5 m from the person and never put on the
  mesh again or asked "can I walk there?". It fell on the outskirts slab (the mesh has a patch there: the walk ends
  3 m short), or behind the breaker post (the mesh runs through it, so `BotPath.walkable` calls it walled): the goal
  was marked unreachable for 5 s and the bot stood. The same place was also chosen again at every think, so two valid
  places took turns, and 11.5 m plus the 1.5 m a bot "at" its place may be off was over the 12 m the test counts.
- **Fix:** take the first place `BotPath.probe` reaches (not blocked, not in a gap) among the choke and four named
  places, keep it until the people move 3 m, and make the farthest place the follow band's far edge (10 m). The
  errands' 2.5 m of "the walk may end short" let a place 1.5 m past the lot's edge through on #923's branch (the new
  test caught it); the flank asks for 0.5 m. Found by logging the bot's goal and path once a second, then dumping
  the raw path and the collider each segment hits.
- **Check:** every goal a bot is given comes from a place it asked the walk about (`probe`, or the `avoid` list of
  blocked goals) and is kept, not re-picked each think; a distance a role holds is checked against the band the test
  counts, with the stand-off of "arrived" added. A single-seed bar is compared by the mean over several seeds
  (the same commit and seed varied by 0.05 between runs).
- **Where:** Deadnight `docs/research/bots.md` ("A flank bot that stood still (#953)").
