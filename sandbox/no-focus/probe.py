"""Spike: does a launch way leave the foreground window alone? Usage: probe.py <show:0|4|7|none> <godot args...>

Holds the foreground with a window of its own, starts Godot with the given STARTUPINFO show state, polls
GetForegroundWindow every 5 ms until Godot exits and prints one RESULT line.
"""
from pathlib import Path
import ctypes
import ctypes.wintypes as wt
import subprocess
import threading
import sys
import time

u = ctypes.windll.user32
k = ctypes.windll.kernel32
u.GetForegroundWindow.restype = wt.HWND
u.CreateWindowExW.restype = wt.HWND
u.CreateWindowExW.argtypes = [wt.DWORD, wt.LPCWSTR, wt.LPCWSTR, wt.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                              ctypes.c_int, wt.HWND, wt.HANDLE, wt.HANDLE, wt.LPVOID]
u.SetForegroundWindow.argtypes = [wt.HWND]
u.ShowWindow.argtypes = [wt.HWND, ctypes.c_int]
u.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
u.IsWindowVisible.argtypes = [wt.HWND]
u.IsIconic.argtypes = [wt.HWND]
u.GetWindowRect.argtypes = [wt.HWND, ctypes.POINTER(wt.RECT)]

WS_VISIBLE, WS_OVERLAPPEDWINDOW = 0x10000000, 0x00CF0000


def make_holder() -> int:
    """A window that owns the foreground, with its own thread pumping messages (a hung window stalls Godot)."""
    box: list[int] = []

    def run() -> None:
        h = u.CreateWindowExW(0, "STATIC", "GDS-focus-holder", WS_VISIBLE | WS_OVERLAPPEDWINDOW, 50, 50, 300, 200,
                              None, None, None, None)
        box.append(h)
        msg = wt.MSG()
        while u.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            u.TranslateMessage(ctypes.byref(msg))
            u.DispatchMessageW(ctypes.byref(msg))

    threading.Thread(target=run, daemon=True).start()
    while not box:
        time.sleep(0.01)
    h = box[0]
    for _ in range(40):
        u.keybd_event(0x12, 0, 0, 0)  # Alt down/up lets SetForegroundWindow through
        u.keybd_event(0x12, 0, 2, 0)
        u.SetForegroundWindow(h)
        time.sleep(0.05)
        if u.GetForegroundWindow() == h:
            return h
    raise SystemExit("could not take the foreground for the holder window")


def pid_of(hwnd) -> int:
    pid = wt.DWORD()
    u.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return pid.value


def title_of(hwnd) -> str:
    buf = ctypes.create_unicode_buffer(128)
    u.GetClassNameW(hwnd, buf, 128)
    cls = buf.value
    u.GetWindowTextW(hwnd, buf, 128)
    return f"{cls}:{buf.value[:40]}"


def windows_of(pid: int) -> list[str]:
    found: list[str] = []
    cb = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)

    def each(hwnd, _):
        if pid_of(hwnd) in tree(pid) and u.IsWindowVisible(hwnd) and title_of(hwnd).startswith("Engine"):
            r = wt.RECT()
            u.GetWindowRect(hwnd, ctypes.byref(r))
            found.append(f"pid={pid_of(hwnd)} iconic={bool(u.IsIconic(hwnd))} rect=({r.left},{r.top},{r.right},{r.bottom})")
        return True

    u.EnumWindows(cb(each), 0)
    return found


class PE(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("pid", wt.DWORD), ("heap", ctypes.c_void_p),
                ("modid", wt.DWORD), ("threads", wt.DWORD), ("ppid", wt.DWORD), ("pri", ctypes.c_long),
                ("flags", wt.DWORD), ("exe", ctypes.c_wchar * 260)]


def tree(root: int) -> set[int]:
    """root and every process below it."""
    k.CreateToolhelp32Snapshot.restype = wt.HANDLE
    snap = k.CreateToolhelp32Snapshot(2, 0)
    pairs = []
    e = PE()
    e.dwSize = ctypes.sizeof(PE)
    ok = k.Process32FirstW(snap, ctypes.byref(e))
    while ok:
        pairs.append((e.pid, e.ppid))
        ok = k.Process32NextW(snap, ctypes.byref(e))
    k.CloseHandle(snap)
    out = {root}
    grew = True
    while grew:
        grew = False
        for pid, ppid in pairs:
            if ppid in out and pid not in out:
                out.add(pid)
                grew = True
    return out


def main() -> int:
    show = sys.argv[1]
    cmd = sys.argv[2:]
    holder = make_holder()
    si = None
    if show not in ("none", "desktop"):
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = int(show)
    t0 = time.time()
    if show == "desktop":
        sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python" / "src"))
        from gds_tools.quiet_run import run_quiet

        pids: list[int] = []
        res = []
        th = threading.Thread(target=lambda: res.append(run_quiet(cmd, timeout=60, on_start=pids.append)))
        th.start()
        bad = set()
        while th.is_alive():
            fg = u.GetForegroundWindow()
            if fg != holder and fg and pids and pid_of(fg) in tree(pids[0]):
                bad.add(title_of(fg))
            time.sleep(0.02)
        out = res[0].output
        print(f"RESULT show=desktop stolen={sorted(bad) or 'no'} fg_after_is_holder={u.GetForegroundWindow() == holder} "
              f"seconds={time.time() - t0:.1f} rc={res[0].returncode}")
        for l in [l for l in out.splitlines() if "PROBE" in l or "ERROR" in l]:
            print("  ", l)
        u.PostMessageW(holder, 0x0010, 0, 0)
        return 0
    p = subprocess.Popen(cmd, startupinfo=si, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace")
    lines: list[str] = []
    threading.Thread(target=lambda: [lines.append(l) for l in p.stdout], daemon=True).start()
    mine = {p.pid}
    stolen_by: set[str] = set()
    first_steal = None
    seen_windows: list[str] = []
    t_win = None
    while p.poll() is None and time.time() - t0 < 25:
        fg = u.GetForegroundWindow()
        if fg != holder and fg and pid_of(fg) in mine:
            stolen_by.add(title_of(fg))
            first_steal = first_steal or round(time.time() - t0, 3)
        mine = tree(p.pid)
        if not seen_windows and time.time() - t0 > 3:
            seen_windows = [w for w in windows_of(p.pid)]
            if seen_windows: t_win = round(time.time() - t0, 2)
        time.sleep(0.02)
    p.wait()
    time.sleep(0.3)
    out = ''.join(lines)
    fg_after = u.GetForegroundWindow()
    probe = [l for l in out.splitlines() if "PROBE" in l]
    errors = [l for l in out.splitlines() if "ERROR" in l]
    print(f"RESULT show={show} godot_pid={p.pid} stolen={'YES by %s at %ss' % (sorted(stolen_by), first_steal) if stolen_by else 'no'}"
          f" fg_after_is_holder={fg_after == holder} seconds={time.time() - t0:.1f} rc={p.returncode}"
          f" window@{t_win}s={seen_windows} errors={len(errors)}")
    for l in probe + errors[:5]:
        print("  ", l)
    u.PostMessageW(holder, 0x0010, 0, 0)
    return 0


sys.exit(main())
