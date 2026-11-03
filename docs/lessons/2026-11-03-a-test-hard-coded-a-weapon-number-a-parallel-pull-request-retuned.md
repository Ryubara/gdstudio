---
areas: [tests, gameplay]
---
# A test hard-coded a catalogue weapon's magazine and a parallel pull request retuned it

2026-11-03

- **Saw:** Deadnight #730 went red on one case in 1978 (`test_bot_needs`, "a bot with a second gun that still has
  rounds is not empty": expected SHORT, got LOW) after main moved, though it was green on the branch before the merge.
- **Cause:** the test gave the shotgun a reserve of 4 and called that "under a magazine". #700 had turned the shotgun
  into a two-shell double-barrel, so 4 is two magazines. A test that bakes in a catalogue number is a bet that no other
  pull request retunes the catalogue.
- **Fix:** the case uses one spare round, under a magazine of any size the catalogue gives. Run `gds merge-main` and the
  suites you touch again just before opening, since the catalogue and the lot move under parallel pull requests.
- **Docs:** Deadnight `docs/research/bots.md`, "Needs against orders". Check: a test of a rule about "under a magazine"
  derives its numbers from the weapon's definition or uses the extreme (0 or 1), never a tuned value.
