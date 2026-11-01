# A large heredoc in the Bash tool failed to parse

2026-11-01

- **Saw:** `unexpected EOF while looking for matching ''` and nothing was written, twice, on a 200 line Python file and
  a GDScript file written with `cat > f <<'EOF'`.
- **Cause:** Not isolated: a quoted heredoc should not care about apostrophes in the body, but both failing commands
  were long and mixed quotes with `$(...)` further down. The same text through the Write tool worked at once.
- **Fix:** Write files with the Write tool; keep the shell for running things. Small Python edits with `python - <<'PY'`
  worked.
- **Docs:** none yet
