"""What drawing the prototype mannequins costs a browser frame: runs `tools/bench/mannequin_draw_bench.tscn` in Chrome.

Serves a web export of the bench (`gds template bench-web 3d-third-person mannequin_draw_bench` makes it: kit
docs/engines/godot/web-probes.md#bench-web), records every `requestAnimationFrame` delta and every program WebGL links
under the cell the bench names in `window.__cell`, waits for `window.__mannequin_draw_bench` and prints, for each
model (the Quaternius male and the `form`, `joint` and `facet` males), 1, 8 and 16 bodies at each level of detail:
the page's median and 95th percentile frame, the engine's mean frame (the median round and the best round: a busy
machine slows whole rounds), the draw calls and primitives a frame and what a body adds against the same level with no
body, from both rounds; then each model's first appearance (its worst frame and the programs
linked then). Software drawing (SwiftShader) by default; `--gpu` draws with the machine's GPU; `--uncapped` turns
vsync and the frame cap off so the frame is the page's own work (without it the page's frames are whole vsyncs). `--query` is the page's query (`rounds=2&frames=90`).

    uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 \
        python tools/bench/mannequin_draw_bench.py build/web [--gpu] [--uncapped] [--query q] [--out x.json]

Run it under `gds quiet`. Exits 1 when the bench did not finish or the page logged an error.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "web_smoke"))
from net_play_smoke import GPU_ARGS, SOFTWARE_ARGS, serve

BENCH_TIMEOUT_S = 3600.0
UNCAPPED_ARGS = ["--disable-gpu-vsync", "--disable-frame-rate-limit"]
# Records each rAF delta and each program linked (with its link time) under `window.__cell`.
RECORDER = """
window.__cell = '';
window.__frames = {};
window.__links = {};
(() => {
  let last = 0;
  const tick = (t) => {
    if (last && window.__cell) (window.__frames[window.__cell] ||= []).push(t - last);
    last = t;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  const proto = WebGL2RenderingContext.prototype;
  const link = proto.linkProgram;
  const param = proto.getProgramParameter;
  proto.linkProgram = function (p) { p.__t = performance.now(); return link.call(this, p); };
  proto.getProgramParameter = function (p, n) {
    const r = param.call(this, p, n);
    if (n === this.LINK_STATUS && p.__t) {
      (window.__links[window.__cell || '-'] ||= []).push(performance.now() - p.__t);
      p.__t = 0;
    }
    return r;
  };
})();
"""
RENDERER = """(() => {
  const gl = document.createElement('canvas').getContext('webgl2');
  const info = gl && gl.getExtension('WEBGL_debug_renderer_info');
  return info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : 'unknown';
})()"""


def percentile(values: list[float], share: float) -> float:
    ordered = sorted(values)
    return ordered[min(int(len(ordered) * share), len(ordered) - 1)] if ordered else 0.0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export of the bench (index.html)")
    parser.add_argument("--gpu", action="store_true", help="draw with the machine's GPU instead of SwiftShader")
    parser.add_argument("--uncapped", action="store_true", help="vsync and the frame cap off")
    parser.add_argument("--viewport", default="640x360", help="the page's size, WxH")
    parser.add_argument("--query", default="", help="the page's query: rounds, frames, warm, order")
    parser.add_argument("--out", type=Path, help="write the bench's JSON and the page's frames here")
    args = parser.parse_args()
    server, port = serve(args.build)
    messages: list[str] = []
    with sync_playwright() as playwright:
        launch_args = (GPU_ARGS if args.gpu else SOFTWARE_ARGS) + (UNCAPPED_ARGS if args.uncapped else [])
        browser = playwright.chromium.launch(args=launch_args)
        width, height = (int(n) for n in args.viewport.split("x"))
        page = browser.new_page(viewport={"width": width, "height": height})
        page.add_init_script(RECORDER)
        page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
        page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
        query = f"?{args.query}" if args.query else ""
        page.goto(f"http://127.0.0.1:{port}/index.html{query}")
        renderer = page.evaluate(RENDERER)
        end = time.time() + BENCH_TIMEOUT_S
        result = None
        while result is None and time.time() < end:
            page.wait_for_timeout(2000)
            result = page.evaluate("window.__mannequin_draw_bench || null")
        frames = page.evaluate("window.__frames")
        links = page.evaluate("window.__links")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        report(args, result, frames, links, renderer)
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


def report(args: argparse.Namespace, result: dict, frames: dict, links: dict, renderer: str) -> None:
    """Prints the cells and the first appearances, and writes them to `--out`."""
    mode = ("GPU" if args.gpu else "SwiftShader") + (", uncapped" if args.uncapped else "")
    print(f"{mode} ({renderer}), {args.viewport}, {result['rounds']} rounds of {result['frames']} frames")
    rows = []
    empty: dict[int, tuple[float, float]] = {}
    for row in result["results"]:
        deltas = frames.get(row["cell"], [])
        row["page_median_ms"] = round(statistics.median(deltas), 3) if deltas else 0.0
        row["page_p95_ms"] = round(percentile(deltas, 0.95), 3)
        row["best_ms"] = min(row["frame_ms_runs"])
        row["programs_linked"] = len(links.get(row["cell"], []))
        if row["model"] == "none":
            empty[row["level"]] = (row["frame_ms"], row["best_ms"])
        rows.append(row)
    print(
        "cell                       page p50  page p95  engine    best   draws    prims"
        "  a body  (best)  linked"
    )
    for row in rows:
        base, base_best = empty.get(row["level"], (0.0, 0.0))
        count = max(row["count"], 1)
        row["body_ms"] = round((row["frame_ms"] - base) / count, 4)
        row["body_best_ms"] = round((row["best_ms"] - base_best) / count, 4)
        print(
            f"{row['cell']:<26} {row['page_median_ms']:8.3f} {row['page_p95_ms']:9.3f} {row['frame_ms']:7.3f}"
            f" {row['best_ms']:7.3f} {row['draw_calls']:7.1f} {row['primitives']:8d} {row['body_ms']:7.3f}"
            f" {row['body_best_ms']:7.3f} {row['programs_linked']:7d}"
        )
    print("first appearance          worst ms   page worst  linked  link ms")
    for item in result["first_use"]:
        key = f"first/{item['model']}"
        deltas = frames.get(key, [])
        linked = links.get(key, [])
        item["page_worst_ms"] = round(max(deltas), 3) if deltas else 0.0
        item["programs_linked"] = len(linked)
        item["link_ms"] = round(sum(linked), 3)
        print(
            f"{item['model']:<24} {item['worst_ms']:8.3f} {item['page_worst_ms']:12.3f}"
            f" {item['programs_linked']:7d} {item['link_ms']:8.3f}"
        )
    if args.out:
        result["renderer"] = renderer
        result["mode"] = mode
        args.out.write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
