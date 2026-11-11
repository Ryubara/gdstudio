"""What a navigation region costs the web build's frame: runs `tools/bench/nav_sync_bench.tscn` in headless Chrome.

Serves a web export of the bench (`gds template bench-web 3d-third-person nav_sync_bench` makes it: kit
docs/engines/godot/web-probes.md#bench-web), waits for `window.__nav_sync_bench`, and prints, for each mesh, the physics
ticks until the map answers on a region added and the after-physics time of the frames that add and remove it. The web
build has no threads, so STEP and THREADED are the same build there. The optional second argument is a CPU throttle (4
is the weak-machine stand-in).

    uv run --project <kit>/python gds quiet --         uv run --with playwright==1.64.1 python tools/bench/nav_sync_bench.py build/web 4

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

BENCH_TIMEOUT_S = 900.0


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:
        return


def main() -> int:
    folder = Path(sys.argv[1])
    throttle = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    handler = functools.partial(QuietHandler, directory=str(folder))
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
        page.goto(f"http://127.0.0.1:{server.server_address[1]}/index.html")
        end = time.time() + BENCH_TIMEOUT_S
        result = None
        while result is None and time.time() < end:
            page.wait_for_timeout(1000)
            result = page.evaluate("window.__nav_sync_bench || null")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        print(
            f"throttle {throttle:g}x, threads {result['threads']}, {result['trials']} trials"
        )
        idle = result["idle_us"]
        print(
            f"idle frame after physics: median {idle['median']:.0f} us, most {idle['most']:.0f} us"
        )
        for row in result["rows"]:
            add = row["add_us"]
            remove = row["remove_us"]
            print(
                f"{row['mesh']:<16} {row['polygons']:>5} polygons {row['mode']:<8}"
                f" ticks {row['ticks']['median']:.0f} (most {row['ticks']['most']:.0f});"
                f" add {add['median']:.0f} / p95 {add['p95']:.0f} / most {add['most']:.0f} us;"
                f" remove {remove['median']:.0f} / most {remove['most']:.0f} us"
            )
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
