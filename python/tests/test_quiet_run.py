"""`run_quiet`: output, exit codes and timeouts with a plain program everywhere, and on Windows the proof that matters:
the real pinned Godot opens a window and renders frames while another window keeps the foreground."""

import json
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
    # A sample may land in the few ms between a clip and the guard, longer on a loaded CI runner (6 of 20 seen with a
    # 20 ms guard): free most of the time, and free at the end.
    assert len(held) <= len(seen) // 3
    assert clip() == free


def test_godot_arguments_are_split_from_the_timeout() -> None:
    assert cli.split_godot_args(["--path", "game"]) == (cli.GODOT_TIMEOUT, ["--path", "game"])
    assert cli.split_godot_args(["--timeout", "30", "--", "--headless"]) == (30.0, ["--headless"])
    with pytest.raises(workspace.WorkspaceError):
        cli.split_godot_args(["--timeout", "soon"])


def test_quiet_arguments_are_split_from_the_timeout() -> None:
    assert cli.split_quiet_args(["--", "uv", "run", "--timeout", "3"]) == (
        cli.QUIET_TIMEOUT,
        ["uv", "run", "--timeout", "3"],
    )
    assert cli.split_quiet_args(["--timeout", "5", "--", "python", "x.py"]) == (5.0, ["python", "x.py"])


def test_gds_quiet_runs_any_command_and_returns_its_code(capsys: pytest.CaptureFixture[str]) -> None:
    code = "import os, sys; print('quiet', os.environ.get('GDS_QUIET')); sys.exit(4)"
    assert cli.main(["quiet", "--", sys.executable, "-c", code]) == 4
    assert "quiet 1" in capsys.readouterr().out
    assert cli.main(["quiet", "--timeout", "1", "--", sys.executable, "-c", "import time; time.sleep(30)"]) == 124
    assert cli.main(["quiet"]) == 2  # nothing to run


def test_a_batch_file_runs_through_cmd(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    script = tmp_path / "probe.cmd"
    script.write_text("@echo off\r\n", encoding="utf-8")
    monkeypatch.setattr(cli.shutil, "which", lambda name: str(script) if name == "probe" else None)
    resolved = cli.resolve_program(["probe", "a b"])
    assert resolved[1:] == ["/d", "/c", str(script), "a b"]
    assert cli.resolve_program(["missing", "x"]) == ["missing", "x"]


@pytest.mark.skipif(sys.platform != "win32", reason="desktops are Windows'")
def test_every_program_the_command_starts_runs_on_the_private_desktop() -> None:
    """A browser started by Playwright is a grandchild of the command: it inherits the desktop like any child."""
    desktop = (
        "import ctypes; u = ctypes.windll.user32; n = ctypes.create_unicode_buffer(256); "
        "u.GetThreadDesktop.restype = ctypes.c_void_p; "
        "u.GetUserObjectInformationW(ctypes.c_void_p(u.GetThreadDesktop(ctypes.windll.kernel32.GetCurrentThreadId())),"
        " 2, n, 512, None); print(n.value)"
    )
    code = f"import subprocess, sys; subprocess.run([sys.executable, '-c', {desktop!r}])"
    assert run_quiet(python(code)).output.strip() == "gds-quiet"


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


CHROME = [
    Path(os.environ.get(var, "-")) / "Google" / "Chrome" / "Application" / "chrome.exe"
    for var in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA")
]


@windows_only
def test_a_headless_chrome_pointer_lock_does_not_hold_the_real_cursor() -> None:
    """Headless Chrome (Playwright, channel "chrome", as the web smoke probes run with --gpu) clips the person's real
    cursor to its hidden window under pointer lock, at the top left of the screen: measured (17, 68, 864, 541) for the
    whole lock, started plainly or on the private desktop without the guard (2026-11-02). Under `run_quiet` the lock
    takes, the browser runs on the private desktop with no window on the person's, and the cursor stays free."""
    import shutil

    if not any(p.exists() for p in CHROME) or not shutil.which("uv"):
        pytest.skip("Google Chrome or uv is not installed")
    from focus_holder import process_tree

    user32 = ctypes_user32()
    free = clip_of(user32)
    probe = Path(__file__).with_name("browser_lock_probe.py")
    cmd = [shutil.which("uv") or "uv", "run", "--no-project", "--with", "playwright==1.64.1", "python", str(probe)]
    pids: list[int] = []
    seen: list[tuple[int, int, int, int]] = []
    on_person_desktop: set[str] = set()
    done = threading.Event()

    def sample() -> None:
        while not done.is_set():
            seen.append(clip_of(user32))
            if pids and len(seen) % 20 == 0:
                on_person_desktop.update(windows_of(user32, process_tree(pids[0])))
            time.sleep(0.005)

    sampler = threading.Thread(target=sample)
    sampler.start()
    try:
        outcome = run_quiet(cmd, timeout=300, on_start=pids.append)
    finally:
        done.set()
        sampler.join()
    if outcome.returncode != 0 and "playwright" in outcome.output.lower() and "locked" not in outcome.output:
        pytest.skip(f"Playwright could not start Chrome: {outcome.output[-300:]}")
    result = json.loads(outcome.output.strip().splitlines()[-1])
    assert result == {"locked": True, "desktop": "gds-quiet"}, outcome.output
    assert not on_person_desktop, f"browser windows on the person's desktop: {sorted(on_person_desktop)}"
    held = [rect for rect in seen if rect != free]
    # The guard frees the clip within 5 ms; a sample may land in that gap on a loaded machine. Unguarded, about 40 of
    # the samples (the whole 0.8 s lock) are held.
    assert len(held) <= 3, f"{len(held)} of {len(seen)} samples held the cursor: {sorted(set(held))}"
    assert clip_of(user32) == free


def ctypes_user32():  # noqa: ANN201 - a ctypes library
    import ctypes
    from ctypes import wintypes as wt

    user32 = ctypes.WinDLL("user32")
    user32.GetClipCursor.argtypes = [ctypes.POINTER(wt.RECT)]
    user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
    return user32


def clip_of(user32) -> tuple[int, int, int, int]:  # noqa: ANN001
    import ctypes
    from ctypes import wintypes as wt

    rect = wt.RECT()
    user32.GetClipCursor(ctypes.byref(rect))
    return rect.left, rect.top, rect.right, rect.bottom


def windows_of(user32, pids: set[int]) -> list[str]:  # noqa: ANN001
    """Every top-level window of `pids` on the person's desktop, hidden ones too (a headless browser shows none)."""
    import ctypes
    from ctypes import wintypes as wt

    found: list[str] = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def each(window: int, _: int) -> bool:
        pid = wt.DWORD()
        user32.GetWindowThreadProcessId(window, ctypes.byref(pid))
        if pid.value in pids:
            name = ctypes.create_unicode_buffer(128)
            user32.GetClassNameW(window, name, 128)
            found.append(name.value)
        return True

    user32.EnumWindows(each, 0)
    return found
