---
areas: [tests, process]
---
# A scene was regenerated under running suites, again

2026-11-04

- **Saw:** two Deadnight suites failed with "the way ends 8.6 m from the hall" for every window, in a run of
  `tests/world` that had started before I moved two filing cabinets in the generator, wrote the scene again and baked
  the walking meshes (#994). Run again on the commit, they passed. The #917 rework had made the same mistake (a scene
  swapped in for a baseline under two runs).
- **Cause:** the suites read the scene and the baked meshes from the worktree as each suite starts; a run that began on
  one scene finished on another, and meshes baked for the new scene met tests that had loaded the old one.
- **Fix:** both runs were stopped by their process ids (found by the run's own `timeout` value in the command line),
  the change committed, and every suite run again on the commit.
- **Check for next time:** commit, then start the long suites; while they run, change nothing they read (the
  generator's output, the meshes, the tests). To keep working meanwhile, run them in a detached checkout of the commit
  (`git worktree add --detach <dir> <sha>`, one `--import`), never in the worktree being edited.
