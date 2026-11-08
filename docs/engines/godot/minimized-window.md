# A minimized window draws nothing

In a windowed GdUnit run (`gds godot -- ... GdUnitCmdTool.gd -a <suite>`) the window is minimized: the command-line
runner minimizes it when it starts, and again after every suite (`GdUnitTestSuiteAfterStage`). The first suite of a
session finds the window as the game left it, because the game's `Settings` autoload puts it in the windowed mode when
it is ready; every suite after the first starts minimized (`DisplayServer.window_get_mode() == 1`).

**A minimized window draws no frame.** The main loop goes on (`process_frame`, `physics_frame` and timers fire), but the
engine skips the draw: `Engine.get_frames_drawn()` stands still, a `SubViewport` does not update, and
`RenderingServer.frame_post_draw` never comes. Anything that `await`s it hangs until the test's own five minute limit,
with nothing in the log (`GdUnit` prints `Test timed out after 5min`, and a kill prints one unrelated
`BUG: Unreferenced static string`).

It was found twice, in two places, by the same cause:

| Where | What waited | Fix |
| --- | --- | --- |
| A pixel test (Deadnight's outline suite) | `await RenderingServer.frame_post_draw` | draw by hand: `RenderingServer.force_draw(false)` a few times ([Measuring an effect on the screen](measuring-effects-on-screen.md), [Outline through walls](outline-through-walls.md#only-where-it-is-hidden)) |
| A night's warm-up (Deadnight #1207): the loading screen draws the lot a few times and waits for each frame | the same `await` inside the game | the suites that open a night put the window back in `before()` |

When the code under test needs real drawn frames (a warm-up, a shader's first use, a capture), restore the window
instead of faking the draw:

```gdscript
func before() -> void:
    await WindowFixture.make_drawable(get_tree())
```

Deadnight's `WindowFixture` (`game/tests/ui/window_fixture.gd`) sets the mode back to windowed when it is minimized,
waits for two drawn frames in real time and, if none comes in five seconds, prints an error in place of a hang. A
headless run has no window and returns at once. A guard suite lists every suite that opens a night and does not call it.

How to see which await hung: print `Engine.get_frames_drawn()` and `DisplayServer.window_get_mode()` just before the
await. A hung one prints mode `1` and a frame count that does not move.

Do not lengthen the test timeout and do not catch it with a timer in the game: the game is right to wait (a player who
minimizes a loading game finds it finishing when the window comes back).
