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

FREED_WITHIN_MS = 1000  # a clip must be freed within this; measured 3 to 16 ms idle and with four runs at once
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
def test_the_guard_frees_the_cursor_every_interval_and_once_more_at_the_end(monkeypatch: pytest.MonkeyPatch) -> None:
    """The guard's whole job, without the real cursor: it calls `ClipCursor(None)` until told to stop, then once more.
    A fake `user32` records the calls; nothing here waits on a clock the machine's load can stretch."""
    from gds_tools import quiet_run

    calls: list[object] = []

    class FakeUser32:
        @staticmethod
        def ClipCursor(rect: object) -> None:  # noqa: N802 - the Windows name
            calls.append(rect)

    monkeypatch.setattr(quiet_run, "_u32", FakeUser32)
    running = threading.Event()
    guard = threading.Thread(target=quiet_run._free_cursor_while, args=(running,), daemon=True)
    guard.start()
    deadline = time.time() + 30
    while len(calls) < 3 and time.time() < deadline:
        time.sleep(0.01)
    before = len(calls)
    running.set()
    guard.join(timeout=30)
    assert not guard.is_alive()
    assert before >= 3, "the guard did not free the cursor repeatedly while the program ran"
    assert len(calls) > before, "the guard did not free the cursor once more when the program ended"
    assert all(rect is None for rect in calls)


@pytest.mark.skipif(sys.platform != "win32", reason="the cursor clip is a Windows call")
def test_a_cursor_clip_on_the_hidden_desktop_is_freed_and_does_not_hold_the_real_cursor() -> None:
    """A program on the private desktop clips the cursor to 10 x 10 pixels, like a game that captures the mouse and
    re-applies it on focus and resize, and times how long each clip lasts by polling the clip from there. Without the
    guard a clip is never freed (the program gives up after 3 s); with it, each is freed within milliseconds.

    This replaces a count of how many of 20 samples from a thread of this process saw the clip held (at most a third).
    That count measures the share of time the cursor was held, which depends on how the guard thread, the sampling
    thread and the program are scheduled against each other: on a loaded `windows-2025` runner 9 of 20 were held
    (kit #113) while the guard worked as written. The latency of each clip, seen from the program that set it, does not
    depend on the sampler, and the bound is far above any stall a loaded runner causes and far below "never"."""
    import ctypes
    from ctypes import wintypes as wt

    user32 = ctypes.WinDLL("user32")
    user32.GetClipCursor.argtypes = [ctypes.POINTER(wt.RECT)]

    def clip() -> tuple[int, int, int, int]:
        rect = wt.RECT()
        user32.GetClipCursor(ctypes.byref(rect))
        return rect.left, rect.top, rect.right, rect.bottom

    free = clip()
    code = "\n".join(
        [
            "import ctypes, json, time",
            "from ctypes import wintypes as wt",
            "user32 = ctypes.windll.user32",
            "mine = wt.RECT(0, 0, 10, 10)",
            "def held():",
            "    r = wt.RECT(); user32.GetClipCursor(ctypes.byref(r))",
            "    return (r.left, r.top, r.right, r.bottom) == (0, 0, 10, 10)",
            "latencies = []",
            "for _ in range(10):",
            "    user32.ClipCursor(ctypes.byref(mine)); start = time.perf_counter()",
            "    while held() and time.perf_counter() - start < 3: time.sleep(0.0005)",
            "    latencies.append(round((time.perf_counter() - start) * 1000, 1))",
            "    time.sleep(0.1)",
            "print(json.dumps(latencies))",
        ]
    )
    outcome = run_quiet(python(code), timeout=120)
    latencies = json.loads(outcome.output.strip().splitlines()[-1])
    assert len(latencies) == 10, outcome.output
    assert max(latencies) < FREED_WITHIN_MS, f"a clip held the cursor for {max(latencies)} ms: {latencies}"
    assert clip() == free


def test_gds_godot_plays_no_sound_unless_asked() -> None:
    dummy = ["--audio-driver", "Dummy"]
    assert cli.mute_godot(["--path", "game"]) == [*dummy, "--path", "game"]
    assert cli.mute_godot([]) == dummy
    assert cli.mute_godot(["--path", "g", "--audio-driver", "WASAPI"]) == ["--path", "g", "--audio-driver", "WASAPI"]
    assert cli.mute_godot(["--audio-driver=WASAPI"]) == ["--audio-driver=WASAPI"]
    assert cli.mute_godot(["--path", "game"], with_audio=True) == ["--path", "game"]


