"""The web build on a phone: real touches in a phone-sized browser drive the stick, the look drag and the buttons.

Serves the exported game (`build/web`), opens it with `?probe&play` (the game, not the menu) in Chromium with mobile emulation (844 x 390 CSS px at a
pixel ratio of 2, touch events sent through the DevTools protocol, `Input.dispatchTouchEvent`) and reads what the
game's `WebProbe` writes to `window.gdprobe`:

- the layer shows at once on a touch screen and no console message is an error;
- a look drag turns the camera by the designed angle (the layer's `look_sensitivity` times the drag in canvas pixels)
  and moves nothing else;
- the stick moves the character along the camera's heading and turns nothing;
- a tap on the jump button jumps;
- the crouch button crouches, the aim button aims and the fire button shoots;
- with two fingers down at once (the stick and a look drag) each does only its own job, and lifting one leaves the
  other working.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_smoke.py build/web build/smoke

Screenshots and `result.json` go to the second argument. Exits 1 on any check that fails. Run it under `gds quiet`.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import math
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

PAGE_W = 844
PAGE_H = 390
RATIO = 2
READY_TIMEOUT_S = 120.0
LOOK_SENSITIVITY_DEG_PER_PX = 0.1  # TouchControls.look_sensitivity, the scene's value.
LOOK_TOLERANCE = 0.2
STEPS = 12
STEP_PERIOD_S = 0.03


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:  # noqa: D102
        return


def serve(folder: Path) -> tuple[http.server.ThreadingHTTPServer, int]:
    handler = functools.partial(QuietHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


class Finger:
    """A touch point driven through the DevTools protocol."""

    def __init__(self, cdp, ident: int, x: float, y: float) -> None:
        self.cdp = cdp
        self.ident = ident
        self.x = x
        self.y = y

    def point(self) -> dict:
        return {"x": self.x, "y": self.y, "id": self.ident}


class Hand:
    """Every finger down at once: a touch event carries all of them."""

    def __init__(self, page: Page) -> None:
        self.cdp = page.context.new_cdp_session(page)
        self.fingers: dict[int, Finger] = {}

    def _send(self, kind: str) -> None:
        points = [finger.point() for finger in self.fingers.values()]
        self.cdp.send("Input.dispatchTouchEvent", {"type": kind, "touchPoints": points})

    def down(self, ident: int, x: float, y: float) -> None:
        self.fingers[ident] = Finger(self.cdp, ident, x, y)
        self._send("touchStart")

    def move(self, ident: int, x: float, y: float) -> None:
        self.fingers[ident].x = x
        self.fingers[ident].y = y
        self._send("touchMove")

    def drag(self, moves: dict[int, tuple[float, float]], steps: int = STEPS) -> None:
        """Moves several fingers together, in `steps` equal steps."""
        starts = {i: (self.fingers[i].x, self.fingers[i].y) for i in moves}
        for step in range(1, steps + 1):
            share = step / steps
            for ident, (x, y) in moves.items():
                self.fingers[ident].x = starts[ident][0] + (x - starts[ident][0]) * share
                self.fingers[ident].y = starts[ident][1] + (y - starts[ident][1]) * share
            self._send("touchMove")
            time.sleep(STEP_PERIOD_S)

    def up(self, ident: int) -> None:
        """Lifts one finger: `touchEnd` carries the finger that lifts, the others stay down."""
        finger = self.fingers.pop(ident)
        self.cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": [finger.point()]})


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


def angle_between(a: float, b: float) -> float:
    return (b - a + 180.0) % 360.0 - 180.0


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
            viewport={"width": PAGE_W, "height": PAGE_H},
            device_scale_factor=RATIO,
            is_mobile=True,
            has_touch=True,
        )
        page = context.new_page()
        page.on("console", lambda m: console_errors.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: console_errors.append(str(e)))
        page.goto(f"http://127.0.0.1:{port}/index.html?probe&play", wait_until="load")
        state = wait_for(page, lambda s: s.get("ready") is True and s.get("touch_shown") is not None, READY_TIMEOUT_S)
        if not state.get("ready"):
            print("the game never reported ready", file=sys.stderr)
            return 1
        time.sleep(3.0)
        state = probe(page)
        scale = state["canvas_h"] / PAGE_H
        css = lambda key: state[key] / scale  # noqa: E731 - a canvas pixel in CSS pixels
        check("shown at once on a touch screen", state["touch_shown"] is True, f"touch_shown={state['touch_shown']}")
        page.screenshot(path=str(args.out / "phone_idle.png"))
        hand = Hand(page)

        # 1. A look drag turns the camera by the designed angle and moves nothing else.
        before = probe(page)
        hand.down(1, 600, 200)
        hand.drag({1: (600 + 120, 200)})
        time.sleep(0.8)
        hand.up(1)
        time.sleep(0.8)
        after = probe(page)
        want = -120.0 * scale * LOOK_SENSITIVITY_DEG_PER_PX
        got = angle_between(before["yaw"], after["yaw"])
        moved = math.dist((before["x"], before["z"]), (after["x"], after["z"]))
        check("a look drag turns by the designed angle", abs(got - want) <= abs(want) * LOOK_TOLERANCE, f"turned {got:.1f} deg, designed {want:.1f}")
        check("a look drag moves nothing", moved < 0.05, f"moved {moved:.3f} m")

        # 2. The stick moves the character along the camera and turns nothing.
        before = probe(page)
        stick_x, stick_y = css("home_x"), css("home_y")
        hand.down(2, stick_x, stick_y)
        hand.drag({2: (stick_x, stick_y - 40)}, steps=6)
        time.sleep(1.2)
        mid = probe(page)
        page.screenshot(path=str(args.out / "phone_stick_down.png"))
        hand.up(2)
        time.sleep(0.8)
        after = probe(page)
        travelled = math.dist((before["x"], before["z"]), (after["x"], after["z"]))
        forward = (-math.sin(math.radians(before["yaw"])), -math.cos(math.radians(before["yaw"])))
        along = (after["x"] - before["x"]) * forward[0] + (after["z"] - before["z"]) * forward[1]
        heading_ok = along > travelled * 0.8
        check("the stick moves the character", travelled > 1.5, f"travelled {travelled:.2f} m, speed {mid['speed']:.1f} m/s")
        check("the stick moves it along the camera's heading", heading_ok, f"{along:.2f} m of {travelled:.2f} m along it")
        check("the stick turns nothing", abs(angle_between(before["yaw"], after["yaw"])) < 0.5, f"yaw {before['yaw']:.1f} to {after['yaw']:.1f}")
        check("the stick stops when the thumb lifts", after["speed"] < 0.3, f"speed {after['speed']:.2f} m/s")

        # 3. A tap on the jump button jumps.
        before = probe(page)
        hand.down(3, css("button0_x"), css("button0_y"))
        peak = before["y"]
        end = time.time() + 0.5
        while time.time() < end:
            peak = max(peak, probe(page)["y"])
            time.sleep(0.04)
        hand.up(3)
        time.sleep(1.0)
        after = probe(page)
        check("the jump button jumps", after["jumps"] == before["jumps"] + 1 and peak - before["y"] > 0.3, f"jumps {before['jumps']} to {after['jumps']}, rose {peak - before['y']:.2f} m")

        # 4. Two fingers at once: the stick and a look drag, each only its own job.
        before = probe(page)
        hand.down(4, stick_x, stick_y)
        hand.down(5, 600, 200)
        # Backwards, the way the character came from: it is not at a wall.
        hand.drag({4: (stick_x, stick_y + 40), 5: (600 + 90, 200)}, steps=10)
        time.sleep(0.4)
        page.screenshot(path=str(args.out / "phone_two_fingers.png"))
        both = probe(page)
        hand.up(5)
        time.sleep(0.3)
        mid_state = probe(page)
        time.sleep(0.8)
        after_lift = probe(page)
        hand.up(4)
        time.sleep(0.6)
        turned = angle_between(before["yaw"], both["yaw"])
        want = -90.0 * scale * LOOK_SENSITIVITY_DEG_PER_PX
        check("two fingers: the look finger still turns by the designed angle", abs(turned - want) <= abs(want) * LOOK_TOLERANCE, f"turned {turned:.1f} deg, designed {want:.1f}")
        check("two fingers: the stick finger still moves the character", math.dist((before["x"], before["z"]), (both["x"], both["z"])) > 0.5, f"moved {math.dist((before['x'], before['z']), (both['x'], both['z'])):.2f} m")
        check("two fingers: lifting the look finger keeps the character moving and the view still", math.dist((mid_state["x"], mid_state["z"]), (after_lift["x"], after_lift["z"])) > 0.8 and abs(angle_between(mid_state["yaw"], after_lift["yaw"])) < 1.0, f"moved {math.dist((mid_state['x'], mid_state['z']), (after_lift['x'], after_lift['z'])):.2f} m, turned {angle_between(mid_state['yaw'], after_lift['yaw']):.2f} deg")

        # 5. The crouch, aim and fire buttons: a finger on each does its own job.
        hand.down(6, css("button4_x"), css("button4_y"))
        state = wait_for(page, lambda s: s.get("crouching") is True, 3.0)
        page.screenshot(path=str(args.out / "phone_crouch.png"))
        check("the crouch button crouches", state.get("crouching") is True, f"crouching={state.get('crouching')}")
        hand.up(6)
        state = wait_for(page, lambda s: s.get("crouching") is False, 3.0)
        check("lifting the crouch button stands up", state.get("crouching") is False, f"crouching={state.get('crouching')}")
        hand.down(7, css("button3_x"), css("button3_y"))
        state = wait_for(page, lambda s: s.get("aiming") is True, 3.0)
        check("the aim button aims", state.get("aiming") is True, f"aiming={state.get('aiming')}")
        time.sleep(1.0)
        page.screenshot(path=str(args.out / "phone_aim.png"))
        before = probe(page)
        hand.down(8, css("button2_x"), css("button2_y"))
        state = wait_for(page, lambda s: s.get("shots", 0) > before.get("shots", 0), 3.0)
        page.screenshot(path=str(args.out / "phone_fire.png"))
        check("the fire button shoots", state.get("shots", 0) == before.get("shots", 0) + 1, f"shots {before.get('shots')} to {state.get('shots')}")
        hand.up(8)
        hand.up(7)
        state = wait_for(page, lambda s: s.get("aiming") is False, 4.0)
        check("lifting the aim button lowers the arm", state.get("aiming") is False, f"aiming={state.get('aiming')}")

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
