"""The menus on a phone in the web build: real touches from the main menu into the game and back out.

Serves the exported game (`build/web`), opens it with `?probe` (no `play`: the menu) in Chromium with mobile
emulation (844 x 390 CSS px at a pixel ratio of 2, touch events through the DevTools protocol) and reads what the
`MenuProbe` and `WebProbe` write to `window.gdprobe`, tapping the middle of the buttons the probe reports:

- the main menu is up, its Play button has the focus, and Quit is not offered in a browser;
- a tap on Play loads the game: the touch layer shows and the menu's screens are gone;
- a tap on the Menu button pauses the game and opens the pause menu, and the buttons of the menu take taps (touch-to-mouse
  is on again while it is up);
- a tap on Settings opens the settings, a tap on the Audio tab shows it, a tap on Back returns to the pause menu;
- a tap on Resume gives the game back: nothing is paused and a tap on the jump button jumps;
- no console message is an error.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/menu_smoke.py build/web build/smoke

Screenshots and `result.json` go to the second argument. Exits 1 on any check that fails. Run it under `gds quiet`.
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

PAGE_W = 844
PAGE_H = 390
RATIO = 2
READY_TIMEOUT_S = 120.0


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


class Finger:
    """One finger tapping through the DevTools protocol, in CSS pixels."""

    def __init__(self, page: Page) -> None:
        self.cdp = page.context.new_cdp_session(page)

    def tap(self, x: float, y: float, hold: float = 0.12) -> None:
        point = {"x": x, "y": y, "id": 1}
        self.cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [point]})
        time.sleep(hold)
        self.cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": [point]})
        time.sleep(0.3)


def button(state: dict, text: str, scale: float) -> tuple[float, float] | None:
    """The middle of the visible button with this text, in CSS pixels (the probe gives canvas units)."""
    key = text.lower().replace(" ", "_")
    if f"btn_{key}_x" not in state:
        return None
    return state[f"btn_{key}_x"] / scale, state[f"btn_{key}_y"] / scale


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

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        context = browser.new_context(
            viewport={"width": PAGE_W, "height": PAGE_H}, device_scale_factor=RATIO, is_mobile=True, has_touch=True
        )
        page = context.new_page()
        page.on("console", lambda m: console_errors.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: console_errors.append(str(e)))
        page.goto(f"http://127.0.0.1:{port}/index.html?probe", wait_until="load")
        state = wait_for(page, lambda s: s.get("menu") is True and s.get("screens") == 1, READY_TIMEOUT_S)
        if not state.get("menu"):
            print("the menu never reported", file=sys.stderr)
            return 1
        time.sleep(1.0)
        state = probe(page)
        scale = state["canvas_h"] / PAGE_H
        finger = Finger(page)
        page.screenshot(path=str(args.out / "phone_main_menu.png"))
        check("the main menu is up with Play focused", state.get("focus_text") == "Play", f"focus on {state.get('focus_text')!r}")
        check("Quit is not offered in a browser", "btn_quit_x" not in state, "no Quit button reported")

        # 1. Play loads the game.
        play = button(state, "Play", scale)
        finger.tap(*play)
        state = wait_for(page, lambda s: s.get("menu") is None and s.get("ready") is True and "touch_shown" in s, READY_TIMEOUT_S)
        time.sleep(2.0)
        state = probe(page)
        check("a tap on Play loads the game", state.get("menu") is None and "touch_shown" in state, f"menu={state.get('menu')}")
        check("the touch layer shows and no screen is up", state.get("touch_shown") is True and state.get("screens") == 0, f"touch_shown={state.get('touch_shown')} screens={state.get('screens')}")
        check("the Menu button shows on the touch screen", state.get("pause_shown") is True, f"pause_shown={state.get('pause_shown')}")
        page.screenshot(path=str(args.out / "phone_game.png"))

        # 2. The Menu button pauses the game.
        finger.tap(state["pause_x"] / scale, state["pause_y"] / scale)
        state = wait_for(page, lambda s: s.get("paused") is True, 3.0)
        time.sleep(0.8)
        page.screenshot(path=str(args.out / "phone_pause.png"))
        check("a tap on Menu pauses the game and opens the pause menu", state.get("paused") is True and state.get("screens") == 1, f"paused={state.get('paused')} screens={state.get('screens')}")

        # 3. Settings, the Audio tab, Back.
        state = probe(page)
        finger.tap(*button(state, "Settings", scale))
        state = wait_for(page, lambda s: s.get("screens") == 2, 3.0)
        check("a tap on Settings opens the settings", state.get("screens") == 2, f"screens={state.get('screens')}")
        time.sleep(0.6)
        state = probe(page)
        finger.tap(*button(state, "Audio", scale))
        time.sleep(0.8)
        page.screenshot(path=str(args.out / "phone_settings_audio.png"))
        state = probe(page)
        check("the Audio tab takes the tap", "btn_audio_x" in state, "tabs reported")
        finger.tap(*button(state, "Back", scale))
        state = wait_for(page, lambda s: s.get("screens") == 1, 3.0)
        check("a tap on Back returns to the pause menu", state.get("screens") == 1 and state.get("paused") is True, f"screens={state.get('screens')} paused={state.get('paused')}")

        # 4. Resume gives the game back: a tap on the jump button jumps.
        time.sleep(0.5)
        state = probe(page)
        finger.tap(*button(state, "Resume", scale))
        state = wait_for(page, lambda s: s.get("paused") is False and s.get("screens") == 0, 3.0)
        check("a tap on Resume closes the menu and unpauses", state.get("paused") is False and state.get("screens") == 0, f"paused={state.get('paused')} screens={state.get('screens')}")
        time.sleep(1.0)
        before = probe(page)
        finger.tap(before["button0_x"] / scale, before["button0_y"] / scale, hold=0.3)
        after = wait_for(page, lambda s: s.get("jumps", 0) > before.get("jumps", 0), 3.0)
        check("the game answers touch again after Resume", after.get("jumps", 0) == before.get("jumps", 0) + 1, f"jumps {before.get('jumps')} to {after.get('jumps')}")

        check("no console error or page error", not console_errors, "; ".join(console_errors[:5]) or "none")
        browser.close()
    server.shutdown()
    result = {"checks": checks, "problems": problems, "scale": scale}
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    for name, entry in checks.items():
        print(("ok   " if entry["ok"] else "FAIL ") + name + " (" + entry["detail"] + ")")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
