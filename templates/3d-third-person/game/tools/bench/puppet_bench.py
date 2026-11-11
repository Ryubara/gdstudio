"""What an online puppet costs a frame in the web build: runs `tools/bench/puppet_bench.tscn` in headless Chrome.

Serves a web export of the bench (export the project with that scene as `run/main_scene` and `tools/*` taken out of
the preset's exclude filter), waits for `window.__puppet_bench`, and prints the mean frame and its 95th percentile of
every variant (seven puppets near, far or out of view; none, animated every frame, frozen, hidden, every second frame,
or under the online game's animation throttle), with what a puppet costs against `near/none`. Software drawing
(SwiftShader) by default; `--gpu` draws with the machine's GPU, and `--uncapped` turns vsync and the frame cap off so
the frame is the page's own work.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/bench/puppet_bench.py build/bench [--gpu [--uncapped]] [--out x.json]

Run it under `gds quiet`. Exits 1 when the bench did not finish or the page logged an error.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "web_smoke"))
from net_play_smoke import GPU_ARGS, SOFTWARE_ARGS, serve

BENCH_TIMEOUT_S = 600.0
UNCAPPED_ARGS = ["--disable-gpu-vsync", "--disable-frame-rate-limit"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export of the bench (index.html)")
    parser.add_argument("--gpu", action="store_true", help="draw with the machine's GPU instead of SwiftShader")
    parser.add_argument("--uncapped", action="store_true", help="with --gpu: vsync and the frame cap off")
    parser.add_argument("--viewport", default="320x180", help="the page's size, WxH")
    parser.add_argument("--out", type=Path, help="write the bench's JSON here too")
    args = parser.parse_args()
    server, port = serve(args.build)
    messages: list[str] = []
    with sync_playwright() as playwright:
        launch_args = GPU_ARGS + (UNCAPPED_ARGS if args.uncapped else []) if args.gpu else SOFTWARE_ARGS
        browser = playwright.chromium.launch(args=launch_args)
        width, height = (int(n) for n in args.viewport.split("x"))
        page = browser.new_page(viewport={"width": width, "height": height})
        page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
        page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
        page.goto(f"http://127.0.0.1:{port}/index.html")
        end = time.time() + BENCH_TIMEOUT_S
        result = None
        while result is None and time.time() < end:
            page.wait_for_timeout(1000)
            result = page.evaluate("window.__puppet_bench || null")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        if args.out:
            args.out.write_text(json.dumps(result, indent=2), encoding="utf-8")
        rows = {row["variant"]: row for row in result["results"]}
        empty = rows["near/none"]["frame_ms"]
        mode = ("GPU, uncapped" if args.uncapped else "GPU") if args.gpu else "SwiftShader"
        print(f"{mode}, {result['puppets']} puppets, {args.viewport}")
        for name, row in rows.items():
            each = (row["frame_ms"] - empty) / result["puppets"]
            print(f"{name:<15} frame {row['frame_ms']:7.3f} ms  p95 {row['p95_ms']:7.3f} ms  a puppet {each:6.3f} ms")
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
