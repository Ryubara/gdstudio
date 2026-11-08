# A tour that exits with 139 or 0xC0000005 after saving its frames

A windowed capture script ends, its frames are on disk, and the process exit code is **139** (bash) or
**3221225477 = 0xC0000005** (`gds godot`, an access violation). The official Godot build prints no backtrace, so the
output looks clean. The exit code is the only sign, and `gds capture frames` already refuses a non-zero code.

## Cause we found: a lambda of a freed script in a static variable

A script that stores a **lambda** (or a `Callable` bound to its own method) in a **static variable of another class**
and quits with it still set crashes the engine at shutdown. At quit the engine frees the capture script before the
other class's static variables; the variable then releases a lambda whose script is gone. In Deadnight the hook was
`MainMenu.board_factory = func() -> Object: ...` in a tour. It reproduces headless in a few lines (a `SceneTree` script
that sets the hook and calls `quit()`).

- A `Callable` of a class that lives for the whole run (`FakeChallengeBoard.new`) is safe; so is `Callable()`.
- **Clear the hook before `quit()`** (`MainMenu.board_factory = Callable()`), the way the tests clear it in `after`.
- The same holds for a lambda set on an autoload's variable, or on any object that outlives the capture node.

## Finding it without a backtrace

1. Get the real code: `gds godot` returns Godot's. Through `uv run ... gds godot` in a Git Bash shell a code of
   0xC0000005 shows as `Segmentation fault`, 139.
2. Run the main scene windowed with `--quit-after`: if it exits 0, the engine and the driver are fine.
3. Copy the script and quit early at points along it (an argument says where). The crash begins at the first line that
   touches the thing, and no line before it. Here it was the assignment of the lambda, not the menu, the settings, the
   audio or the renderer.
4. Reduce it to a `SceneTree` script and run it `--headless`: the exit code is read without a window.

## Keep it from coming back

A GdUnit test runs that reduced script in a child Godot and asserts exit code 0, and reads every capture script for a
lambda set on a class that is not cleared in the same file (Deadnight `tests/core/test_capture_quit.gd`).
See the [lesson](../../lessons/2026-11-03-a-lambda-in-a-static-variable-crashed-the-engine-at-quit.md).
