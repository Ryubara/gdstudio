"""What the weapon holds cost a character a frame in the web build: runs `tools/bench/hold_cost.tscn` in headless Chrome.

Serves a web export of the bench (`gds template bench-web 3d-third-person hold_cost` makes it: kit
docs/engines/godot/web-probes.md#bench-web) cross-origin isolated (so the page's clock steps 5 us, not 100), loads it
once a run (`?run=no_hold`, `aimed`, `rifle`, ...; one page a run, as the bench measures one set of figures a process),
waits for `window.__hold_cost` and prints each run's mean and median frame work and, for each hold, its cost a
character a frame: the run's mean less that of the `no_hold` run with the same camera, over the figures. The optional second argument is a CPU throttle
(4 is the weak-machine stand-in), the third a comma-separated list of runs.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/hold_cost.py build/web 1

Run it under `gds quiet`. Exits 1 when a run did not finish or the page logged an error.
"""

from __future__ import annotations

import functools
import http.server
import json
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

RUN_TIMEOUT_S = 300.0
RUNS = ["no_hold", "carried", "aimed", "rifle", "rifle_low", "rifle_reload", "no_hold_far", "rifle_far"]


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
    runs = sys.argv[3].split(",") if len(sys.argv) > 3 else RUNS
    handler = functools.partial(IsolatedHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    messages: list[str] = []
    results: dict[str, dict] = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        for run in runs:
            page = browser.new_page(viewport={"width": 640, "height": 360})
            page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
            page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
            if throttle > 1.0:
                session = page.context.new_cdp_session(page)
                session.send("Emulation.setCPUThrottlingRate", {"rate": throttle})
            page.goto(f"http://127.0.0.1:{server.server_address[1]}/index.html?run={run}")
            end = time.time() + RUN_TIMEOUT_S
            result = None
            while result is None and time.time() < end:
                page.wait_for_timeout(1000)
                result = page.evaluate("window.__hold_cost || null")
            if result is None:
                messages.append(f"error: the run {run} did not finish")
            else:
                result["isolated"] = page.evaluate("self.crossOriginIsolated")
                results[run] = result
            page.close()
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    bases = {r["camera"]: r for r in results.values() if r["run"].startswith("no_hold")}
    print(f"throttle {throttle:g}x")
    for run, result in results.items():
        base = bases.get(result["camera"])
        line = (
            f"{run:<13} work mean {result['mean_ms']:7.3f} ms, median {result['median_ms']:7.3f} ms"
            f" ({result['frames']} frames, isolated {result['isolated']})"
        )
        if base is not None and not run.startswith("no_hold"):
            each = (result["mean_ms"] - base["mean_ms"]) * 1000.0 / result["characters"]
            line += f"  hold {each:6.1f} us a character a frame"
        print(line)
    print("JSON " + json.dumps({"throttle": throttle, "runs": results}))
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
