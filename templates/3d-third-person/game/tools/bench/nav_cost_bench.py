"""What AI characters cost in the web build: runs `tools/bench/ai_cost_bench.tscn` in headless Chrome.

Serves a web export of the bench (export the project with that scene as `run/main_scene` and `tools/*` taken out of
the preset's exclude filter), waits for `window.__nav_cost_bench`, and prints, for 1 to 120 characters standing and
walking, the `AiDirector`'s step a physics tick (mean, 95th percentile, per character), the median frame work and the
count at each tier. The optional second argument is a CPU throttle (4 is the weak-machine stand-in).

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/ai_cost_bench.py build/web 4

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
            result = page.evaluate("window.__nav_cost_bench || null")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        print(f"throttle {throttle:g}x, {result['frames']} frames")
        for row in result["rows"]:
            print(
                f"{row['characters']:>3} nav {row['nav_mean_us']:>7.1f} us a tick, {row['nav_us_each']:>5.2f} us each;"
                f" director step {row['step_mean_us']:>8.1f} us; queries a tick {row['queries_mean_a_tick']:.2f}"
                f" (most {row['queries_most_a_tick']} of {row['paths_per_tick']}); each"
                f" {row['queries_each_a_second']:.2f}/s (limit {row['repath_limit_a_second']:g});"
                f" tiers {row['full']}/{row['reduced']}/{row['dormant']}"
            )
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
