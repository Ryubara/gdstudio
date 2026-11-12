"""The AI's web cost: runs the AI soak (`tools/soak/ai_soak.tscn`) in headless Chrome and prints its frame costs.

Serves a web export of the soak (`gds template bench-web 3d-third-person tools/soak/ai_soak.tscn` builds it with the
soak as `run/main_scene` and `tools/*` in the pack), loads it once for each population and CPU throttle asked
(`?scale=N&pathing=0&seconds=S`: the AI section's 10 characters times N, the player walked round fighting, nothing in
the pathing section, so `scale=4` is the web cap of 40), and prints a Markdown table: the frame's work at the median
and the 95th percentile over the measured seconds (after the soak's 5 s warm-up), the AI director's step a tick (mean
and 95th percentile), ticks a frame (past 1 the frame falls behind the 60 Hz tick: `crowds.md#ai-characters`) and the
calibration loop. A throttle of 4 is the weak-laptop stand-in (`Emulation.setCPUThrottlingRate`).

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/web_smoke/ai.py build/web --scales 1,4 --throttles 1,4

Exits 1 when a run did not finish or the page logged an error (the build must load clean).
Docs: the kit's `docs/engines/godot/crowds.md#ai-characters`.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

#: Seconds of wall time a run may take beyond its simulated seconds (a throttled page runs slower than the clock).
SLACK_S = 600.0
#: Characters the AI section holds at scale 1.
SECTION_COUNT = 10


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:
        return


def run_once(browser, url: str, throttle: float, seconds: float) -> tuple[dict | None, list[str]]:
    """One page load of the soak: its `window.__ai_soak` result and the page's error lines."""
    messages: list[str] = []
    page = browser.new_page(viewport={"width": 640, "height": 360})
    page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
    page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
    if throttle > 1.0:
        session = page.context.new_cdp_session(page)
        session.send("Emulation.setCPUThrottlingRate", {"rate": throttle})
    page.goto(url)
    end = time.time() + seconds * max(throttle, 1.0) + SLACK_S
    result = None
    while result is None and time.time() < end:
        page.wait_for_timeout(1000)
        result = page.evaluate("window.__ai_soak || null")
    page.close()
    errors = [m for m in messages if m.startswith(("error", "pageerror"))]
    return result, errors


def row(scale: int, throttle: float, result: dict) -> str:
    """One line of the table."""
    return (
        f"| {scale * SECTION_COUNT} | {throttle:g}x | {result['frame_work_ms_p50']} / {result['frame_work_ms_p95']} "
        f"| {result['director_step_us_mean'] / 1000:.2f} / {result['director_step_us_p95'] / 1000:.2f} "
        f"| {result['ticks_per_frame']} | {result['calibration_ms']} | {', '.join(result['gates']) or 'none'} |"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export's folder (index.html)")
    parser.add_argument("--scales", default="1,2,3", help="population scales, comma-separated (3 is 30 characters)")
    parser.add_argument("--throttles", default="1,4", help="CPU throttles, comma-separated")
    parser.add_argument("--seconds", type=float, default=15.0, help="simulated seconds a run (5 of them warm-up)")
    parser.add_argument("--json", type=Path, help="also write every result to this file")
    args = parser.parse_args()
    handler = functools.partial(QuietHandler, directory=str(args.build))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    failed: list[str] = []
    results: list[dict] = []
    lines = [
        "| Characters | CPU | Frame work ms (median / p95) | AI step ms a tick (mean / p95) | Ticks a frame "
        "| Calibration ms | Gates broken |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        for throttle in [float(t) for t in args.throttles.split(",")]:
            for scale in [int(s) for s in args.scales.split(",")]:
                url = f"http://127.0.0.1:{port}/index.html?scale={scale}&pathing=0&seconds={args.seconds:g}"
                result, errors = run_once(browser, url, throttle, args.seconds)
                failed += [f"scale {scale} at {throttle:g}x: {e}" for e in errors[:5]]
                if result is None:
                    failed.append(f"scale {scale} at {throttle:g}x: the soak did not finish")
                    continue
                result["throttle"] = throttle
                results.append(result)
                lines.append(row(scale, throttle, result))
                print(lines[-1], flush=True)
        browser.close()
    server.shutdown()
    print("\n".join(lines))
    if args.json:
        args.json.write_text(json.dumps(results, indent=1), encoding="utf-8")
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
