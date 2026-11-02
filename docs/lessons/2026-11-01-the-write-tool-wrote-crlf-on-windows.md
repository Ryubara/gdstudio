---
areas: [tools, process]
---
# The Write tool wrote CRLF line endings on Windows

2026-11-01

- **Saw:** files written with the agent's Write tool failed gdlint and markdownlint on their line endings
  (Deadnight #442).
- **Cause:** on this Windows machine the Write tool writes CRLF; `.gitattributes` normalises on commit, but the
  linters read the working copy.
- **Fix:** normalise new files before committing (`sed -i 's/\r$//' <files>`), then run the pre-commit hooks.
- **Docs:** none yet; see also [Python text mode writes CRLF](2026-11-01-python-text-mode-writes-crlf-on-windows.md).
