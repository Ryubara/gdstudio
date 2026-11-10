"""The network link in the web build: the page connects to a local server, survives a frozen tab, and
never downgrades `wss://`.

Starts `tools/net/echo_server.gd` in a headless Godot (a free port), serves the exported game
(`build/web`), and opens it in headless Chromium with `?netprobe&url=ws://...`; the game's `NetProbe`
writes what its `WebSocketLink` sees to `window.gdnet`. Checks:

- the link reads the server's address from the page and opens; pings come back (round trip over
  loopback, and through `tools/net/relay.py` with 100 ms each way, which must read 200 ms or more);
- the server streams 35 KB a second while the page's main thread is frozen for 5 s (a busy loop,
  the freeze a player gets): every packet arrives, in order, with no `Buffer payload full` error;
- the same page served over `https` (a routed origin) refuses `ws://` with a reason and opens no
  socket; it would only open `wss://`;
- the control: the same freeze with the engine's default 64 KB inbound buffer (`&inbound=65536`)
  loses packets, which is why the link's buffer is 1 MB.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/net_link_smoke.py build/web build/net_smoke \\
        --godot <pinned godot> --project game

Numbers and `result.json` go to the second argument. Exits 1 on any check that fails. Run it under
`gds quiet`.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import mimetypes
import statistics
import subprocess
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "net"))
from relay import Relay

READY_TIMEOUT_S = 120.0
STREAM_BYTES = 584  # 35 KB a second at 60 ticks.
FREEZE_S = 5.0
RELAY_DELAY_S = 0.1


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:
        return


def serve(folder: Path) -> tuple[http.server.ThreadingHTTPServer, int]:
    handler = functools.partial(QuietHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def start_server(godot: str, project: Path) -> tuple[subprocess.Popen[str], int]:
    """The echo server in a headless Godot, and the port it listens on."""
    process = subprocess.Popen(
        [
            godot,
            "--headless",
            "--path",
            str(project),
            "-s",
            "res://tools/net/echo_server.gd",
            "--",
            "--port",
            "0",
            "--stream",
            str(STREAM_BYTES),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    began = time.monotonic()
    assert process.stdout is not None
    while time.monotonic() - began < 60:
        line = process.stdout.readline()
        if line.startswith("LISTENING"):
            threading.Thread(target=lambda: [None for _ in process.stdout], daemon=True).start()
            return process, int(line.split()[1])
        if not line and process.poll() is not None:
            break
    stop_server(process)
    raise SystemExit("the echo server did not start")


def stop_server(process: subprocess.Popen[str]) -> None:
    """Stops the server and the program the Windows console wrapper started."""
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(process.pid)], capture_output=True, check=False)
    else:
        process.kill()
    process.wait(10)


def wait_for(page: Page, expression: str, timeout_s: float) -> bool:
    began = time.monotonic()
    while time.monotonic() - began < timeout_s:
        if page.evaluate(f"() => {{ try {{ return !!({expression}); }} catch (e) {{ return false; }} }}"):
            return True
        time.sleep(0.2)
    return False


def gdnet(page: Page) -> dict:
    return page.evaluate(
        "() => { const g = window.gdnet || {}; return {state: g.state, refusal: g.refusal, url: g.url,"
        " streamed: g.streamed, in_order: g.in_order, gaps: g.gaps_over_100ms, pings: g.pings,"
        " rtt: g.rtt_ms, bytes_in: g.bytes_in, fps: g.fps}; }"
    )


def round_trips(page: Page, count: int, timeout_s: float = 30.0) -> list[float]:
    wait_for(page, f"window.gdnet && window.gdnet.pings >= {count}", timeout_s)
    return json.loads(gdnet(page).get("rtt") or "[]")


def frozen_tab(page: Page, errors: list[str]) -> dict:
    """Asks for the stream, freezes the page's thread for `FREEZE_S` and reads what came."""
    page.evaluate("() => { window.gdnet.want_stream = true; }")
    wait_for(page, "window.gdnet.streamed > 60", 30)
    before = gdnet(page)["streamed"]
    page.evaluate(
        f"() => {{ const end = performance.now() + {FREEZE_S * 1000}; while (performance.now() < end) {{}} }}"
    )
    at_end = gdnet(page)["streamed"]
    time.sleep(3.0)
    after = gdnet(page)
    # One stream packet per server tick: the 5 s and the 3 s after must all be there.
    expected = before + int((FREEZE_S + 3.0) * 60 * 0.9)
    payload_errors = [e for e in errors if "Buffer payload full" in e]
    return {
        "streamed_before": before,
        "streamed_at_end_of_freeze": at_end,
        "streamed_3s_later": after["streamed"],
        "expected_at_least": expected,
        "in_order": after["in_order"],
        "gaps_over_100ms": after["gaps"],
        "payload_full_errors": len(payload_errors),
        "whole": bool(after["in_order"]) and after["streamed"] >= expected and not payload_errors,
    }


