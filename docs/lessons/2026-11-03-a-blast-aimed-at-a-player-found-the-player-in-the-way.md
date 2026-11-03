---
areas: [gameplay, tests]
---
# A blast aimed at a player found the player's own body in the way, and a bot walked into its own grenade

2026-11-03

- **Saw:** with grenades hurting players (Deadnight #805), a two-client test put a teammate 2 m from a blast that downed
  the holder and the teammate stayed at full health. A soak of three bots then showed a bot at 0.63 of its health from
  its own grenade, 2.4 m from a blast it had planned 7.5 m away.
- **Cause:** (1) the cover line from the blast to a player's chest was cast with the shots' probe, which also meets the
  bodies of players, so the ray stopped on the target's own capsule and "a wall" stood in front of everyone (the old
  40% thrower share only worked because the thrower stood outside their own body). (2) the bot's throw checked where
  the grenade would land, never where the bot would be: it walked on toward the fight during the three seconds of fuse
  and into the blast.
- **Fix:** the grenade's cover ray is the probe's `static_callable()` (walls and props, a person is no cover). A bot
  tells the team where its grenade will land (`BotTeam.add_blast`) and every bot steps out of that spot's reach, with a
  margin, until it goes off. Both are held by tests: a real-socket two-client test with a teammate beside the holder,
  and a soak that measures every bot blast against where every player stood, from the bodies.
- **Docs:** [Grenades research: Blast on players](https://github.com/Ryubara/deadnight/blob/main/docs/research/grenades.md#blast-on-players-805).
  Check for next time: a rule that hurts a player needs a test with a second player beside the source, and a rule a bot
  uses to choose a place needs a soak that measures the result, not only the choice.
