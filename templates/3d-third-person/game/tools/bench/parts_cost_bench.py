"""What the template's parts cost a frame in the web build: runs `tools/bench/parts_cost_bench.tscn` in headless Chrome.

Serves a web export of the bench (`gds template bench-web 3d-third-person parts_cost_bench` makes it: kit
docs/engines/godot/web-probes.md#bench-web), waits for `window.__parts_cost_bench`, and prints the crowd's median frame
(1 to 50 characters, idle and walking), each character part's microseconds a frame (the other processing nodes and
the skeleton's modifiers apart) and each world part's. The optional second argument is a CPU throttle (4 is the
weak-machine stand-in).

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/parts_cost_bench.py build/web 4

A browser's clock is coarse (0.1 ms steps without cross-origin isolation): the crowd's frames are medians of 300 and
the parts are sums over 300 frames, so a small part reads to about a microsecond. Run it under `gds quiet`. Exits 1
when the bench did not finish or the page logged an error.
"""

from __future__ import annotations

import functools
import http.server
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

BENCH_TIMEOUT_S = 600.0


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
            result = page.evaluate("window.__parts_cost_bench || null")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        print(f"throttle {throttle:g}x, {result['frames']} frames")
        for row in result["crowd"]:
            print(
                f"{row['characters']:>3} characters  work idle {row['idle_work_ms']:>7.3f} ms"
                f"  walking {row['walking_work_ms']:>7.3f} ms"
                f"  {row['nodes_each']:.0f} nodes, {row['bodies_each']:.0f} bodies, spawn {row['spawn_ms_each']:.2f} ms each"
            )
        parts = result["parts"]
        names = [key for key in parts if key.endswith("_us")]
        print(
            f"{parts['characters']} walking, us a character a frame: "
            + ", ".join(f"{k[:-3]} {parts[k]:.1f}" for k in names)
        )
        for group in ("others", "modifiers"):
            print(
                f"  {group}: "
                + ", ".join(f"{k} {v:.1f}" for k, v in parts.get(group, {}).items())
            )
        for key in ("death", "death_male"):
            death = result[key]
            print(
                f"{key}: first {death['first_ms']:.2f} ms, later {death['later_ms']:.2f} ms"
            )
        for row in result["world"]:
            print(
                f"{row['count']} {row['kind']:<7} {row['work_us_each']:>6.2f} us each (work),"
                f" {row['processing_each']:.0f} processing each"
            )
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
