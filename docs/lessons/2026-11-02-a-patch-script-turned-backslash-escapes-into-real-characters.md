---
areas: [process, tools]
---
# A patch script written through a heredoc turned `\n` and `\b` into real characters

2026-11-02

- **Saw:** a test file would not parse (`unterminated string literal`), a regex in `issues.py` had lost its `\b` and
  `\t`, and a `sed` replacement split a string over three lines. Each was found only when `ruff` or `pytest` ran, after
  the "successful" edit.
- **Cause:** the edit was a `python` script written inside a shell heredoc, with the source text in a Python `'''...'''`
  string. Backslash escapes pass through two layers (shell/tool, then the Python string literal), so `\n` became a
  newline, `\t` a tab and `\b` a backspace in the file being edited. `sed 's/x/a\nb/'` does the same with `\n`.
- **Fix:** put text that contains backslashes in an `Edit` call (exact strings, no unescaping), or build the
  characters with `chr(92)`, or use a raw string (`r'''...'''`) and check the result with `git diff` before running
  anything. Run `ruff check` and `ruff format` straight after a scripted edit, not at the end.
- **Docs:** none needed beyond this lesson.
