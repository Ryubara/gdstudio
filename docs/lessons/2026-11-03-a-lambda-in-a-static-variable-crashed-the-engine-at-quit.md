---
areas: [tests, godot]
---
# Windowed tours exited with 139 after saving their frames: a lambda left in a static variable

2026-11-03

- **Saw:** Deadnight `solo_settings_tour` (and `map_picker_tour`, #666) wrote every PNG and then exited with code 139
  (`gds godot` returns 0xC0000005). No backtrace is printed by the official build. The main scene alone exited 0.
- **Cause:** the tour set `MainMenu.board_factory` (a `static var`) to a lambda of the tour's own script and quit
  without clearing it. The engine frees the tour's script before the game's static variables, so quitting released a
  lambda of a dead script: an access violation. Not audio, a thread or the RenderingServer, as first suspected.
- **Fix:** clear the hook before `quit()` (`MainMenu.board_factory = Callable()`). Found by quitting the tour at steps
  and then reducing it to a `SceneTree` script (lambda kept: 139, cleared: 0, `Class.new` as the callable: 0). A test
  runs the reduced script in a child Godot for the exit code and checks that every capture script that sets a lambda
  on a class also clears it.
- **Check for next time:** a capture or tour that sets a static hook or any callback on the game clears it before it
  quits; read the exit code of every windowed run (it is not noise), and bisect a crash by quitting early, not by
  guessing a cause.
- **Docs:** [A tour that exits with 139](../engines/godot/exit-code-139.md).
