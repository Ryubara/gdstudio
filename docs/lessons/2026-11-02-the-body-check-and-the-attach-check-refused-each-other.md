---
areas: [tools, process]
---
# The body check and the attach check refused each other on a visual pull request

2026-11-02

- **Saw:** Deadnight #586: `gh pr create --attach` was refused twice. With `![x](./file.png)` on the Before:/After:
  lines the attach guard passed, but the body guard (`gds pr check-body`, #168) refused the same body: "the 'Before:'
  capture is missing", because it only counts uploaded `github.com/user-attachments` links, and the uploads do not
  exist until the command runs. Posting the images as an issue comment is blocked by the no-comment-as-user hook.
- **Cause:** the two guards (#159 and #168) were written separately; the body check does not know the images of
  `--attach` are about to become the uploads.
- **Fix (workaround):** open the pull request with a `Screenshots: none (reason)` line plus the `./file` references
  (the body check accepts the `none` line, the attach check sees the references), then read the body back, move the
  appended upload links onto the `Before:` and `After:` bullets, check it with `gds pr check-body`, and `gh pr edit
  --body-file`. The real fix is in the kit: `check_body` in `.claude/hooks/guards.py` should treat a `./<file>`
  reference to a file named by `--attach` as an upload.
- **Docs:** [Capture](../capture.md#attaching).
