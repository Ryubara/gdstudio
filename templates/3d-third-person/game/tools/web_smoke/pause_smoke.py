"""The pause menu and the settings in the web build, on a computer: pointer lock, Esc and a saved file.

Serves the exported game (`build/web`), opens it with `?probe&play` in desktop Chromium and reads what the
game's `WebProbe` writes to `window.gdprobe`:

- a click on the page takes pointer lock, and the game reads its mouse as captured;
- letting the lock go (`document.exitPointerLock()`, which is what the browser's own first Esc does) opens the
  pause menu in the same moment: the tree is paused, a screen is up and the mouse is free;
- Enter on the menu (Resume has the focus) closes it, and a click takes the lock again;
- Esc opens the menu and Esc again closes it;
- through the keys alone the menu opens the settings, the Audio tab and its first slider, and a change of the
  volume is in the page's saved files (IndexedDB) a moment later and is applied again after a reload;
- no console message is an error.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/pause_smoke.py build/web build/smoke

Screenshots and `result.json` go to the second argument. Exits 1 on any check that fails. Run it under `gds quiet`:
headless Chrome under pointer lock clips the real cursor.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

PAGE_W = 1280
PAGE_H = 720
READY_TIMEOUT_S = 120.0
KEY_HOLD_S = 0.15
CAPTURED = 2  # Input.MOUSE_MODE_CAPTURED
SETTINGS_FILE = "settings.cfg"
SAVED_VOLUME = 80
VOLUME_STEPS_LEFT = 4  # the slider moves 5 a key press: 100 to 80


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:  # noqa: D102
        return


def serve(folder: Path) -> tuple[http.server.ThreadingHTTPServer, int]:
    handler = functools.partial(QuietHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def probe(page: Page) -> dict:
    return page.evaluate("Object.assign({}, window.gdprobe || {})")


def wait_for(page: Page, test, seconds: float) -> dict:
    """Polls the probe until `test(state)` holds or the time is up; returns the last state."""
    end = time.time() + seconds
    state = probe(page)
    while time.time() < end:
        state = probe(page)
        if test(state):
            break
        time.sleep(0.1)
    return state


def tap(page: Page, key: str) -> None:
    """Holds a key for about a frame and a half at least: Godot reads input once a frame."""
    page.keyboard.down(key)
    time.sleep(KEY_HOLD_S)
    page.keyboard.up(key)
    time.sleep(0.25)


def lock_element(page: Page) -> str:
    return page.evaluate("document.pointerLockElement ? document.pointerLockElement.tagName : ''")


def saved_settings(page: Page) -> str:
    """The text of the settings file in the page's IndexedDB, or an empty string."""
    script = """
    () => new Promise((resolve) => {
      const open = indexedDB.open('/userfs');
      open.onerror = () => resolve('');
      open.onsuccess = () => {
        const db = open.result;
        if (!db.objectStoreNames.contains('FILE_DATA')) { resolve(''); return; }
        const store = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA');
        const keys = store.getAllKeys();
        keys.onsuccess = () => {
          const key = keys.result.find((k) => String(k).endsWith('/%s'));
          if (!key) { resolve(''); return; }
          const get = store.get(key);
          get.onsuccess = () => resolve(new TextDecoder().decode(get.result.contents));
        };
      };
    })
    """ % SETTINGS_FILE
    return page.evaluate(script)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export's folder (build/web)")
    parser.add_argument("out", type=Path, help="where the screenshots and result.json go")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server, port = serve(args.build)
    checks: dict[str, dict] = {}
    problems: list[str] = []
    console_errors: list[str] = []

    def check(name: str, ok: bool, detail: str) -> None:
        checks[name] = {"ok": bool(ok), "detail": detail}
        if not ok:
            problems.append(f"{name}: {detail}")

    url = f"http://127.0.0.1:{port}/index.html?probe&play"
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        context = browser.new_context(viewport={"width": PAGE_W, "height": PAGE_H})
        page = context.new_page()
        page.on("console", lambda m: console_errors.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: console_errors.append(str(e)))
        page.goto(url, wait_until="load")
        state = wait_for(page, lambda s: s.get("ready") is True and "touch_shown" in s, READY_TIMEOUT_S)
        if not state.get("ready"):
            print("the game never reported ready", file=sys.stderr)
            return 1
        time.sleep(2.0)

        # 1. A click takes the lock.
        page.mouse.click(PAGE_W / 2, PAGE_H / 2)
        state = wait_for(page, lambda s: s.get("mouse_mode") == CAPTURED, 3.0)
        check("a click takes pointer lock", lock_element(page) == "CANVAS", f"lock on {lock_element(page)!r}")
        check("the game reads its mouse as captured", state.get("mouse_mode") == CAPTURED, f"mouse_mode={state.get('mouse_mode')}")
        check("nothing is paused while playing", state.get("paused") is False and state.get("screens") == 0, f"paused={state.get('paused')} screens={state.get('screens')}")

        # 2. Letting the lock go (the browser's first Esc) opens the pause menu.
        released = time.time()
        page.evaluate("document.exitPointerLock()")
        state = wait_for(page, lambda s: s.get("paused") is True, 3.0)
        opened_in = time.time() - released
        page.screenshot(path=str(args.out / "desktop_pause.png"))
        check("losing the lock opens the pause menu", state.get("paused") is True and state.get("screens") == 1, f"paused={state.get('paused')} screens={state.get('screens')} after {opened_in:.2f} s")
        check("the mouse is free on the menu", state.get("mouse_mode") != CAPTURED and lock_element(page) == "", f"mouse_mode={state.get('mouse_mode')}")
        check("Resume has the focus", state.get("focus_text") == "Resume", f"focus on {state.get('focus_text')!r}")

        # 3. Enter resumes; a click takes the lock again.
        tap(page, "Enter")
        state = wait_for(page, lambda s: s.get("paused") is False and s.get("screens") == 0, 3.0)
        check("Enter on Resume closes the menu", state.get("paused") is False and state.get("screens") == 0, f"paused={state.get('paused')} screens={state.get('screens')}")
        page.mouse.click(PAGE_W / 2, PAGE_H / 2)
        state = wait_for(page, lambda s: s.get("mouse_mode") == CAPTURED, 3.0)
        check("a click after Resume takes the lock again", lock_element(page) == "CANVAS" and state.get("mouse_mode") == CAPTURED, f"lock on {lock_element(page)!r}, mouse_mode={state.get('mouse_mode')}")

        # 3b. A click on Resume closes the menu and takes the lock again, in the same gesture.
        page.evaluate("document.exitPointerLock()")
        state = wait_for(page, lambda s: s.get("paused") is True and "btn_resume_x" in s, 3.0)
        time.sleep(0.8)
        scale = 1080.0 / PAGE_H  # canvas units to CSS pixels: the project's canvas is 1080 high
        page.mouse.click(state["btn_resume_x"] / scale, state["btn_resume_y"] / scale)
        state = wait_for(page, lambda s: s.get("paused") is False and s.get("mouse_mode") == CAPTURED, 3.0)
        check("a click on Resume closes the menu", state.get("paused") is False and state.get("screens") == 0, f"paused={state.get('paused')} screens={state.get('screens')}")
        check("the click on Resume takes the lock again", lock_element(page) == "CANVAS" and state.get("mouse_mode") == CAPTURED, f"lock on {lock_element(page)!r}, mouse_mode={state.get('mouse_mode')}")

        # 4. Esc opens the menu and Esc closes it.
        tap(page, "Escape")
        state = wait_for(page, lambda s: s.get("paused") is True, 3.0)
        check("Esc opens the pause menu", state.get("paused") is True, f"paused={state.get('paused')} screens={state.get('screens')}")
        tap(page, "Escape")
        state = wait_for(page, lambda s: s.get("paused") is False, 3.0)
        check("Esc again closes it", state.get("paused") is False and state.get("screens") == 0, f"paused={state.get('paused')} screens={state.get('screens')}")

        # 5. Through the keys: menu, Settings, the Audio tab, its first slider, a change of volume.
        tap(page, "Escape")
        wait_for(page, lambda s: s.get("paused") is True, 3.0)
        tap(page, "ArrowDown")
        state = probe(page)
        check("Down moves from Resume to Settings", state.get("focus_text") == "Settings", f"focus on {state.get('focus_text')!r}")
        tap(page, "Enter")
        state = wait_for(page, lambda s: s.get("screens") == 2, 3.0)
        check("Enter on Settings opens the settings screen", state.get("screens") == 2, f"screens={state.get('screens')}")
        tap(page, "ArrowRight")
        tap(page, "Enter")
        tap(page, "ArrowDown")
        state = wait_for(page, lambda s: s.get("volume_master") == 100, 2.0)
        for _ in range(VOLUME_STEPS_LEFT):
            tap(page, "ArrowLeft")
        state = wait_for(page, lambda s: s.get("volume_master") == SAVED_VOLUME, 3.0)
        page.screenshot(path=str(args.out / "desktop_settings.png"))
        check("the keys change the volume", state.get("volume_master") == SAVED_VOLUME, f"volume_master={state.get('volume_master')}")
        end = time.time() + 5.0
        text = ""
        while time.time() < end:
            text = saved_settings(page)
            if f"master={SAVED_VOLUME}" in text:
                break
            time.sleep(0.25)
        check("the change is in the saved file", f"master={SAVED_VOLUME}" in text, "settings.cfg in IndexedDB: " + (text.replace("\n", " | ")[:160] or "not found"))

        # 6. Esc steps back, Esc closes, and the game runs on.
        tap(page, "Escape")
        state = wait_for(page, lambda s: s.get("screens") == 1, 3.0)
        check("Esc on the settings goes back to the pause menu", state.get("screens") == 1 and state.get("paused") is True, f"screens={state.get('screens')}")
        tap(page, "Escape")
        state = wait_for(page, lambda s: s.get("paused") is False, 3.0)
        check("Esc on the pause menu resumes", state.get("paused") is False and state.get("screens") == 0, f"paused={state.get('paused')} screens={state.get('screens')}")
        check("no console error or page error", not console_errors, "; ".join(console_errors[:5]) or "none")

        # 7. After a reload the saved volume is applied at start.
        page.reload(wait_until="load")
        state = wait_for(page, lambda s: s.get("ready") is True and "touch_shown" in s, READY_TIMEOUT_S)
        time.sleep(1.0)
        state = probe(page)
        check("the saved volume is applied after a reload", state.get("volume_master") == SAVED_VOLUME, f"volume_master={state.get('volume_master')}")
        browser.close()
    server.shutdown()
    result = {"checks": checks, "problems": problems}
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    for name, entry in checks.items():
        print(("ok   " if entry["ok"] else "FAIL ") + name + " (" + entry["detail"] + ")")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
