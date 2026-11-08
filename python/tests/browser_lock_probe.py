"""Headless Chrome takes pointer lock on a page and holds it 0.8 s, the way a browser smoke probe aims a game camera.

Run by test_quiet_run.py through `run_quiet` (never on its own: under pointer lock headless Chrome clips the person's
real cursor to its hidden window, docs/engines/godot/no-focus.md). Prints one JSON line: whether the lock took, the
desktop
this process runs on, and the longest time (ms) the cursor clip differed from the free one while the lock lasted, seen
from this process (so the test needs no sampler of its own to be scheduled against the guard).

    uv run --with playwright==1.64.1 python browser_lock_probe.py [channel]
"""

import ctypes
import json
import sys
import time
from ctypes import wintypes as wt

PAGE = """<canvas id=c width=1280 height=720></canvas><script>
const c = document.getElementById('c'); window.locked = false;
document.addEventListener('pointerlockchange', () => { window.locked = document.pointerLockElement === c; });
c.addEventListener('click', () => c.requestPointerLock());</script>"""


def desktop_name() -> str:
    user32, kernel32 = ctypes.WinDLL("user32"), ctypes.WinDLL("kernel32")
    user32.GetThreadDesktop.restype = wt.HANDLE
    user32.GetUserObjectInformationW.argtypes = [wt.HANDLE, ctypes.c_int, wt.LPVOID, wt.DWORD, wt.LPVOID]
    name = ctypes.create_unicode_buffer(256)
    user32.GetUserObjectInformationW(user32.GetThreadDesktop(kernel32.GetCurrentThreadId()), 2, name, 512, None)
    return name.value


LOCK_SECONDS = 2.5  # longer than the test's bound on a held clip, so a missing guard is held past it


def clip() -> tuple[int, int, int, int]:
    rect = wt.RECT()
    ctypes.WinDLL("user32").GetClipCursor(ctypes.byref(rect))
    return rect.left, rect.top, rect.right, rect.bottom


Rect = tuple[int, int, int, int]


def poll(seconds: float, read=clip, clock=time.perf_counter, sleep=time.sleep) -> list[tuple[float, Rect]]:  # noqa: ANN001
    """Read the clip every millisecond for `seconds`: (time, clip) pairs. `read`, `clock` and `sleep` are replaced in
    the test of this module, which needs no real cursor."""
    samples, end = [], clock() + seconds
    while clock() < end:
        samples.append((clock(), read()))
        sleep(0.001)
    return samples


def free_clip(rects: list[Rect]) -> Rect:
    """The free clip is the whole screen and any clip a program sets is inside it: the biggest rectangle seen. (Not just
    the one read before the lock: another program's clip, such as a parallel run of this test, can be set then.)"""
    return max(rects, key=lambda r: max(0, r[2] - r[0]) * max(0, r[3] - r[1]))


def longest_held_ms(samples: list[tuple[float, Rect]], free: Rect) -> float:
    """The longest stretch (ms) from a poll that saw the clip held to the first poll that saw it free again."""
    longest, since = 0.0, None
    for now, rect in samples:
        if rect != free and since is None:
            since = now
        if since is not None:
            longest = max(longest, (now - since) * 1000)
        if rect == free:
            since = None
    return round(longest, 1)


def main() -> None:
    from playwright.sync_api import sync_playwright

    channel = sys.argv[1] if len(sys.argv) > 1 else "chrome"
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, channel=channel)
        page = browser.new_context(viewport={"width": 1280, "height": 720}).new_page()
        page.set_content(PAGE)
        before = clip()
        page.mouse.click(640, 360)
        samples = poll(LOCK_SECONDS)
        locked = page.evaluate("() => window.locked")
        page.evaluate("() => document.exitPointerLock()")
        browser.close()
        free = free_clip([before, clip(), *(rect for _, rect in samples)])
        held_ms = longest_held_ms(samples, free)
    print(json.dumps({"locked": locked, "desktop": desktop_name(), "held_ms": held_ms}), flush=True)


if __name__ == "__main__":
    main()
