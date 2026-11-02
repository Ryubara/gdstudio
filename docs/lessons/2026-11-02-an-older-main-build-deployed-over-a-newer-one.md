---
areas: [ci, backend]
---
# An older main build deployed over a newer one on Railway

2026-11-02

- **Saw:** the web service showed `main 85325be` (#507) live at 08:05:05Z, then `main 7c12a41` (#525, one merge
  earlier) deploying at 08:06:21Z: the live game went back to before the hand grips (Deadnight #552). The same lag had
  made a fix report (#478) be played on a build without the fix.
- **Cause:** a deploy job deploys the commit its own run was built from, and the runs of two quick merges finish their
  tests in any order. A `concurrency` group on the deploy job serializes the deploys; it never orders them, so the run
  of the older merge still goes second.
- **Fix:** the deploy job asks, when it starts (after the wait in its group), whether its commit is still the head of
  `main` (`gh api repos/$GITHUB_REPOSITORY/commits/main --jq .sha`), and skips with a notice when it is not; the run of
  the head deploys itself. Give every deploy job its own group (the game server had none), and test the check with the
  head injected, so the refusal of an older commit fails first without GitHub.
- **Check:** for any job that publishes "the latest" of something, ask "what if a run of an older commit gets here
  last". Do not rely on the group alone; compare the run's commit with the head at the moment of publishing.
- **Docs:** Deadnight `docs/research/web-export.md` ("The deployed build is the head of main"),
  [Web and server deployed minutes apart](2026-11-02-web-and-server-deployed-minutes-apart.md).
