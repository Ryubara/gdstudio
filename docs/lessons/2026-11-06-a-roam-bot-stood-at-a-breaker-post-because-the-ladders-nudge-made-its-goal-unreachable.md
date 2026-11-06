---
areas: [gameplay, tests]
---
# A Roam bot stood for minutes at a breaker post: the ladder's nudge made its goal unreachable and it let go

2026-11-06

- **Saw:** the nightly soak's `idle under Roam over 8 s` broke in 4-bot rooms of every profile, 16 of the 19 stands at
  one spot, `(4.8, 21.4)`, note `roam`, a goal of `(12.5, 0.4, 31.6)`, `stuck` false, for 8.7 to 46.6 s. A lone bot set
  down at the spot walked to the goal in 7 s, so the first reading was "something a night adds is in the way".
- **Cause:** nothing a night adds. The walk from the west of the lot to that stand follows the booth's north wall round
  its corner, and the `booth` breaker post (a `StaticBody3D`, not CSG, so not in the baked walking mesh) stands on the
  line: the bot walks into its west face and stops. The ladder climbs; its second rung repaths to the goal moved by up
  to 1.5 m, which can lie behind the boards of the barricade (`BotPath.walkable`: unreachable). A goal called
  unreachable gives the legs no direction, so the bot is "not commanded to walk", `BotStuck` ends the episode and the
  ladder is gone; the mark of the unreachable goal sits on the moved goal's 2 m cell, not on the roam's place, so
  `BotRoam` keeps the place for good. Also misread: the sample's `path: 4` is `BotPath.Status.UNREACHABLE`, not four
  points (the path was empty).
- **Fix:** `BotLegs._ask_path` takes the nudge back when it makes the goal unreachable and asks for the goal itself
  (the real goal, if it is unreachable, is then marked on its own cell and the roam drops it). `test_bot_legs.gd` (the
  hall with boards across it, a seed whose jitter lands behind them) and `test_bot_breaker_post.gd` (the lot: 13 of 16
  bot seeds stood 22.4 s at `(4.849, 21.45)` before, none after).
- **Check for next time:** a field of a sample that is an enum prints as a number: look the enum up before reading it as
  a count. A reproduction starts the bot where the sample's bot *came from* (the approach line), not where it stood:
  the spot was the end of a walk that hugged a corner. A recovery that moves a goal must prove the moved goal is still
  reachable, and any state in which the bot is not commanded to walk is invisible to the stuck detector.
- **Docs:** Deadnight's `docs/research/bots.md` ("A Roam bot held at the breaker post (#1325)").
