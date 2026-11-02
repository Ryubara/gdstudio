---
areas: [tools, process]
---
# `gh pr view > file` outside a repository wiped a pull request description

2026-11-02

- **Saw:** after `gh pr edit --body-file`, the description held only the attached images and `pr-rules` refused it
  (missing every section, the `Model:` line).
- **Cause:** `gh pr view 537 --json body -q .body > body.md` ran in the scratch folder, which is not a repository:
  `gh` printed an error, the redirect left an empty file, a script "edited" the empty text and `gh pr edit` published it.
- **Fix:** run `gh` from the worktree (or pass `-R <owner/repo>`), check the saved file is not empty (`wc -c`) before
  editing it, and keep a copy of the body before replacing it. A `pr-rules` rerun reads the old event, so edit the
  description again rather than rerun the job.
- **Docs:** this lesson.
