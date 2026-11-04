---
areas: [general, tools]
---
# A backslash-n sent through the shell became a real newline in the file

2026-11-03

- **Saw:** `gdformat` failed on a test file with "No terminal matches '\"' ... at line 116" after an edit made by a
  Python script run from a heredoc; the line `override_failure_message("\n".join(failures))` was split in two.
  Running the same edit again changed nothing.
- **Cause:** the script wrote `"\n"` and the command layer reduced it to `\n` before Python read it, so Python wrote a
  real newline into the GDScript string (GDScript itself accepts a string over two lines, so the tests still ran; only
  the formatter refused it).
- **Fix:** build a backslash in the edit script with `chr(92)` (and a newline with `chr(10)`) instead of typing escapes,
  or use the Edit tool for a line with backslashes; check with `grep -n '("$'` on the file and with
  `uvx pre-commit run --all-files` before the commit.
- **Docs:** none beyond this lesson; the older lesson on CRLF line endings in GDScript is the same family.
