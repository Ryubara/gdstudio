---
areas: [gameplay, tests]
---
# A soak gate counted the walk home from an allowed trip as leaving the spot

2026-11-03

- **Saw:** under the Hold order 6 of 9 bots in a night held the spot under 92% of the time, and a fix to the brain
  moved the number by a point or two.
- **Cause:** the gate (within 3 m of the spot for 92% of the time under the stance, "not on a trip for a revive, a ping,
  a dodge or an errand") was measured from the bot's note: a walk home carries the stance's note (`hold_order`), so every
  trip for rounds, a revive or a retreat was counted twice, once as the trip and once as time off the spot. Most of the
  off-spot time in the soak was those walks (a bot with only a pistol goes for rounds eight times a night), and the rest
  was a boss keep-off that had no distance limit.
- **Fix:** the watch holds a trip from the first note that is not the stance until the bot is back in the gate's
  metres, counts it apart (time away, longest trip, a gate on the longest) and keeps the old figure beside the new
  one, so a report can show both. Before changing a bot to move a gate, add to the report why the gate broke (what the
  bot was doing and what it had last done), as the soak's `off_after` does.
- **Docs:** [Hold and a boss](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md#hold-and-a-boss-769).
