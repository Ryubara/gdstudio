---
areas: [ci, tools]
---
# A merge committed after conflicts lost its Co-Authored-By trailer

2026-11-02

- **Saw:** Deadnight #503 went DIRTY and an agent merged `origin/main` into it, fixed one conflict and ran
  `git commit --no-edit`. `pr-rules` then failed on the merge commit: the `noreply@anthropic.com` address was "outside
  the `Co-Authored-By` trailer".
- **Cause:** a merge with conflicts leaves a `# Conflicts:` list in `MERGE_MSG`, and `--no-edit` commits it after the
  message that `git merge -m` had set. The message then ends with a paragraph of conflict lines, so the
  `Co-Authored-By` line is no longer in the last paragraph, and a trailer is only the last paragraph. The address
  there reads as a second address in the body. A merge without conflicts commits at once and has no such list, so the
  mistake shows only the first time main conflicts.
- **Fix:** commit the merge with the whole message from a file or heredoc, and nothing after the trailer:
  `git commit --cleanup=strip -F <message>`, a message that ends with the single `Co-Authored-By: <model> <address>`
  line. Check it before pushing with `git log -1 --format=%B`: the trailer is the last line. Rewording a pushed commit
  needs a force push, which is the maintainer's, so the fix then is a new branch and a new pull request carrying the
  clean commit (#503 became #531).
- **Docs:** [Merging main into a pull request](../starting-work.md#merging-main-into-a-pull-request).
