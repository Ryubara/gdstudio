---
areas: [web, ci]
---
# A load gate set from 28 runs failed 8 of the next 181 healthy ones, and no divisor fixed it

2026-11-04

- **Saw:** the web job's night-load gate (night over the menu's load, limit 5.5) failed three pull requests in a row
  whose menu loaded in 7 to 9 s (the night over the menu rose with the night unchanged), after the first fix idea was
  to divide by something else (the idle menu frame).
- **Cause:** the term the gate divided by is one the game changes (a faster menu raises the quotient), and the
  calibration was 28 runs of one morning. Over 181 runs the same build's night varies 25 to 95 s (3.8 times) and none of
  the numbers a run records predicts it (log correlation with the night: menu 0.58, idle frame 0.51, the running night's
  frame time 0.71); replaying the gate with each as the divisor, at a limit that passes every run, fails the same share
  of a night made 1.5, 2 and 3 times longer. The old gate failed 8 healthy runs of the 181 and saw a x1.5 night in 43 %
  only by also failing healthy ones.
- **Fix:** before changing a divisor, download the artifacts of the last 100+ runs (`gh run download <id> -n
  web-smoke`), replay every candidate with `night_load.py --scale 1.5` (the night made 50 % longer) and count both
  failures at x1 and at x1.5, 2, 3: that shows what a time gate can see (here, a doubling), whatever it divides by.
  Pick a divisor that is steady (the menu's time floored at its median, 14 s) and a limit 10 % over the worst, and hold
  the smaller growth with a count the runner cannot move (the warm-up's frame count in `test_load_cost.gd`).
- **Docs:** deadnight `docs/research/web-export.md`, "The gate after a faster menu (#966)".
