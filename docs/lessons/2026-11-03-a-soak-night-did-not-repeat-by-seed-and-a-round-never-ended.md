---
areas: [tests, gameplay]
---
# A stalled soak round could not be replayed by its seed, and the cause was not a bot

2026-11-03

- **Saw:** 3 of 16 Follow and Roam nights with a person ended by the soak's "round of eight minutes" stop, with one
  walker (or two headliners) alive; replaying the same seed ran to the round cap (Deadnight #770).
- **Cause:** a night depends on the machine: the navigation bake finishes on a physics frame, so the same seed is not the
  same night. The stalls were of two kinds, neither a bug in the bots' fighting: a zombie in a pocket of the walking
  mesh (the strip behind the screen; how it got in is not proved), standing at the end of a path with two points for
  eight minutes; and two headliners kiting a person with a dry gun while the bots roamed 40 to 100 m away, because the
  last three zombies are outlined through the walls for a person (`ZombieMarks`) and nothing told the bots.
- **Fix:** read the cause from the evidence of whichever nights break, not from a seed: the soak prints one line every few
  seconds of a long round (`--tail=SECONDS`: where each zombie is, its mode, its target and path, and what each player
  holds and does). The sim says a zombie with no way to a target 12 m or more away is stranded after 12 s and the
  director puts it back on a spawn point (`ZombieSim.relocate`); the bots read the same marks a person sees
  (`BotHunt`) and the nearest free one goes to look. A feature a person has through the screen (an outline, a marker)
  is a feature the bots need through their beliefs, or the soak finds the round where only people can win.
- **Docs:** Deadnight `docs/research/bots.md`, "Idle bots and stalled rounds with a person (#770)".
