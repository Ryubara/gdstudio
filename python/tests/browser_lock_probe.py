"""Headless Chrome takes pointer lock on a page and holds it 0.8 s, the way a browser smoke probe aims a game camera.

Run by test_quiet_run.py through `run_quiet` (never on its own: under pointer lock headless Chrome clips the person's
real cursor to its hidden window, docs/godot/no-focus.md). Prints one JSON line: whether the lock took, and the
desktop this process runs on.

    uv run --with playwright==1.64.1 python browser_lock_probe.py [channel]
"""

import ctypes
import json
import sys
import time
from ctypes import wintypes as wt

from playwright.sync_api import sync_playwright

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


def main() -> None:
    channel = sys.argv[1] if len(sys.argv) > 1 else "chrome"
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, channel=channel)
        page = browser.new_context(viewport={"width": 1280, "height": 720}).new_page()
        page.set_content(PAGE)
        page.mouse.click(640, 360)
        time.sleep(0.8)
        locked = page.evaluate("() => window.locked")
        page.evaluate("() => document.exitPointerLock()")
        browser.close()
    print(json.dumps({"locked": locked, "desktop": desktop_name()}), flush=True)


if __name__ == "__main__":
    main()
