"""What starting a shot or an impact sound costs in the web build: runs `tools/bench/sound_start_bench.tscn` in Chrome.

Serves a web export of the bench (export the project with that scene as `run/main_scene` and `tools/*` taken out of
the preset's exclude filter), opens it in headless Chrome with sound allowed to start without a click, waits for
`window.__sound_start_bench` and prints each case's microseconds a start. It also counts the sounds the page handed
the browser as samples (`createBufferSource`: a lone WAV or Ogg plays as a sample, a randomizer as a stream that
Godot mixes itself) and the loudest sample that reached the output
(an `AnalyserNode` between the page and the speakers), so a cheap start that plays nothing shows as silence.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/bench/sound_start_bench.py build/web

A browser's clock is coarse (0.1 ms steps without cross-origin isolation); the bench times 50 starts at once, so a
start of a few microseconds still reads. Run it under `gds quiet`. Exits 1 when the bench did not finish, the page
logged an error or nothing was heard.
"""

from __future__ import annotations

import functools
import http.server
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

BENCH_TIMEOUT_S = 300.0

# Counts the samples started and taps the output: every connection to the speakers goes through one analyser.
TAP = """
(() => {
  window.__sound = { starts: 0, peak: 0, cases: {}, now: "load" };
  window.__mark = (name) => {
    window.__sound.now = name;
    window.__sound.cases[name] = window.__sound.cases[name] || { starts: 0, peak: 0 };
  };
  window.__mark("load");
  const make = BaseAudioContext.prototype.createBufferSource;
  BaseAudioContext.prototype.createBufferSource = function (...args) {
    window.__sound.starts += 1;
    window.__sound.cases[window.__sound.now].starts += 1;
    return make.apply(this, args);
  };
  const connect = AudioNode.prototype.connect;
  const taps = new WeakMap();
  AudioNode.prototype.connect = function (target, ...rest) {
    if (target instanceof AudioDestinationNode) {
      let tap = taps.get(target.context);
      if (!tap) {
        tap = target.context.createAnalyser();
        tap.fftSize = 2048;
        connect.call(tap, target);
        taps.set(target.context, tap);
        const data = new Float32Array(tap.fftSize);
        setInterval(() => {
          tap.getFloatTimeDomainData(data);
          const now = window.__sound.cases[window.__sound.now];
          for (const v of data) {
            window.__sound.peak = Math.max(window.__sound.peak, Math.abs(v));
            now.peak = Math.max(now.peak, Math.abs(v));
          }
        }, 20);
      }
      return connect.call(this, tap, ...rest);
    }
    return connect.call(this, target, ...rest);
  };
})();
"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:
        return


def main() -> int:
    folder = Path(sys.argv[1])
    handler = functools.partial(QuietHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    messages: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome", headless=True, args=["--autoplay-policy=no-user-gesture-required"]
        )
        page = browser.new_page(viewport={"width": 640, "height": 360})
        page.add_init_script(TAP)
        page.on("console", lambda m: messages.append(f"{m.type}: {m.text}"))
        page.on("pageerror", lambda e: messages.append(f"pageerror: {e}"))
        page.goto(f"http://127.0.0.1:{server.server_address[1]}/index.html")
        end = time.time() + BENCH_TIMEOUT_S
        result = None
        while result is None and time.time() < end:
            page.wait_for_timeout(1000)
            result = page.evaluate("window.__sound_start_bench || null")
        sound = page.evaluate("window.__sound")
        browser.close()
    server.shutdown()
    failed = [m for m in messages if m.startswith(("error", "pageerror"))][:5]
    if result is None:
        failed.append("the bench did not finish")
    else:
        for row in result:
            if "ms" in row:
                print(f"{row['case']:<26} {row['ms']:8.2f} ms for {row['takes']} takes")
                continue
            heard = sound["cases"].get(row["case"], {"starts": 0, "peak": 0.0})
            print(
                f"{row['case']:<26} {row['us_per_start_median']:8.1f} us a start  ({row['stream']})"
                f"  samples {heard['starts']:4d}  peak {heard['peak']:.3f}"
            )
            if heard["peak"] <= 0.0 and not row["case"].endswith("emitter_only"):
                failed.append(f"{row['case']}: nothing reached the output")
        print(f"samples started {sound['starts']}  output peak {sound['peak']:.3f}")
    for line in failed:
        print("FAIL", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
