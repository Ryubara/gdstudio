"""What the gait fitting costs a character a frame in the web build: runs `tools/bench/gait_cost.tscn` in headless Chrome.

Serves a web export of the bench (`gds template bench-web 3d-third-person gait_cost` makes it: kit
docs/engines/godot/web-probes.md#bench-web) cross-origin isolated (so the page's clock steps 5 us, not 100), loads it
once a run and a count of players (`?run=off&players=40`; one page a run, as the bench measures one set of players a
process), in turns off, on, off, on, waits for `window.__gait_cost` and prints each run's mean and median frame work
and the fitting's cost a character a frame: `on`'s mean less `off`'s, over the players. The optional second argument is
a CPU throttle (4 is the weak-machine stand-in), the third a comma-separated list of player counts (default 1,40).

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/gait_cost.py build/web 1

Run it under `gds quiet`. Exits 1 when a run did not finish or the page logged an error.
"""

from __future__ import annotations

import functools
import http.server
import json
import statistics
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

RUN_TIMEOUT_S = 300.0
TURNS = ["off", "on", "off", "on"]


class IsolatedHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export cross-origin isolated, without a log line a request."""

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, *_args: object) -> None:
        return


def main() -> int:
    folder = Path(sys.argv[1])
    throttle = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    counts = [int(c) for c in sys.argv[3].split(",")] if len(sys.argv) > 3 and sys.argv[3] else [1, 40]
    handler = functools.partial(IsolatedHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    messages: list[str] = []
    results: dict[str, list[dict]] = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        for count in counts:
            for run in TURNS:
                page = browser.new_page(viewport={"width": 640, "height": 360})
                page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
                page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
                if throttle > 1.0:
                    session = page.context.new_cdp_session(page)
                    session.send("Emulation.setCPUThrottlingRate", {"rate": throttle})
                port = server.server_address[1]
                page.goto(f"http://127.0.0.1:{port}/index.html?run={run}&players={count}")
                end = time.time() + RUN_TIMEOUT_S
                result = None
                while result is None and time.time() < end:
                    page.wait_for_timeout(1000)
                    result = page.evaluate("window.__gait_cost || null")
                if result is None:
                    messages.append(f"error: the run {run} with {count} did not finish")
                else:
                    results.setdefault(f"{run} {count}", []).append(result)
                page.close()
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    print(f"throttle {throttle:g}x")
    for count in counts:
        means = {run: [r["mean_ms"] for r in results.get(f"{run} {count}", [])] for run in ("off", "on")}
        if not means["off"] or not means["on"]:
            continue
        off = statistics.mean(means["off"])
        on = statistics.mean(means["on"])
        each = (on - off) * 1000.0 / count
        print(f"{count:>3} players: off {off:7.3f} ms, on {on:7.3f} ms a frame; the fitting {each:6.1f} us a character")
    print("JSON " + json.dumps({"throttle": throttle, "runs": results}))
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
