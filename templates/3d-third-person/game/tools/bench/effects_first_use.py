"""The first flash, its light and the first impact in the web build: no GL program is linked once the level is up.

Serves a web export of `tools/bench/effects_cost.tscn` (export the project with that scene as `run/main_scene` and
`tools/*` taken out of the preset's exclude filter), opens it in headless Chrome on the GPU with a fresh profile, and
counts the programs WebGL links (`linkProgram`, timed at the `LINK_STATUS` read that follows it) in each run the bench
marks. The `warm_up` mark is the level's start, the emitter's warm-up included; every later run (nothing fired, the
flash, its light, the impacts, at 4 and 30 shots a second) must link none: a program linked there stops that frame,
for 65 to 190 ms before kit #946. The last two runs walk into the room with a reflection probe of its own and fire
there: 2 and 3 to 4 programs (frames of 120 to 157 and 64 to 87 ms) before the emitter's probe tour (kit #981). It
prints each run's length (`run_ms`; the `warm_up` row's is the level's start), its programs, their milliseconds,
the slowest of its first frames (`first_frames_max_ms`, the hitch) and its mean frame, and writes them to the second
argument.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/bench/effects_first_use.py build/web build/first_use.json

Exits 1 when a run after the warm-up linked a program or the bench did not finish. Run it under `gds quiet`. A
software renderer links the same programs, so the count holds there too; only the milliseconds need a GPU.
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

BENCH_TIMEOUT_S = 600.0

HOOK = r"""
window.__links = []; window.__marks = [];
window.__mark = (name) => window.__marks.push([name, performance.now()]);
const link = WebGL2RenderingContext.prototype.linkProgram;
const param = WebGL2RenderingContext.prototype.getProgramParameter;
WebGL2RenderingContext.prototype.linkProgram = function (p) { p.__t = performance.now(); return link.call(this, p); };
WebGL2RenderingContext.prototype.getProgramParameter = function (p, n) {
  const r = param.call(this, p, n);
  if (n === this.LINK_STATUS && p.__t) { window.__links.push([p.__t, performance.now() - p.__t]); p.__t = 0; }
  return r;
};
"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:  # noqa: D102
        return


def per_run(marks: list, links: list, results: list) -> list[dict]:
    """The programs linked between each mark and the next, with the bench's numbers for that run."""
    by_name = {r["name"]: r for r in results if "name" in r}
    rows = []
    for index, (name, start) in enumerate(marks):
        end = marks[index + 1][1] if index + 1 < len(marks) else float("inf")
        inside = [x for x in links if start <= x[0] < end]
        bench = by_name.get(name, {})
        rows.append(
            {
                "run": name,
                "run_ms": round(end - start, 1) if end != float("inf") else None,
                "programs": len(inside),
                "link_ms": round(sum(x[1] for x in inside), 1),
                "first_frames_max_ms": bench.get("first_frames_max_ms"),
                "frame_ms_mean": bench.get("frame_ms_mean"),
            }
        )
    return rows


def main() -> int:
    folder, out = Path(sys.argv[1]), Path(sys.argv[2])
    handler = functools.partial(QuietHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    messages: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.add_init_script(HOOK)
        page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
        page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
        page.goto(f"http://127.0.0.1:{server.server_address[1]}/index.html")
        end = time.time() + BENCH_TIMEOUT_S
        while not page.evaluate("window.gdbench_done === true") and time.time() < end:
            page.wait_for_timeout(2000)
        done = page.evaluate("window.gdbench_done === true")
        results = page.evaluate("window.gdbench || []")
        marks = page.evaluate("window.__marks")
        links = page.evaluate("window.__links")
        browser.close()
    server.shutdown()
    rows = per_run(marks, links, results)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"runs": rows, "results": results, "console": messages}, indent=1))
    for row in rows:
        print(
            f"{row['run']:<24} {row['run_ms']} ms  programs {row['programs']:>3} ({row['link_ms']:>7} ms)  "
            f"first frames max {row['first_frames_max_ms']} ms  mean {row['frame_ms_mean']} ms"
        )
    failed = [] if done else ["the bench did not finish"]
    failed += [f"{r['run']} linked {r['programs']} programs" for r in rows if r["run"] != "warm_up" and r["programs"]]
    failed += [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
