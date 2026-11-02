---
areas: [tests, gameplay]
---
# A Tween never advanced in a test that steps the game by hand

2026-11-01

- **Saw:** a prop that slides to a new place with a `Tween` was still at the old place after the test had stepped
  the night for many simulated seconds.
- **Cause:** a Tween runs on idle frames. A suite that calls the night's `tick()` by hand never renders a frame, so
  no Tween time passes, however many ticks it runs.
- **Fix:** animate from the step the view is given (count `delta` per frame event, as the prize crane's `CraneView`
  does), not with a Tween, when a test must be able to step the motion. Keep Tweens for things no test steps.
- **Docs:** [the Mystery Box page of Deadnight](https://github.com/Ryubara/deadnight) (`docs/research/mystery-box.md`);
  the rule is the one in the Testing section of the repository's `AGENTS.md`: no real time.
