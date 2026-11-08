---
areas: [tests, tools]
---
# A browser probe that started a Godot server left it running when the probe was killed

2026-11-02

- **Saw:** a probe (Deadnight #502) that starts a headless game server was killed by the tool's time limit; the next run
  failed with `PermissionError: [WinError 32]` on the server's log file, and `Godot_v4.7.2-stable_win64_console.exe` and
  `Godot_v4.7.2-stable_win64.exe` were still running (the port, the log and about 600 MB held).
- **Cause:** on Windows the console build of Godot is a wrapper that starts the real program, so `Popen.kill()` and
  `OS.kill` end the wrapper only; and nothing ran when the parent was killed.
- **Fix:** stop the server with `taskkill /T /F /PID <pid>` (the tree) in a `finally`, give the probe a hard time limit
  of its own (`timeout`, `gds quiet --timeout`) shorter than the tool's, and when a run was killed find what it left
  by command line (`Get-CimInstance Win32_Process`, filtered on the scratch folder in its arguments), never by image
  name, and stop those by PID.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#the-same-in-the-browser-deadnight-502).
