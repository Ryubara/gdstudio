---
areas: [process, tests]
---
# A pull request body claimed uploaded screenshots that were still local paths

2026-11-02

- **Saw:** `pr-rules` failed with "the Before: capture is missing"; the body held `![x](./x.png)` and the report said
  the captures were uploaded.
- **Cause:** `gh pr create --attach` appended the uploads at the end of the body instead of swapping the references in
  `## Screenshots`, and the check of "uploaded" was a grep count that matched the appended copies, not a read of the
  Screenshots lines.
- **Fix:** read the body back (`gh pr view N --json body -q .body`) and look at the Before and After lines for
  `github.com/user-attachments` URLs; if they are still `./` paths, `gh pr edit N --body-file <body> --attach <png>`
  (from the folder holding the files), then delete the appended copies after `## AI use`.
- **Docs:** [Hooks: attach](../studio/hooks.md).
