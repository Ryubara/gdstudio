---
areas: [ci, tools]
---
# A pull request stacked on a hand-merged sync pull request conflicted once that one was squashed

2026-11-02

- **Saw:** Deadnight's rules change (#575) needed the checker that the open sync pull request (#571) brings, and the
  sync pull request waits for a maintainer (it changes `.claude/settings.json`). The rules branch merged the sync
  branch and went on. When the sync pull request was squash-merged, the rules branch showed `CONFLICTING` in
  `.github/scripts/groundwork.py` and `.claude/gds-sync.json`: the same content, but main has one new commit where the
  branch has the sync commits.
- **Cause:** a squash merge writes a commit that no branch contains, so git sees two unrelated edits of the same lines.
- **Fix:** merge main, take the stacked branch's side of the synced files (`git checkout --ours`), run `gds sync <game>`
  (it rewrites the hashes in `.claude/gds-sync.json`) and `gds sync --check`; commit the merge with the whole message
  from a file (`git commit --cleanup=strip -F`). Say in the description which pull request it is stacked on and that
  its diff shows that pull request's files until it merges.
- **Check:** before stacking on a pull request that a maintainer merges by hand, ask whether the work can start from
  main with only the files it needs; the kit's `gds sync` is idempotent, so re-running it on the new branch is cheaper
  than carrying the other branch.
- **Docs:** [Syncing the kit's files into a game](../studio/sync.md).
