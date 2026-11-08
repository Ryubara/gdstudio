---
areas: [gameplay, process]
---
# A teammate bot answered a person's pings and had no needs of its own to rank against orders

2026-11-03

- **Saw:** the maintainer asked that bots fetch their own ammo, weighed against the player's orders such as Follow
  (Deadnight #692). A bot with an empty gun and nobody pinging
  kept fighting empty under Hold; under Follow it would have walked off to any locker; the "nearest" locker was the
  nearest by the straight line, through a fence.
- **Cause:** #647/#670 were specified from what a person can send (one more row of the ping table), so the work was
  organised by inputs. The bot's own wants were a line of a shopping list with no idea of a need and nothing to rank it
  against, and when the standing orders (#641) arrived nobody asked what an order does to a want. The issue text itself
  was half wrong (the shop already bought rounds in a lull); the real gap was the missing arbitration.
- **Fix:** one table of need by order (`BotNeeds.RULES`: go / near / say per cell), tested cell by cell, with the
  trip chosen by walk length; the brain has no branch for it, so the next need (health stances, #693) is a new key.
- **Docs:** Deadnight `docs/research/bots.md`, "Needs against orders". Check: when an AI teammate is given a response
  to a player input, list its own needs first, and write the needs-against-orders table in the same pull request.
