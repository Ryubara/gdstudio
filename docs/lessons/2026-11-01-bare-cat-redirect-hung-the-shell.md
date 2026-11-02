---
areas: [general]
---
# Bare `cat > file` in a shell command hung the tool for two minutes

2026-11-01

- **Saw:** a long chained shell command timed out and was moved to the background; files after the stray line were
  not created.
- **Cause:** a leftover `cat > name 2>/dev/null` with no heredoc read from the terminal forever.
- **Fix:** write files with the Write tool, or give every `cat >` a heredoc; check each step of a chain printed.
- **Docs:** none (tool habit).
