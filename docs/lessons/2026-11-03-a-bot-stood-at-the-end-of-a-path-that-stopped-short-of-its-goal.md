---
areas: [gameplay, tests]
---
# A roaming bot stood 92 s two metres from its place, and no detector saw it

2026-11-03

- **Saw:** the nightly soak's Roam cell: a bot with note `roam`, path status OK, a goal 2 m away, standing still for
  92 s across two rounds (13 s on another night). The stuck detector reported nothing (Deadnight #770).
- **Cause:** the walking mesh ended 2 m short of the place (the path may stop up to `BotPath.REACHED_SHORT` = 2.5 m
  short), the legs counted the bot as arrived at the end of its path (within the goal radius of the path's last point)
  and sent no motion, and the stuck ladder only judges a bot that is commanded to walk. The roam kept its place until
  the bot was within 1.5 m of it, which it could never be.
- **Fix:** the legs say when they stood at the end of a path short of the goal (`BotLegs.stopped_short_of`) and the
  roam takes that as arrival. A detector that needs a commanded speed cannot see a bot that was told to stand: a gate on
  "standing with a goal" (the soak's idle-under-Roam gate) is what found it.
- **Docs:** Deadnight `docs/research/bots.md`, "Idle bots and stalled rounds with a person (#770)".
