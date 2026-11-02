---
areas: [tools, net]
---
# Git Bash rewrote a value that started with a slash

2026-11-02

- **Saw:** a Railway variable set to `/server` through the Railway CLI from Git Bash arrived as
  `C:/Program Files/Git/server`; the game server's first heartbeat to the backend failed with a 400.
- **Cause:** MSYS path conversion rewrites any argument that looks like a POSIX path when Git Bash calls a Windows
  program.
- **Fix:** prefix the command with `MSYS_NO_PATHCONV=1`, or run it from PowerShell; read the value back after setting
  it.
- **Docs:** [Workspace](../workspace.md).
