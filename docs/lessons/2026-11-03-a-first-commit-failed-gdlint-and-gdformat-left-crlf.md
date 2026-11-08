---
areas: [tools, godot]
---
# A first commit failed gdlint and markdownlint, and gdformat left CRLF in what it rewrote

2026-11-03

- **Saw:** the commit hooks refused a branch of new scripts: lines over 100 characters in comments, a `const` written
  after a `func` (`class-definitions-order`), a markdown line over 120. `gdformat` reformatted two test files, and git
  then warned "CRLF will be replaced by LF" for them: on Windows `gdformat` writes CRLF into the files it rewrites.
- **Cause:** the hooks were first run only when the commit ran them, after hours of edits.
- **Fix:** run `uvx pre-commit run --all-files` after each batch of edits (twice: the second run shows what the first
  one rewrote), put constants and variables before functions, keep comments under 100, and after it strip the carriage
  returns of what `gdformat` touched (`sed -i 's/\r$//' <files>`; check with a byte search for `\r\n`, not `grep $'\r'`,
  which found nothing here).
- **Docs:** [Hooks](../studio/hooks.md), and each repository's `.pre-commit-config.yaml`.
