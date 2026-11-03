"""The processes a program started, told from the processes that only name its id as their parent's.

A process table gives every process its parent's id and nothing else. Windows reuses ids fast, and a process whose
parent has exited keeps the dead parent's id: an orphan (Explorer, Windows Terminal, a Firefox background task, the
IME, all there on a CI runner) names an id that a new program can be given. Walking "children of the root" by id then
takes the orphan, and everything below it, for the program's own tree (kit #229: a test found Explorer's `WorkerW`
and Windows Terminal "belonging" to a headless browser). So a process is a child only when it was created after its
parent: an orphan older than the program that took its parent's id is not.

`descendants` is the rule on plain data (it runs on every platform and is tested on a planted table); `tree_of` reads
the real table on Windows.
"""

from __future__ import annotations

import sys
from collections.abc import Callable, Iterable


def descendants(
    pairs: Iterable[tuple[int, int]],
    root: int,
    created: Callable[[int], int | None],
    root_created: int | None = None,
) -> set[int]:
    """`root` and every process below it, from `(pid, parent pid)` pairs.

    `created(pid)` is the creation time of a process (any unit, only compared; `None` when unknown). A process whose
    creation time is unknown, or earlier than its parent's, is not a child. `root_created` is the root's creation
    time as read when it started: if the id now belongs to a process created at another time, the root has exited
    and its id was reused, so the tree is empty.
    """
    pairs = list(pairs)
    now = created(root)
    if root_created is not None and now is not None and now != root_created:
        return set()
    start = root_created if root_created is not None else now
    found = {root}
    born = {root: start}
    while True:
        grown: dict[int, int] = {}
        for pid, parent in pairs:
            if pid in found or parent not in found:
                continue
            birth, parent_birth = created(pid), born[parent]
            if birth is not None and parent_birth is not None and birth >= parent_birth:
                grown[pid] = birth
        if not grown:
            return found
        found |= set(grown)
        born |= grown


if sys.platform == "win32":
    import ctypes
    from ctypes import wintypes as wt

    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _kernel32.CreateToolhelp32Snapshot.restype = wt.HANDLE
    _kernel32.OpenProcess.restype = wt.HANDLE
    _kernel32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
    _kernel32.GetProcessTimes.argtypes = [wt.HANDLE] + [ctypes.POINTER(wt.FILETIME)] * 4
    _kernel32.CloseHandle.argtypes = [wt.HANDLE]
    _QUERY_LIMITED = 0x1000  # PROCESS_QUERY_LIMITED_INFORMATION

    class _Entry(ctypes.Structure):
        _fields_ = [
            ("size", wt.DWORD), ("usage", wt.DWORD), ("pid", wt.DWORD), ("heap", ctypes.c_void_p),
            ("module", wt.DWORD), ("threads", wt.DWORD), ("ppid", wt.DWORD), ("priority", ctypes.c_long),
            ("flags", wt.DWORD), ("exe", ctypes.c_wchar * 260),
        ]  # fmt: skip

    def process_pairs() -> list[tuple[int, int]]:
        """Every running process as `(pid, parent pid)`."""
        snapshot = _kernel32.CreateToolhelp32Snapshot(2, 0)  # TH32CS_SNAPPROCESS
        pairs, entry = [], _Entry()
        entry.size = ctypes.sizeof(_Entry)
        more = _kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while more:
            pairs.append((entry.pid, entry.ppid))
            more = _kernel32.Process32NextW(snapshot, ctypes.byref(entry))
        _kernel32.CloseHandle(snapshot)
        return pairs

    def creation_time(pid: int) -> int | None:
        """When process `pid` was created (100 ns since 1601), `None` if it has exited or cannot be opened."""
        handle = _kernel32.OpenProcess(_QUERY_LIMITED, False, pid)
        if not handle:
            return None
        try:
            made, gone, kernel, user = (wt.FILETIME() for _ in range(4))
            if not _kernel32.GetProcessTimes(handle, made, gone, kernel, user):
                return None
            return (made.dwHighDateTime << 32) | made.dwLowDateTime
        finally:
            _kernel32.CloseHandle(handle)

    def tree_of(root: int, root_created: int | None = None) -> set[int]:
        """`root` and the processes it started, on this machine now. Pass `creation_time(root)` taken when it
        started, so that the tree is empty once the root has exited and its id belongs to another program."""
        return descendants(process_pairs(), root, creation_time, root_created)
