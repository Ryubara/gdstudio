"""Where an AI character's body step goes in the web build: runs `tools/bench/ai_step_profile.tscn` in headless Chrome.

Serves a web export of the bench (export the project with that scene as `run/main_scene` and `tools/*` taken out of
the preset's exclude filter) cross-origin isolated, so the page's clock reads 5 µs steps instead of 100 µs, waits for
`window.__ai_step_profile`, and prints microseconds a body a tick for the real step and for each module of it. The
optional second argument is a CPU throttle (4 is the weak-machine stand-in), the third the page's query
(`count=40&lean=off`).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/bench/ai_step_profile.py build/web 4

Exits 1 when the bench did not finish or the page logged an error.
"""

from __future__ import annotations

import functools
import http.server
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

BENCH_TIMEOUT_S = 300.0


class IsolatedHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export cross-origin isolated (a finer `performance.now()`), without a log line a request."""

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, *_args: object) -> None:
        return


def main() -> int:
    folder = Path(sys.argv[1])
    throttle = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    query = f"?{sys.argv[3]}" if len(sys.argv) > 3 else ""
    handler = functools.partial(IsolatedHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    messages: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        page = browser.new_page(viewport={"width": 640, "height": 360})
        page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
        page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
        if throttle > 1.0:
            session = page.context.new_cdp_session(page)
            session.send("Emulation.setCPUThrottlingRate", {"rate": throttle})
        page.goto(f"http://127.0.0.1:{server.server_address[1]}/index.html{query}")
        end = time.time() + BENCH_TIMEOUT_S
        result = None
        while result is None and time.time() < end:
            page.wait_for_timeout(1000)
            result = page.evaluate("window.__ai_step_profile || null")
        isolated = page.evaluate("window.crossOriginIsolated")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        print(
            f"throttle {throttle:g}x, {result['count']} walking, isolated {isolated}, lean {result['lean'] or '-'},"
            f" calibration {result['calibration_ms']:.2f} ms"
        )
        print(
            f"real step {result['real_us']:.1f} us a body, modules sum {result['sum_us']:.1f}, loop {result['loop_us']:.2f},"
            f" showing the facing {result.get('present_facing_us', 0.0):.2f} (inside steer)"
        )
        for name, each in result["modules"].items():
            print(f"  {name:<15} {each:>7.2f} us")
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
