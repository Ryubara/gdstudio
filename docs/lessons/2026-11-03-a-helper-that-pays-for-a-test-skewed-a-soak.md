---
areas: [tests, gameplay]
---
# A helper that grants the points to pay with skewed a bot soak's numbers

2026-11-03

- **Saw:** a soak of four bots on the second map with every link sold before the night reported one bot with 309,191
  points earned and the same bot buying nothing it needed: its table said "the whole map", but the run was one lone
  rich bot.
- **Cause:** `SeatedNight.open_door` buys a door for player 1 and, to be sure the buy goes through, first grants that
  player 100,000 points. Three links, three grants; the points stayed.
- **Fix:** the soak reads the points before the links are sold and puts them back after; the helper's comment now says
  what it grants. A helper that changes the state it is not about (points, health, the clock) is read before its numbers
  are trusted: print the player's points in the soak's first line.
- **Docs:** Deadnight's `docs/research/maps/small-map-play.md` (the bot nights on the second map).
