---
areas: [tests, gameplay]
---
# Three new shop spots changed the seeded walk of two bot tests that passed on main

2026-11-03

- **Saw:** after adding three wall spots to the maps (Deadnight #793), `test_bot_orders_night` ("roam: still 0.7 m
  from the door") and `test_smallmap_bot_night` (the solo bot bought no weapon in 240 s, with 4,000 points unspent)
  failed; each passed on a detached checkout of `origin/main`, and each passed with any one of the three spots.
- **Cause:** a roaming bot picks its next place among the shop spots and the doors' stands (`LotBotData.roam_spots`),
  and the seeded streams are consumed per choice, so any new spot moves every seeded walk. The two tests judged
  where a bot stands at one moment, or whether it had bought by a fixed time: both are outcomes of one seed.
- **Fix:** judge a roaming bot by how far it went over the time (the farthest distance from the door), and give the
  solo night the minutes a late first purchase needs; do not change a seed to find one that passes. The solo bot's
  4,000 unspent points (it saves for the re-cut and shops past nothing) is a behaviour worth its own issue.
- **Check next time:** before adding a shop spot, a door or a fixture the bots walk to, run `tests/bots`,
  `tests/night` and `tests/world/smallmap` on a branch with and without it.
- **Docs:** none yet.
