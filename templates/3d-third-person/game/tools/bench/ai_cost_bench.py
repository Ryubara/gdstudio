"""What AI characters cost in the web build: runs `tools/bench/ai_cost_bench.tscn` in headless Chrome.

Serves a web export of the bench (`gds template bench-web 3d-third-person ai_cost_bench` makes it: kit
docs/engines/godot/web-probes.md#bench-web), waits for `window.__ai_cost_bench`, and prints, for 1 to 120 characters
standing and walking, the `AiDirector`'s step a physics tick (mean, 95th percentile, per character), the median frame
work and the count at each tier, each without and with the director's animation throttle (`T`, with the trees moved a
frame) and with the calibration loop's time before it (a busy machine reads slower there too). The optional second
argument is a CPU throttle (4 is the weak-machine stand-in), the third the page's query (`counts=40&throttle=on`,
`lean=off` for the full tick).

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/ai_cost_bench.py build/web 4 counts=40

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
    query = f"?{sys.argv[3]}" if len(sys.argv) > 3 else ""
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
        page.goto(f"http://127.0.0.1:{server.server_address[1]}/index.html{query}")
        end = time.time() + BENCH_TIMEOUT_S
        result = None
        while result is None and time.time() < end:
            page.wait_for_timeout(1000)
            result = page.evaluate("window.__ai_cost_bench || null")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        print(f"throttle {throttle:g}x, {result['frames']} frames")
        for row in result["rows"]:
            mode = "walking" if row["walking"] else "standing"
            animation = "T" if row.get("throttle") else "-"
            lean = {"on": " lean", "off": " full"}.get(row.get("lean", ""), "")
            print(
                f"{row['characters']:>3} {mode:<8} {animation}{lean} step {row['step_mean_us']:>8.1f} us"
                f" (p95 {row['step_p95_us']:>8.1f}), {row['us_each']:>6.1f} us each,"
                f" work {row['work_ms']:>7.3f} ms, tiers {row['full']}/{row['reduced']}/{row['dormant']},"
                f" trees {row.get('advances', 0.0):>5.1f} a frame, calibration {row.get('calibration_ms', 0.0):>6.2f} ms,"
                f" ticks a frame {row.get('ticks_per_frame', 0.0):.2f}"
            )
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
