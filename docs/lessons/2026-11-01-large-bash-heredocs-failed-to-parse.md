# A large heredoc in the Bash tool failed to parse

2026-11-01

- **Saw:** `unexpected EOF while looking for matching ''` and nothing was written, on a 200 line Python file and a
  GDScript file written with `cat > f <<'EOF'`, and on `python - <<'PY'` scripts that mixed apostrophes, `\n` and
  `"`. A Python edit script written that way also had its `\n` turned into a real newline, and its asserts failed.
- **Cause:** the command text is processed once by the tool before it reaches the shell, so quoting that is fine in a
  terminal is not. The same text through the Write tool worked at once.
- **Fix:** write files with the Write tool, and edit scripts as `.py` files in the scratchpad run with
  `python file.py args`; use the Edit tool for text that holds `\n`. Keep heredocs for short ASCII.
- **Docs:** none yet