def test_with_audio_is_an_option_of_gds_godot_in_either_order() -> None:
    timeout = cli.GODOT_TIMEOUT
    assert cli.parse_godot_args(["--path", "g"]) == (timeout, False, ["--path", "g"])
    assert cli.parse_godot_args(["--with-audio", "--path", "g"]) == (timeout, True, ["--path", "g"])
    assert cli.parse_godot_args(["--with-audio", "--timeout", "5", "--", "--path", "g"]) == (5.0, True, ["--path", "g"])
    assert cli.parse_godot_args(["--timeout", "5", "--with-audio", "--", "--path", "g"]) == (5.0, True, ["--path", "g"])
    assert cli.parse_godot_args(["--timeout", "5", "--", "--headless"]) == (5.0, False, ["--headless"])


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


@pytest.mark.skipif(sys.platform != "win32", reason="the probe reads the Windows cursor clip")
def test_the_browser_probe_times_a_held_clip_and_a_missing_guard_exceeds_the_bound() -> None:
    """The probe's measure on a fake clip and a fake clock, so no real cursor is held and nothing waits: a clip freed
    after a few milliseconds reads as a few, and a clip that is never freed (the guard removed) reads as the whole lock,
    which is over `FREED_WITHIN_MS`. This is the test's mutant: the guard off."""
    import browser_lock_probe as probe

    free, held = (0, 0, 1024, 768), (17, 68, 864, 541)

    def measure(freed_at: float, before: tuple[int, int, int, int] = free) -> float:
        now = [0.0]

        def sleep(seconds: float) -> None:
            now[0] += seconds

        def read() -> tuple[int, int, int, int]:
            return held if 0.1 <= now[0] < freed_at else free

        samples = probe.poll(probe.LOCK_SECONDS, read=read, clock=lambda: now[0], sleep=sleep)
        return probe.longest_held_ms(samples, probe.free_clip([before, *(rect for _, rect in samples)]))

    assert measure(freed_at=0.105) < FREED_WITHIN_MS  # a guard that frees it within 5 ms
    assert measure(freed_at=0.5) < FREED_WITHIN_MS  # a guard stalled for 0.4 s by a loaded runner still passes
    assert measure(freed_at=1e9) >= FREED_WITHIN_MS  # no guard: held for the rest of the lock
    # another program's clip (a parallel run of this test) set when the lock starts is not taken for the free one
    assert measure(freed_at=0.105, before=(30, 40, 500, 400)) < FREED_WITHIN_MS
    assert probe.LOCK_SECONDS * 1000 > FREED_WITHIN_MS * 2  # the lock outlasts the bound


@windows_only
def test_a_headless_chrome_pointer_lock_does_not_hold_the_real_cursor() -> None:
    """Headless Chrome (Playwright, channel "chrome", as the web smoke probes run with --gpu) clips the person's real
    cursor to its hidden window under pointer lock, at the top left of the screen: measured (17, 68, 864, 541) for the
    whole lock, started plainly or on the private desktop without the guard (2026-11-02). Under `run_quiet` the lock
    takes, the browser runs on the private desktop with no window on the person's, and the clip is freed within
    `FREED_WITHIN_MS` of being set.

    The probe times the clip from inside the lock (the longest stretch it differed from the free one), as the clip
    test above does. This replaces "at most 3 of the ~1400 samples from a thread of this process held" (4 of 1416 on a
    loaded `windows-2025`, kit #166): a share of samples measures how the guard, the sampler and the browser are
    scheduled, not whether the guard works. Without the guard the clip lasts the whole 2.5 s lock."""
    import shutil

    if not any(p.exists() for p in CHROME) or not shutil.which("uv"):
        pytest.skip("Google Chrome or uv is not installed")
    from focus_holder import process_tree

    user32 = ctypes_user32()
    free = clip_of(user32)
    probe = Path(__file__).with_name("browser_lock_probe.py")
    cmd = [shutil.which("uv") or "uv", "run", "--no-project", "--with", "playwright==1.64.1", "python", str(probe)]
    pids: list[int] = []
    on_person_desktop: set[str] = set()
    done = threading.Event()

    def sample() -> None:
        while not done.is_set():
            if pids:
                on_person_desktop.update(windows_of(user32, process_tree(pids[0])))
            time.sleep(0.1)

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
    assert result["locked"] is True and result["desktop"] == "gds-quiet", outcome.output
    assert not on_person_desktop, f"browser windows on the person's desktop: {sorted(on_person_desktop)}"
    assert result["held_ms"] < FREED_WITHIN_MS, f"a clip held the cursor for {result['held_ms']} ms: {outcome.output}"
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
