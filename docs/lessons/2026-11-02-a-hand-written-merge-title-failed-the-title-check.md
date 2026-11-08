---
areas: [ci, tools]
---
# A hand-written merge title failed the commit title hook

2026-11-02

- **Saw:** `git commit -F <file>` for a merge, with the title `ui: Merge main into fix-pad-pause`, stopped at the
  hook "commit title follows the conventions" (the verb `Merge` is not on the list), so the merge stayed uncommitted
  and a later `git log` still showed the old head.
- **Cause:** only the title git writes itself (`Merge remote-tracking branch ...`) is exempt; an area prefix plus
  `Merge` is not a title the convention knows. The hook's output ended in a list of skipped checks, so the one
  `Failed` line was easy to miss.
- **Fix:** after `git merge --no-commit`, commit with a message file whose title is
  `Merge remote-tracking branch 'origin/main' into <branch>` and whose last line is the `Co-Authored-By` trailer
  (`git commit -F <file> --cleanup=strip`), then check `git log -1` shows the merge before pushing. A merge that brings
  in a commit by another model also needs that model in the pull request's `Model:` line.
- **Docs:** [Merging main into a pull request](../studio/starting-work.md#merging-main-into-a-pull-request).
