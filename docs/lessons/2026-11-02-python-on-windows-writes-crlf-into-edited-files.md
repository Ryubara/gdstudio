---
areas: [process, tools]
---
# Files edited with a Python script came back with CRLF line endings

2026-11-02

- **Saw:** `git add` warned "CRLF will be replaced by LF the next time Git touches it" for GDScript files an agent had
  changed with a small `python` script, and `gdformat` rewrote them.
- **Cause:** `open(path, "w")` on Windows translates `\n` to `\r\n` (the text mode default), whatever the file had.
- **Fix:** read and write with `newline=""` / `newline="\n"` (`open(p, newline="").read().replace("\r\n", "\n")` and
  `open(p, "w", newline="\n")`), or use the Edit tool. The repository's `.gitattributes` has `* text=auto eol=lf`, so
  nothing wrong is committed, but the working tree and the formatter disagree until it is fixed.
- **Docs:** none needed beyond this lesson.
