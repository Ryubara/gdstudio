---
areas: [audio, process]
---
# A baseline was measured before main changed the sounds under it

2026-11-03

- **Saw:** two sets of headroom measurements (about 40 minutes each) were made on a tree that did not have the reload
  rework and the double-barrel shotgun that landed on `main` meanwhile; after the merge the harness lifted a teammate's
  reload steps a second time, the shotgun was a different gun, and the results had to be redone (Deadnight #718).
- **Cause:** the measurement was started before merging `main`, on a task whose subject (the guns' and reloads' levels)
  other open pull requests were changing.
- **Fix:** merge `main` (`gds merge-main`) before the first measurement of a mix, and again before the one that goes
  into the pull request; keep a second worktree on `origin/main` for the "before" runs so both sides come from the same
  base; give a harness no copy of a level a game script now sets itself.
- **Docs:** [Audio](../engines/godot/audio.md#headroom-without-a-limiter).
