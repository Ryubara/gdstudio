"""What the AI section's population costs in the web build: runs `tools/bench/ai_section_bench.tscn` in headless Chrome.

Serves a web export of the bench (`gds template bench-web 3d-third-person ai_section_bench --run` builds it with that
scene as `run/main_scene` and `tools/*` out of the exclude filter), waits for `window.__ai_section_bench`, and prints,
for the section's whole population around the player standing in the doorway (watch) and walked round fighting
(fight), the director's step a tick, the living characters and the step for each, the median frame work, ticks a
frame and the calibration loop. The optional second argument is a CPU throttle (4 is the weak-machine stand-in).

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/ai_section_bench.py build/web 4

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
            result = page.evaluate("window.__ai_section_bench || null")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        print(f"throttle {throttle:g}x, {result['ticks']} ticks a row")
        for row in result["rows"]:
            print(
                f"{row['mode']:>5}: step {row['step_mean_us']:>7.1f} us (p95 {row['step_p95_us']:>7.1f},"
                f" {row['alive']:.1f} alive, {row['us_each']:>6.1f} each), work {row['work_ms']:>6.2f} ms,"
                f" {row['ticks_per_frame']:.2f} ticks/frame, calibration {row['calibration_ms']:.1f} ms,"
                f" spawned in {row['spawn_ticks']} ticks"
            )
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
