"""What the AI's reactions cost in the web build: runs `tools/bench/ai_behaviour_bench.tscn` in headless Chrome.

Serves a web export of the bench (export the project with that scene as `run/main_scene` and `tools/*` taken out of
the preset's exclude filter), waits for `window.__ai_behaviour_bench`, and prints, for 50 and 100 hostile guards around
two targets with their brains off, on with the targets friendly (calm) and on against them (threat), the director's step a tick, the median frame work, ticks a frame, the
calibration loop, the events routed a second and the guards by active task. The optional second argument is a CPU
throttle (4 is the weak-machine stand-in), the third the page's query (`counts=50`).

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/ai_behaviour_bench.py build/web 4

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
            result = page.evaluate("window.__ai_behaviour_bench || null")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        print(f"throttle {throttle:g}x, {result['frames']} frames")
        for row in result["rows"]:
            tasks = ", ".join(f"{kind} {n}" for kind, n in sorted(row["tasks"].items()))
            print(
                f"{row['characters']:>3} guards, {row['mode']:>6}: step {row['step_mean_us']:>7.1f} us"
                f" (p95 {row['step_p95_us']:>7.1f}, {row['us_each']:>5.1f} each), work {row['work_ms']:>6.2f} ms,"
                f" {row['ticks_per_frame']:.2f} ticks/frame, calibration {row['calibration_ms']:.1f} ms,"
                f" {row['routed_per_second']:>5.1f} routed/s, full {row['full']}; {tasks}"
            )
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
