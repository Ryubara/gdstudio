---
areas: [gameplay, tests]
---
# A shopping bot walked to spots behind shut doors, and had no break to shop in

2026-11-02

- **Saw:** Deadnight #228 (bot shopping). The errand tests passed, and the first soak of four bots still bought almost
  nothing in six game minutes: bots stood at a locker or a door for a minute with `unreach` climbing and points unspent.
  A second soak had a round that never ended (six of the dead stood at the concession door), so no bot ever shopped.
- **Cause:** three assumptions from a page written before the lot was built. (1) The shop spots, breaker posts and fuel
  crates behind a shut door are on no walking mesh until the door is bought; a chooser that picks "the nearest spot"
  picks one the bot cannot reach, the legs mark it unreachable for 5 s, and the chooser picks it again. (2) The page said
  "buy in a break", and the break is 5 s (the maintainer shortened it from 20 s): a walk to a spot is longer, so the
  shopping starved. (3) A rule that waits for the round to clear waits forever when a few dead stand where no one goes.
- **Fix:** the bot remembers a stand it found no way to until a door opens (the mesh changes then) and the chooser skips
  it; a lull is a break, a round with five (or a quarter of its dead) left, or ten seconds without a sight or a sound of
  the dead, and the threat gate (nothing within 12 m) is what keeps a bot out of a fight; the soak takes a handful of
  stragglers off the lot after 90 s (the stand-in for a person who would go and shoot them: #591). The test helper that
  gave a bot points with `grant_points` could not take them back (a negative grant is refused, so a bot that had bought
  doors with 100000 points kept them): tests set `players[id].points` outright.
- **Check for next time:** before a bot rule says "go to X", ask the navigation server whether X is reachable with the
  doors as they are now (the field, the first door, all doors) and run the rule in a soak before trusting the unit tests;
  read every phase length from the tuning, never from a design page; a test that opens a door waits for the mesh
  (`SeatedNight.settle`) before it sends a bot through it.
- **Docs:** the game's `docs/research/bots.md` (phase 4, Built) and the open mesh finding #590.
