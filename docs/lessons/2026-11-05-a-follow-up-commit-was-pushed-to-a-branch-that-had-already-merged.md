---
areas: [process, ci]
---
# A follow-up commit was pushed to a branch whose auto-merge had already landed

2026-11-05

- **Saw:** after opening a docs pull request with auto-merge on, a second commit (a lesson updated with a cause found
  later) was pushed to the same branch; the pull request had merged at its first commit, so the second never reached
  `main` and the stop hook named the branch.
- **Cause:** on a green docs-only pull request `--auto` merges within a minute, and the follow-up was pushed after
  that, without looking at the pull request's state first.
- **Fix:** a new branch from `origin/main`, the commit cherry-picked, a new pull request. Check for next time: before
  pushing to a branch that has a pull request, run `gh pr view <n> --json state`; when it is `MERGED`, branch from
  `origin/main` instead of pushing, and put every doc a task needs into the first pull request before turning
  auto-merge on.
- **Docs:** [Lessons](index.md): no page covers it yet; this file is the record.
