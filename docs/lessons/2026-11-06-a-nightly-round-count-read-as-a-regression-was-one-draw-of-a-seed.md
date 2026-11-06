---
areas: [tests, gameplay]
---
# A nightly's round count read as a regression was one draw of a spread of 9 to 19 rounds

2026-11-06

- **Saw:** Deadnight's 30 minute autopilot night reached round 13 with 169 kills on one dispatch, against 17 to 18 with
  268 to 270 on the two runs before (issue #1341). The page called it "the night itself changed" and named the weapon
  numbers and the automatic reload as the guess, because the step is fixed, the seed is fixed and the command is the
  same line in the workflow.
- **Cause:** the night is a fixed-step run but not a repeatable one (the same commit, seed and command twice at once
  gave round 17 and round 11; #1350), and with a seed fixed in the workflow every commit is a new draw of the same
  chaotic night. 20 seeds on each of three commits gave 15.4, 15.9 and 15.0 rounds with a spread (sd) of 3 rounds; the
  red night was one of 6 nights in 20 at round 13 or less on its own commit. The one fault in it, bots with a loaded ray
  gun that did not fire inside their splash, was a bot bug already fixed by the next commit and worth +1.7 rounds.
- **Fix:** compare a metric of a long night as a mean over many seeds with a paired interval (`autopilot_run.gd` takes
  `--seed=N`; 20 nights a commit see a change of about 2 rounds, 8 do not see one of 3), and look at the seconds a
  night stood still (the dead alive unchanged for 20 s or more) before blaming a number. A probe that prints who stands
  where each minute of a stall names the cause in one night. Never judge a commit by one night of the fixed seed.
- **Docs:** Deadnight `docs/research/performance.md`, "Why the autopilot night reached round 13 and not 17 (#1341)".
