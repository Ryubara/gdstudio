---
areas: [ci, tests, process]
---
# Pull requests that passed alone turned main red together

2026-11-04

- **Saw:** Deadnight's `ci` on `main` was red for seven merges in a row (#958 to #963), each merge adding failures: the
  weapon-source tests (offline and over a socket), the autopilot's machine test, the second map's use-zone sweep and a
  small-map bot night. Every one of those pull requests had a green `ci` on its own branch.
- **Cause:** the checks ran on each branch with the `main` it was cut from, so a test added by one pull request never ran
  against the code of another that landed first.
    - **A test met a rule it did not know:** #954's weapon-source tests press use the tick after a teleport with full
      hands; #958 (merged before it) made a purchase that throws a carried weapon away wait until its card has been up
      0.4 s. #958 fixed the tests it knew of; #954's were not on its branch.
    - **A list of keys that include coordinates:** #958's sweep lists the second map's overlapping pairs by name and
      position (`weapon_smg (3.6, 0.0, -6.4) | ...`); #964 moved the map, so 19 entries were stale and 5 new overlaps had
      no entry. #964's branch did not have the test.
    - **A test that passed by luck:** the autopilot's machine test passed for months because its bot happened not to buy
      the far doors first; a later change in the purse and the timing flipped it, and it uncovered three real faults
      (a bot stuck on a boarded fence breach, a re-cut press with nothing to cap it once the price stopped growing, a
      tonic bought at the wrong machine).
    - **A platform difference on top:** a small-map bot night failed on the Linux runner (the solo bot died in round 3 on
      one seed) and passed on Windows on every seed tried. It reproduced only on the pinned Linux Godot run in WSL, on
      `main`'s exact map; any nudge to the map moved the night, so no one change "fixed" it.
- **Fix:**
    - Before auto-merge on a branch that is behind, `gds merge-main`, then run **the tests that other merges added or
      changed since the branch's base**: `git diff --name-only <base>..origin/main -- 'game/tests/**/test_*.gd'`, plus
      the branch's own. A test file that is new on `main` is the one most likely to disagree with the branch's code.
    - A list of known failures keyed by data that moves (names with coordinates) is rewritten by the pull request that
      moves the data, in the same pull request; a pull request that changes a map runs the map's sweeps.
    - Reproduce a red `main` where it ran: the pinned Godot for Linux runs in WSL from a copy of the project (the
      shard's folders from `tools/ci_test_shards.py`), which told a Windows-only pass from a real fix.
    - Test one thing at a time: the bisect of a red test is `git checkout` of the merges between the last green run and
      the first red one, one `--import` and one test each.
- **Docs:** [Starting work](../starting-work.md); the game's `docs/research/use-reach.md` for the rule that broke the
  weapon-source tests.
