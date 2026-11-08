---
areas: [gameplay, tests]
---
# Four bots and a person jammed in the same corridors

2026-11-02

- **Saw:** with the follow logic in (Deadnight #226) a four-bot soak had bots stuck 6 to 16% of their walking time,
  almost all of it against another player; `body.get_slide_collision()` named a `CharacterBody3D` (a bot or the person),
  not the lot.
- **Cause:** players collide with each other, all the bots chase the same person along the same corridors, and two with
  the same best place pile onto it. Pushing every neighbour away made it worse (two bots stepping the same way).
- **Fix:** (1) the bots of one team take slots in a fan behind the person, by seat order, and rate a place by where the
  other bots will be in a second; (2) a look-ahead for a meeting (closest approach under 1.1 m inside 1.5 s) in which
  a person never gives way and, of two bots, the higher seat does, to the right, slowing near; (3) a standing bot steps
  out of the way of a player who walks at it. Stuck time fell from 6 to 16% to about 1 to 3%. Classify each stuck
  episode by what the body ran into (the soak report has `stuck_causes`) before tuning.
- **Docs:** Deadnight `docs/research/bots.md` (Built in phase 2); [Navigation in tests](../engines/godot/navigation-in-tests.md).
