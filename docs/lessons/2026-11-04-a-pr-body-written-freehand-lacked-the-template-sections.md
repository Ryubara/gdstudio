---
areas: [process, ci]
---
# A kit pull request body written freehand lacked the template sections and `body` failed

2026-11-04

- **Saw:** kit pull request #607 (a lesson) failed the `body` check in `pr-rules`; auto-merge waited until the
  description was rewritten, and the game pull request that linked its lesson sat on `Lessons:` meanwhile.
- **Cause:** the description was typed as a few free lines (summary and lesson name) instead of being started from
  `.github/pull_request_template.md`; Issues affected, Checklist and Screenshots were missing. A docs-only pull request
  felt too small for the template, and `gds pr check-body` was not run on the file before `gh pr create`.
- **Fix:** copy the template into a file, fill every section (`None (reason)` and `Screenshots: none (reason)` are
  valid answers), run `gds pr check-body <file> --title <title file>` until it prints ok, then `gh pr edit -F`.
- **Check for next time:** every pull request, a one-line lesson included, starts from the template file and passes
  `gds pr check-body` before it is created.
- **Docs:** [Hooks](../hooks.md#pr-body).
