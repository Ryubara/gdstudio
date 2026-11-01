"""Start a program so that its windows never take the keyboard or mouse from the person at the machine.

On Windows every windowed Godot (a capture, an autopilot scene, a GdUnit run without `--headless`) grabs the
foreground when its window opens, and no start-up flag stops that (`docs/godot/no-focus.md`). A window on a different
Windows desktop cannot take the focus of the one the person works on, so the program is started on a private desktop
of the same window station: it renders as usual (OpenGL and Movie Maker included) and nobody sees or feels it.

Everywhere else (Linux CI, macOS) there is no focus to protect and the program is started normally.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
from collections.abc import Callable
from dataclasses import dataclass

DESKTOP_NAME = "gds-quiet"  # one shared desktop: every quiet program of every agent lands on it
KILL_GRACE = 5  # seconds the output reader waits for the program to end after a timeout kill


@dataclass(frozen=True)
class Outcome:
    """How a quiet run ended: exit code, combined output, and whether the timeout killed it."""

    returncode: int
    output: str
    timed_out: bool = False


def run_quiet(
    cmd: list[str],
    cwd: str | os.PathLike[str] | None = None,
    timeout: float | None = None,
    on_output: Callable[[str], None] | None = None,
    on_start: Callable[[int], None] | None = None,
) -> Outcome:
    """Run `cmd` to its end without disturbing the person at the machine; stdout and stderr are merged.

    `on_output` gets each chunk as it arrives (to stream it), `on_start` the process id. After `timeout` seconds the
    whole process tree is killed (Godot's console wrapper starts the real program as a child).
    """
    if sys.platform == "win32":
        return _run_on_private_desktop(cmd, cwd, timeout, on_output, on_start)
    return _run_plain(cmd, cwd, timeout, on_output, on_start)


def _run_plain(
    cmd: list[str],
    cwd: str | os.PathLike[str] | None,
    timeout: float | None,
    on_output: Callable[[str], None] | None,
    on_start: Callable[[int], None] | None,
) -> Outcome:
    proc = subprocess.Popen(
        cmd, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        encoding="utf-8", errors="replace",
    )  # fmt: skip
    if on_start:
        on_start(proc.pid)
    timed_out = threading.Event()

    def kill() -> None:
        timed_out.set()
        proc.kill()

    timer = threading.Timer(timeout, kill) if timeout else None
    if timer:
        timer.start()
    chunks: list[str] = []
    assert proc.stdout is not None
    for line in proc.stdout:
        chunks.append(line)
        if on_output:
            on_output(line)
    proc.wait()
    if timer:
        timer.cancel()
    return Outcome(proc.returncode, "".join(chunks), timed_out.is_set())


if sys.platform == "win32":
    import ctypes
    import msvcrt
    from ctypes import wintypes as wt

    _k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _u32 = ctypes.WinDLL("user32", use_last_error=True)

    _GENERIC_ALL = 0x10000000
    _INHERIT = 0x00000001
    _CREATE_SUSPENDED = 0x00000004
    _CREATE_NO_WINDOW = 0x08000000
    _CREATE_UNICODE_ENVIRONMENT = 0x00000400
    _STARTF_USESTDHANDLES = 0x00000100
    _JOB_KILL_ON_CLOSE = 0x00002000
    _JOB_EXTENDED_LIMIT_INFO = 9
    _INFINITE = 0xFFFFFFFF

    class _Security(ctypes.Structure):
        _fields_ = [("length", wt.DWORD), ("descriptor", wt.LPVOID), ("inherit", wt.BOOL)]

    class _StartupInfo(ctypes.Structure):
        _fields_ = [
            ("cb", wt.DWORD), ("reserved", wt.LPWSTR), ("desktop", wt.LPWSTR), ("title", wt.LPWSTR),
            ("x", wt.DWORD), ("y", wt.DWORD), ("x_size", wt.DWORD), ("y_size", wt.DWORD),
            ("x_chars", wt.DWORD), ("y_chars", wt.DWORD), ("fill", wt.DWORD), ("flags", wt.DWORD),
            ("show", wt.WORD), ("reserved2_size", wt.WORD), ("reserved2", wt.LPVOID),
            ("std_in", wt.HANDLE), ("std_out", wt.HANDLE), ("std_err", wt.HANDLE),
        ]  # fmt: skip

    class _ProcessInfo(ctypes.Structure):
        _fields_ = [("process", wt.HANDLE), ("thread", wt.HANDLE), ("pid", wt.DWORD), ("tid", wt.DWORD)]

    class _BasicLimits(ctypes.Structure):
        _fields_ = [
            ("per_process_time", ctypes.c_int64), ("per_job_time", ctypes.c_int64), ("flags", wt.DWORD),
            ("min_working_set", ctypes.c_size_t), ("max_working_set", ctypes.c_size_t),
            ("active_process_limit", wt.DWORD), ("affinity", ctypes.c_size_t),
            ("priority_class", wt.DWORD), ("scheduling_class", wt.DWORD),
        ]  # fmt: skip

    class _IoCounters(ctypes.Structure):
        _fields_ = [
            (name, ctypes.c_uint64) for name in ("rd_ops", "wr_ops", "other_ops", "rd_bytes", "wr_bytes", "other_bytes")
        ]

    class _ExtendedLimits(ctypes.Structure):
        _fields_ = [
            ("basic", _BasicLimits), ("io", _IoCounters), ("job_memory", ctypes.c_size_t),
            ("process_memory", ctypes.c_size_t), ("peak_process_memory", ctypes.c_size_t),
            ("peak_job_memory", ctypes.c_size_t),
        ]  # fmt: skip

    _k32.CreateProcessW.argtypes = [
        wt.LPCWSTR, wt.LPWSTR, wt.LPVOID, wt.LPVOID, wt.BOOL, wt.DWORD, wt.LPVOID, wt.LPCWSTR,
        ctypes.POINTER(_StartupInfo), ctypes.POINTER(_ProcessInfo),
    ]  # fmt: skip
    _k32.CreatePipe.argtypes = [
        ctypes.POINTER(wt.HANDLE),
        ctypes.POINTER(wt.HANDLE),
        ctypes.POINTER(_Security),
        wt.DWORD,
    ]
    _k32.CreateFileW.restype = wt.HANDLE
    _k32.CreateFileW.argtypes = [
        wt.LPCWSTR,
        wt.DWORD,
        wt.DWORD,
        ctypes.POINTER(_Security),
        wt.DWORD,
        wt.DWORD,
        wt.HANDLE,
    ]
    _k32.CreateJobObjectW.restype = wt.HANDLE
    _k32.CreateJobObjectW.argtypes = [wt.LPVOID, wt.LPCWSTR]
    _k32.SetInformationJobObject.argtypes = [wt.HANDLE, ctypes.c_int, wt.LPVOID, wt.DWORD]
    _k32.AssignProcessToJobObject.argtypes = [wt.HANDLE, wt.HANDLE]
    _k32.TerminateJobObject.argtypes = [wt.HANDLE, wt.UINT]
    _k32.ResumeThread.argtypes = [wt.HANDLE]
    _k32.WaitForSingleObject.argtypes = [wt.HANDLE, wt.DWORD]
    _k32.GetExitCodeProcess.argtypes = [wt.HANDLE, ctypes.POINTER(wt.DWORD)]
    _k32.SetHandleInformation.argtypes = [wt.HANDLE, wt.DWORD, wt.DWORD]
    _k32.CloseHandle.argtypes = [wt.HANDLE]
    _u32.CreateDesktopW.restype = wt.HANDLE
    _u32.CreateDesktopW.argtypes = [wt.LPCWSTR, wt.LPCWSTR, wt.LPVOID, wt.DWORD, wt.DWORD, wt.LPVOID]
    _u32.CloseDesktop.argtypes = [wt.HANDLE]

    def _check(ok: object, what: str) -> None:
        if not ok:
            raise OSError(f"{what} failed: {ctypes.WinError(ctypes.get_last_error())}")

    def _run_on_private_desktop(
        cmd: list[str],
        cwd: str | os.PathLike[str] | None,
        timeout: float | None,
        on_output: Callable[[str], None] | None,
        on_start: Callable[[int], None] | None,
    ) -> Outcome:
        desktop = _u32.CreateDesktopW(DESKTOP_NAME, None, None, 0, _GENERIC_ALL, None)
        _check(desktop, "CreateDesktop")
        inherit = _Security(ctypes.sizeof(_Security), None, True)
        read, write, nul = wt.HANDLE(), wt.HANDLE(), None
        job = _k32.CreateJobObjectW(None, None)
        process = thread = None
        try:
            _check(_k32.CreatePipe(ctypes.byref(read), ctypes.byref(write), ctypes.byref(inherit), 0), "CreatePipe")
            _check(_k32.SetHandleInformation(read, _INHERIT, 0), "SetHandleInformation")
            nul = _k32.CreateFileW("NUL", 0x80000000, 3, ctypes.byref(inherit), 3, 0, None)
            limits = _ExtendedLimits()
            limits.basic.flags = _JOB_KILL_ON_CLOSE
            _check(
                _k32.SetInformationJobObject(
                    job, _JOB_EXTENDED_LIMIT_INFO, ctypes.byref(limits), ctypes.sizeof(limits)
                ),
                "SetInformationJobObject",
            )
            info = _StartupInfo()
            info.cb = ctypes.sizeof(info)
            info.desktop = f"WinSta0\\{DESKTOP_NAME}"
            info.flags = _STARTF_USESTDHANDLES
            info.std_in, info.std_out, info.std_err = nul, write, write
            proc = _ProcessInfo()
            flags = _CREATE_SUSPENDED | _CREATE_NO_WINDOW | _CREATE_UNICODE_ENVIRONMENT
            line = ctypes.create_unicode_buffer(subprocess.list2cmdline([str(c) for c in cmd]))
            _check(
                _k32.CreateProcessW(
                    None,
                    line,
                    None,
                    None,
                    True,
                    flags,
                    None,
                    str(cwd) if cwd else None,
                    ctypes.byref(info),
                    ctypes.byref(proc),
                ),
                f"CreateProcess({cmd[0]})",
            )
            process, thread = proc.process, proc.thread
            _check(_k32.AssignProcessToJobObject(job, process), "AssignProcessToJobObject")
            _k32.ResumeThread(thread)
            _k32.CloseHandle(write)  # the program holds the only write end: reading ends when it does
            write = wt.HANDLE()
            if on_start:
                on_start(proc.pid)
            timed_out = threading.Event()

            def kill() -> None:
                timed_out.set()
                _k32.TerminateJobObject(job, 1)

            timer = threading.Timer(timeout, kill) if timeout else None
            if timer:
                timer.start()
            chunks: list[str] = []
            fd = msvcrt.open_osfhandle(read.value, os.O_RDONLY)
            read = wt.HANDLE()  # the file descriptor owns it now
            with os.fdopen(fd, "rb", buffering=0) as stream:
                while data := stream.read(65536):
                    text = data.decode("utf-8", errors="replace")
                    chunks.append(text)
                    if on_output:
                        on_output(text)
            _k32.WaitForSingleObject(process, _INFINITE)
            if timer:
                timer.cancel()
            code = wt.DWORD()
            _k32.GetExitCodeProcess(process, ctypes.byref(code))
            return Outcome(code.value, "".join(chunks), timed_out.is_set())
        finally:
            for handle in (read, write, nul, process, thread):
                if handle:
                    _k32.CloseHandle(handle)
            if job:
                _k32.CloseHandle(job)  # kills anything still running (JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
            _u32.CloseDesktop(desktop)

else:

    def _run_on_private_desktop(*_args: object) -> Outcome:  # pragma: no cover - never called off Windows
        raise NotImplementedError
