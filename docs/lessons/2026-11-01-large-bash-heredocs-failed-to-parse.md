---
areas: [tests, ci, tools]
---
# A large heredoc in the Bash tool failed to parse

2026-11-01

- **Saw:** `unexpected EOF while looking for matching ''` and nothing was written, on a 200 line Python file and a
  GDScript file written with `cat > f <<'EOF'`, and on `python - <<'PY'` scripts that mixed apostrophes, `\n` and
  `"`. A Python edit script written that way also had its `\n` turned into a real newline, and its asserts failed.
  Later (Deadnight #457), in `python - <<'EOF'` scripts a `\` line continuation collapsed (a workflow's `run:` blocks
  broke; actionlint caught it), and `r"...\d+...\b"` became `d+` and a backspace (a hook regex silently never
  matched; a unit test caught it).
- **Cause:** the command text is processed once by the tool before it reaches the shell, so quoting that is fine in a
  terminal is not. Every backslash goes through that escape step before Python sees it, even inside a quoted heredoc
  and a raw string; doubling it does not reliably survive either. The same text through the Write tool worked at
  once.
- **Fix:** never write a backslash through a heredoc. Write files with the Write tool, and edit scripts as `.py`
  files in the scratchpad run with `python file.py args`; use the Edit tool for text that holds `\`. Keep heredocs
  for short ASCII with no backslash. Lint generated workflows (actionlint) and test generated regexes.
- **Docs:** none yet
- **Seen again (kit #165, 2026-11-02):** an edit script written through a heredoc turned the backslash-b of a regex
  (`maintainers?` followed by a word boundary) into a backspace character (a unit test of the maintainer form failed;
  the line showed it under `cat -A`), the backslash-n of two Python strings into real newlines, and a command with
  quotes in its heredoc body failed to parse twice. All were fixed by writing the script with the Write tool and the
  source with the Edit tool. After any generated edit, scan the files for control characters (below a space, other than
  newline, tab and carriage return) before the first test run.
- **Seen again (Deadnight #1080, 2026-11-04):** a 200 line test file and two `python - <<'PYEOF'` doc-edit scripts, each
  with quotes and apostrophes in the body, failed with the same `unexpected EOF` and wrote nothing, after the reminder
  at the start had named this lesson. The short heredocs without quotes in the same task worked. Same fix: the Write tool
  for any body of more than a few plain lines, then `python file.py`.
