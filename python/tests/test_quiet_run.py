"""`run_quiet`: output, exit codes and timeouts with a plain program everywhere, and on Windows the proof that matters:
the real pinned Godot opens a window and renders frames while another window keeps the foreground."""

import os
import sys
import threading
import time
from pathlib import Path

import pytest
from PIL import Image

from gds_tools import cli, workspace
from gds_tools.quiet_run import run_quiet

SPIKE = Path(__file__).resolve().parents[2] / "sandbox" / "no-focus"


def python(code: str) -> list[str]:
    return [sys.executable, "-c", code]


def test_output_and_exit_code_come_back() -> None:
    chunks: list[str] = []
    outcome = run_quiet(
        python("import sys; print('out'); print('err', file=sys.stderr); sys.exit(3)"), on_output=chunks.append
    )
    assert outcome.returncode == 3
    assert not outcome.timed_out
    assert "out" in outcome.output and "err" in outcome.output
    assert "".join(chunks) == outcome.output


def test_working_folder_and_process_id(tmp_path: Path) -> None:
    pids: list[int] = []
    outcome = run_quiet(python("import os; print(os.getcwd())"), cwd=tmp_path, on_start=pids.append)
    assert Path(outcome.output.strip()).resolve() == tmp_path.resolve()
    assert len(pids) == 1 and pids[0] != os.getpid()


def test_timeout_kills_the_program_and_what_it_started() -> None:
    child = "import time; time.sleep(60)"
    code = f"import subprocess, sys, time; subprocess.Popen([sys.executable, '-c', {child!r}]); time.sleep(60)"
    started = time.time()
    outcome = run_quiet(python(code), timeout=2)
    assert outcome.timed_out
    assert time.time() - started < 20


def test_the_program_is_told_it_runs_quiet() -> None:
    outcome = run_quiet(python("import os; print(os.environ.get('GDS_QUIET'))"))
    assert outcome.output.strip() == "1"


@pytest.mark.skipif(sys.platform != "win32", reason="the cursor clip is a Windows call")
def test_a_cursor_clip_on_the_hidden_desktop_does_not_hold_the_real_cursor() -> None:
    import ctypes
    from ctypes import wintypes as wt

    user32 = ctypes.WinDLL("user32")
    user32.GetClipCursor.argtypes = [ctypes.POINTER(wt.RECT)]

    def clip() -> tuple[int, int, int, int]:
        rect = wt.RECT()
        user32.GetClipCursor(ctypes.byref(rect))
        return rect.left, rect.top, rect.right, rect.bottom

    free = clip()
    # A program on the private desktop clips the cursor to 10 x 10 pixels and again every 0.1 s for 1.5 s, like a game
    # that captures the mouse and re-applies it on focus and resize. Without the guard every sample is held (measured:
    # 16 of 20 even against a program re-clipping every 5 ms). A game re-clipping every frame must read GDS_QUIET and
    # not capture at all: the guard is the safety net, not the fix.
    code = "\n".join(
        [
            "import ctypes, time",
            "from ctypes import wintypes as wt",
            "r = wt.RECT(0, 0, 10, 10)",
            "end = time.time() + 1.5",
            "while time.time() < end:",
            "    ctypes.windll.user32.ClipCursor(ctypes.byref(r)); time.sleep(0.1)",
        ]
    )
    seen: list[tuple[int, int, int, int]] = []

    def sample(_pid: int) -> None:
        def run() -> None:
            for _ in range(20):
                time.sleep(0.05)
                seen.append(clip())

        threading.Thread(target=run, daemon=True).start()

    run_quiet(python(code), on_start=sample)
    held = [rect for rect in seen if rect == (0, 0, 10, 10)]
    # A sample may land in the 20 ms between a clip and the guard: free nearly all the time, and free at the end.
    assert len(held) <= len(seen) // 4
    assert clip() == free


def test_godot_arguments_are_split_from_the_timeout() -> None:
    assert cli.split_godot_args(["--path", "game"]) == (cli.GODOT_TIMEOUT, ["--path", "game"])
    assert cli.split_godot_args(["--timeout", "30", "--", "--headless"]) == (30.0, ["--headless"])
    with pytest.raises(workspace.WorkspaceError):
        cli.split_godot_args(["--timeout", "soon"])


# --- the real thing -------------------------------------------------------------------------------------------------

windows_only = pytest.mark.skipif(sys.platform != "win32", reason="the focus rules are Windows'")


def pinned_godot() -> Path:
    try:
        return workspace.tool_path("godot")
    except workspace.WorkspaceError:
        pytest.skip("the pinned Godot is not installed")


@windows_only
def test_a_windowed_godot_renders_a_capture_without_touching_the_keyboard_or_the_desktop(tmp_path: Path) -> None:
    """A test window holds the foreground and is typed into (F24, once every 30 ms) while the pinned Godot opens a real
    window and records a Movie Maker capture. Every key must arrive, the foreground must never belong to Godot, no
    Godot window may exist on the person's desktop, and the frames must be rendered, changing and not black."""
    from focus_holder import Holder, process_tree, visible_windows_of

    godot = pinned_godot()
    holder = Holder()
    try:
        if not holder.take_foreground():
            pytest.skip("the test window could not take the foreground (a locked or remote session)")
        holder.type_key()
        time.sleep(0.2)
        assert holder.received == holder.sent == 1, "the test window does not receive keys: the test cannot judge"
        run_quiet([str(godot), "--headless", "--path", str(SPIKE), "--import"], timeout=120)
        movie = tmp_path / "shot.png"
        pids: list[int] = []
        foreground_taken: list[float] = []
        windows: set[str] = set()
        done = threading.Event()
        started = time.time()

        def watch() -> None:
            while not done.is_set():
                if pids:
                    tree = process_tree(pids[0])
                    if holder.foreground_owner() in tree:
                        foreground_taken.append(round(time.time() - started, 2))
                    windows.update(visible_windows_of(tree))
                holder.type_key()
                time.sleep(0.03)

        watcher = threading.Thread(target=watch)
        watcher.start()
        try:
            outcome = run_quiet(
                [
                    str(godot),
                    "--path",
                    str(SPIKE),
                    "--write-movie",
                    str(movie),
                    "--fixed-fps",
                    "10",
                    "--quit-after",
                    "30",
                ],
                timeout=120,
                on_start=pids.append,
            )
        finally:
            done.set()
            watcher.join()
        time.sleep(0.2)  # the last keys are still in the message queue
        assert outcome.returncode == 0, outcome.output
        assert "ERROR" not in outcome.output
        assert "driver=Windows" in outcome.output  # a real window, not headless
        assert not foreground_taken, f"Godot took the foreground at {foreground_taken[:5]} s"
        assert not windows, f"Godot had windows on the person's desktop: {sorted(windows)}"
        assert holder.sent > 5 and holder.received == holder.sent, f"{holder.received} of {holder.sent} keys arrived"
        frames = sorted(tmp_path.glob("shot*.png"))
        assert len(frames) == 30
        colours = {Image.open(f).convert("RGB").getpixel((320, 180)) for f in frames}
        assert len(colours) > 20 and (0, 0, 0) not in colours  # rendered, changing and not black
    finally:
        holder.close()
