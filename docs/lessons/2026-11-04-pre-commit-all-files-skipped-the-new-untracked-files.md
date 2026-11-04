---
areas: [tools, general]
---
# `pre-commit run --all-files` passed and the commit was refused for the files I had just added

2026-11-04

- **Saw:** Deadnight #1063: `uvx pre-commit run --all-files` showed only one gdlint error (fixed), then `git commit` failed
  twice more: a gdlint line over 100 characters in a new capture script, markdownlint MD007, MD012 and MD013 in two
  `LICENSE.md` files and two docs pages, and a CRLF test file (a heredoc written on Windows).
- **Cause:** `--all-files` checks the files git tracks; files created in the task and not yet `git add`ed were not
  looked at, and the `.md` edits had not been staged either. The hook run at commit time checks what is staged, so it
  found everything the first run could not.
- **Fix:** `git add -A` before `uvx pre-commit run --all-files` (or run the hooks at commit time and read all of their
  output), `file <new file>` for CRLF on Windows, and keep Markdown lines to 120 characters with nested lists indented
  by 4.
- **Docs:** [Lessons](index.md): no page covers it yet; this file is the record.