def summary(samples: list[float]) -> dict:
    if not samples:
        return {"n": 0}
    ordered = sorted(samples)
    return {
        "n": len(ordered),
        "median": round(statistics.median(ordered), 1),
        "p95": round(ordered[min(int(len(ordered) * 0.95), len(ordered) - 1)], 1),
        "max": round(ordered[-1], 1),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export folder (index.html)")
    parser.add_argument("out", type=Path, help="folder for result.json")
    parser.add_argument("--godot", required=True, help="the pinned Godot (console build on Windows)")
    parser.add_argument("--project", type=Path, required=True, help="the game folder (project.godot)")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    result: dict = {"checks": {}}
    failures: list[str] = []

    def check(name: str, ok: bool, detail: object) -> None:
        result["checks"][name] = {"ok": ok, "detail": detail}
        print(("PASS " if ok else "FAIL ") + name + f": {detail}", flush=True)
        if not ok:
            failures.append(name)

    http_server, http_port = serve(args.build)
    process, ws_port = start_server(args.godot, args.project)
    relay = Relay("127.0.0.1", ws_port, RELAY_DELAY_S)
    relay_port = relay.start_in_thread()
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
            )
            errors: list[str] = []

            # 1. Over loopback: the address from the page, the link opens, pings come back.
            page = browser.new_page()
            page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
            page.goto(f"http://127.0.0.1:{http_port}/index.html?netprobe&url=ws://127.0.0.1:{ws_port}")
            opened = wait_for(page, "window.gdnet && window.gdnet.state === 'open'", READY_TIMEOUT_S)
            check("opens from the page address", opened, gdnet(page))
            loopback = summary(round_trips(page, 10))
            # The page polls on its physics tick: a slow software-rendered page rounds every trip up.
            loopback["page_fps"] = gdnet(page).get("fps")
            result["rtt_loopback_ms"] = loopback
            check("pings come back over loopback", loopback.get("n", 0) >= 10, loopback)

            # 2. A frozen tab: the server streams 35 KB/s while the page's thread is busy for 5 s.
            freeze = frozen_tab(page, errors)
            result["freeze"] = freeze
            check("a 5 s frozen tab loses nothing of 35 KB/s", freeze["whole"], freeze)
            page.close()

            # 2b. The control: the engine's default inbound buffer, the same freeze.
            page = browser.new_page()
            control_errors: list[str] = []
            page.on(
                "console",
                lambda message: control_errors.append(message.text) if message.type == "error" else None,
            )
            page.goto(f"http://127.0.0.1:{http_port}/index.html?netprobe&inbound=65536&url=ws://127.0.0.1:{ws_port}")
            wait_for(page, "window.gdnet && window.gdnet.state === 'open'", READY_TIMEOUT_S)
            control = frozen_tab(page, control_errors)
            result["freeze_with_64_kb"] = control
            check("the control with 64 KB loses packets", not control["whole"], control)
            page.close()

            # 3. Through the relay, 100 ms each way: the round trip is 200 ms or more.
            page = browser.new_page()
            page.goto(f"http://127.0.0.1:{http_port}/index.html?netprobe&url=ws://127.0.0.1:{relay_port}")
            wait_for(page, "window.gdnet && window.gdnet.state === 'open'", READY_TIMEOUT_S)
            relayed = summary(round_trips(page, 10))
            relayed["page_fps"] = gdnet(page).get("fps")
            result["rtt_relay_ms"] = relayed
            result["relay_bytes"] = relay.counts()
            check(
                "a relay of 100 ms each way reads 200 ms or more",
                relayed.get("n", 0) >= 10 and relayed["median"] >= 200.0,
                relayed,
            )
            page.close()

            # 4. An https page never opens ws://.
            page = browser.new_page()
            sockets: list[str] = []
            page.on("websocket", lambda ws: sockets.append(ws.url))
            build = args.build.resolve()

            def from_build(route) -> None:
                name = route.request.url.split("?")[0].split("game.test/", 1)[1] or "index.html"
                path = build / name
                if not path.is_file():
                    route.fulfill(status=404)
                    return
                kind = mimetypes.guess_type(name)[0] or "application/octet-stream"
                if name.endswith(".wasm"):
                    kind = "application/wasm"
                route.fulfill(status=200, body=path.read_bytes(), headers={"Content-Type": kind})

            page.route("https://game.test/**", from_build)
            page.goto(f"https://game.test/index.html?netprobe&url=ws://127.0.0.1:{ws_port}")
            refused = wait_for(page, "window.gdnet && window.gdnet.state === 'refused'", READY_TIMEOUT_S)
            seen = gdnet(page)
            check(
                "an https page refuses ws:// and opens no socket",
                refused and "wss://" in str(seen.get("refusal")) and not sockets,
                {"gdnet": seen, "sockets": sockets},
            )
            page.close()
            result["console_errors"] = [e for e in errors if "Buffer payload full" not in e][:20]
            browser.close()
    finally:
        relay.stop()
        stop_server(process)
        http_server.shutdown()

    result["failures"] = failures
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("FAILED: " + ", ".join(failures) if failures else "ALL PASSED", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
