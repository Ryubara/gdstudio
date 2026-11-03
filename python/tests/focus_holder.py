"""A test window that owns the foreground and counts the keystrokes that reach it (Windows only).

`Holder` is what a person typing in an editor is: a window with the keyboard focus. `type_key()` presses F24, a key no
program binds, the way a keyboard does (`keybd_event` goes to the foreground window's focus), and `received` counts
what arrived: if a program stole the keyboard, the count falls behind `sent`. `process_tree` finds a program's
children, to tell its windows from the rest of the machine's.
"""

from __future__ import annotations

import ctypes
import threading
import time
from ctypes import wintypes as wt

from process_tree import tree_of

VK_F24 = 0x87
WM_KEYDOWN = 0x0100
WM_CLOSE = 0x0010
WS_VISIBLE_OVERLAPPED = 0x10CF0000

_user32 = ctypes.WinDLL("user32", use_last_error=True)
_kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
_WNDPROC = ctypes.WINFUNCTYPE(ctypes.c_ssize_t, wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM)


class _WindowClass(ctypes.Structure):
    _fields_ = [
        ("style", wt.UINT), ("proc", _WNDPROC), ("class_extra", ctypes.c_int), ("window_extra", ctypes.c_int),
        ("instance", wt.HANDLE), ("icon", wt.HANDLE), ("cursor", wt.HANDLE), ("background", wt.HANDLE),
        ("menu", wt.LPCWSTR), ("name", wt.LPCWSTR),
    ]  # fmt: skip


_user32.GetForegroundWindow.restype = wt.HWND
_user32.CreateWindowExW.restype = wt.HWND
_user32.CreateWindowExW.argtypes = [
    wt.DWORD, wt.LPCWSTR, wt.LPCWSTR, wt.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    wt.HWND, wt.HANDLE, wt.HANDLE, wt.LPVOID,
]  # fmt: skip
_user32.DefWindowProcW.restype = ctypes.c_ssize_t
_user32.DefWindowProcW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
_user32.RegisterClassW.argtypes = [ctypes.POINTER(_WindowClass)]
_user32.SetForegroundWindow.argtypes = [wt.HWND]
_user32.PostMessageW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
_user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
_user32.IsWindowVisible.argtypes = [wt.HWND]
_user32.AttachThreadInput.argtypes = [wt.DWORD, wt.DWORD, wt.BOOL]


def visible_windows_of(pids: set[int]) -> list[str]:
    """The visible top-level windows of `pids` on the desktop this program sees (the one the person works on)."""
    found: list[str] = []

    def each(window: int, _: int) -> bool:
        pid = wt.DWORD()
        _user32.GetWindowThreadProcessId(window, ctypes.byref(pid))
        if pid.value in pids and _user32.IsWindowVisible(window):
            name = ctypes.create_unicode_buffer(64)
            _user32.GetClassNameW(window, name, 64)
            found.append(name.value)
        return True

    _user32.EnumWindows(ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)(each), 0)
    return found


class Holder:
    def __init__(self) -> None:
        self.handle: int | None = None
        self.received = 0
        self.sent = 0
        self._proc = _WNDPROC(self._on_message)  # kept alive for as long as the window
        threading.Thread(target=self._pump, daemon=True).start()
        deadline = time.time() + 5
        while self.handle is None and time.time() < deadline:
            time.sleep(0.01)

    def _on_message(self, window: int, message: int, wparam: int, lparam: int) -> int:
        if message == WM_KEYDOWN and wparam == VK_F24:
            self.received += 1
        return _user32.DefWindowProcW(window, message, wparam, lparam)

    def _pump(self) -> None:
        cls = _WindowClass()
        cls.proc, cls.name = self._proc, f"GdsFocusHolder{id(self)}"
        _user32.RegisterClassW(ctypes.byref(cls))
        self.handle = _user32.CreateWindowExW(
            0, cls.name, "gds-focus-holder", WS_VISIBLE_OVERLAPPED, 50, 50, 300, 200, None, None, None, None
        )
        message = wt.MSG()
        while _user32.GetMessageW(ctypes.byref(message), None, 0, 0) > 0:
            _user32.TranslateMessage(ctypes.byref(message))
            _user32.DispatchMessageW(ctypes.byref(message))

    def take_foreground(self) -> bool:
        """Become the foreground window by sharing the current foreground thread's input queue for a moment (a tap on
        Alt works too but leaves the window in menu mode, which swallows the next key)."""
        for _ in range(40):
            front = _user32.GetWindowThreadProcessId(_user32.GetForegroundWindow(), None)
            mine = _kernel32.GetCurrentThreadId()
            _user32.AttachThreadInput(mine, front, True)
            _user32.SetForegroundWindow(self.handle)
            _user32.AttachThreadInput(mine, front, False)
            time.sleep(0.05)
            if self.has_foreground():
                return True
        return False

    def has_foreground(self) -> bool:
        return _user32.GetForegroundWindow() == self.handle

    def foreground_owner(self) -> int | None:
        """The process id that owns the foreground window."""
        pid = wt.DWORD()
        _user32.GetWindowThreadProcessId(_user32.GetForegroundWindow(), ctypes.byref(pid))
        return pid.value or None

    def type_key(self) -> None:
        """Press F24; counted in `sent` only when this window had the foreground a moment before (the person at the
        machine may switch windows too: a key sent while another window is in front is not the program's fault)."""
        if not self.has_foreground():
            return
        self.sent += 1
        _user32.keybd_event(VK_F24, 0, 0, 0)
        _user32.keybd_event(VK_F24, 0, 2, 0)

    def close(self) -> None:
        _user32.PostMessageW(self.handle, WM_CLOSE, 0, 0)


def process_tree(root: int, root_created: int | None = None) -> set[int]:
    """`root` and every process started below it (Godot's console program starts the real one); see `process_tree.py`
    for why a process counts only when it was created after its parent. `root_created` is `creation_time(root)` read
    when the root started: with it the tree is empty once the root exited and its id went to another program."""
    return tree_of(root, root_created)
