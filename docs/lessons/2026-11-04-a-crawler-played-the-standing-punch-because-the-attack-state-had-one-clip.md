---
areas: [gameplay, godot]
---
# A crawler stood up to attack because the attack state was one clip for every body

2026-11-04

- **Saw:** "The zombie crawlers attack makes them stand up to attack" (Deadnight #971). A crawler that reached the player
  rose from the floor to a walker's height (the mesh's top went from 0.85 to 1.84 m) and dropped again.
- **Cause:** the view chose its animation state by mode, and only the move state had a crawl branch: `_enter(ATTACK)` sent
  every look but the boss to the one `attack` state, which was the standing `Punch`. The simulation was look-blind the same
  way (one reach, one windup for every zombie), and the crawler's hit set was fitted to the `Punch` too, so the zones also
  stood up. A crippled body (a walker whose legs went) is a second body with its own set of actions; nothing listed them.
- **Fix:** a clip of its own for the crawler (`Crawl_Attack`, built from the Crawl's first frame so it never leaves the
  crawl's height), a state for it chosen by `ZombieModels.crawls(look)`, per-type `reach` and `telegraph_seconds` as data,
  the hit set refitted to the new clip, and a test through the real night that the body's highest bone in the attack stays
  within the crawl's.
- **Check:** for every body state a character can be in (standing, crawling, downed, climbing), list every action it
  can take (attack, stagger, die, tear, emerge) and which clip, hit set and reach each one uses; an action that is one
  clip for all bodies is a bug waiting for the first body that cannot stand. The test measures the body's height
  through the real path while the action plays, not the clip alone.
- **Where:** [AnimationTree](../engines/godot/animation-tree.md#one-action-state-for-every-body).
