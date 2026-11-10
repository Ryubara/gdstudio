"""Boots the web export in headless Chromium and fails when it does not come up clean.

Serves the exported game (`build/web`), opens it with `?probe` and waits for the game's `WebProbe` (or a menu's
`MenuProbe`) to report `ready` on `window.gdprobe`: the first frames of the main scene have run. It fails on

- a console error, a page error (an uncaught exception in the page),
- a request that failed or answered 400 or more (the favicon, which the export does not ship, is the one it skips),
- the game not reporting ready within `--limit-s` seconds (the engine's own `#status-notice`, shown when it cannot
  start, is printed with the failure).

It records, never gating on them (a shared runner moves a time by half): the seconds from the page's first request to
`ready`, the longest frame in the seconds after it (a first-use hitch shows here), and the sizes of the pack, the wasm
and the whole folder, so a pack or a load time that grows is seen in the pull request. The numbers go to
`<out>/boot.json`, to stdout and, when `GITHUB_STEP_SUMMARY` is set, to the job summary.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/boot_check.py build/web build/smoke

Exits 1 on any problem. Run it under `gds quiet`: a local headless browser can take the pointer
(`docs/engines/godot/web-probes.md`). The browser comes with `playwright install chromium-headless-shell`.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

READY_LIMIT_S = 60.0
SETTLE_S = 3.0
# Requests the export never makes on purpose: a browser asks for the icon whatever the page says.
IGNORED_URLS = ("/favicon.ico",)
# Software rendering, as on a CI runner without a GPU.
BROWSER_ARGS = ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]

# Runs before the page's own scripts: a frame loop that notes when the probe first says `ready` and the longest gap
# between two frames after it.
WATCH = """
(() => {
  const watch = { readyAt: null, last: null, longest: 0, frames: 0 };
  window.__boot = watch;
  const tick = (now) => {
    const probe = window.gdprobe;
    // `now` is when the frame began, which a blocked main thread leaves far behind the callback's run.
    if (watch.readyAt === null && probe && probe.ready === true) watch.readyAt = performance.now();
    if (watch.readyAt !== null) {
      watch.frames += 1;
      if (watch.last !== null) watch.longest = Math.max(watch.longest, now - watch.last);
    }
    watch.last = now;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
})();
"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:
        return


def serve(folder: Path) -> tuple[http.server.ThreadingHTTPServer, int]:
    handler = functools.partial(QuietHandler, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def sizes(build: Path) -> dict[str, int]:
    """Bytes of the files that decide the download, and of the whole folder."""
    files = {
        name: (build / name).stat().st_size
        for name in ("index.pck", "index.wasm", "index.js")
        if (build / name).is_file()
    }
    files["total"] = sum(path.stat().st_size for path in build.rglob("*") if path.is_file())
    return files


def notice(page: Page) -> str:
    """What the engine's page says when it cannot start (`#status-notice`), empty when it says nothing."""
    try:
        return page.evaluate("document.getElementById('status-notice')?.innerText || ''").strip()
    except Exception:  # noqa: BLE001 - the page may be gone
        return ""


def megabytes(size: int) -> str:
    return f"{size / 1_000_000:.1f} MB"


def report(title: str, result: dict) -> str:
    """The markdown table for the job summary."""
    rows = [
        ("Result", f"failed, {len(result['problems'])} problem(s) below" if result["problems"] else "booted"),
        (
            "To the first frames (the probe reports ready)",
            f"{result['ready_s']:.1f} s" if result["ready_s"] is not None else "never",
        ),
        ("Longest frame in the next seconds", f"{result['longest_frame_ms']:.0f} ms"),
        ("Pack (index.pck)", megabytes(result["sizes"].get("index.pck", 0))),
        ("Engine (index.wasm)", megabytes(result["sizes"].get("index.wasm", 0))),
        ("Whole export", megabytes(result["sizes"]["total"])),
    ]
    lines = [f"### {title}", "", "| | |", "| --- | --- |"]
    lines += [f"| {name} | {value} |" for name, value in rows]
    if result["problems"]:
        lines += ["", *[f"- `{line}`" for line in result["problems"][:10]]]
    return "\n".join(lines) + "\n"


def run(build: Path, out: Path, query: str, limit_s: float, settle_s: float) -> dict:
    server, port = serve(build)
    problems: list[str] = []
    seen: set[str] = set()

    def problem(kind: str, text: str) -> None:
        if text.lstrip().startswith("at:"):  # the second line of an engine error, which names its source file
            return
        line = f"{kind}: {text}"
        if line not in seen:
            seen.add(line)
            problems.append(line)

    ready_s: float | None = None
    longest = 0.0
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(args=BROWSER_ARGS)
        page = browser.new_context(viewport={"width": 1280, "height": 720}).new_page()
        page.add_init_script(WATCH)
        page.on("console", lambda m: problem("console error", m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: problem("page error", str(e)))
        page.on(
            "requestfailed",
            lambda r: None if r.url.endswith(IGNORED_URLS) else problem("request failed", f"{r.url} ({r.failure})"),
        )
        page.on(
            "response",
            lambda r: (
                problem("request answered", f"{r.status} {r.url}")
                if r.status >= 400 and not r.url.endswith(IGNORED_URLS)
                else None
            ),
        )
        page.goto(f"http://127.0.0.1:{port}/index.html?{query}", wait_until="load")
        try:
            page.wait_for_function("window.__boot.readyAt !== null", timeout=limit_s * 1000, polling="raf")
        except Exception:  # noqa: BLE001 - the timeout is the failure
            said = notice(page)
            problem(
                "no frame",
                f"the game did not report ready within {limit_s:.0f} s" + (f" (the page says: {said})" if said else ""),
            )
        else:
            time.sleep(settle_s)
            watch = page.evaluate("window.__boot")
            ready_s = watch["readyAt"] / 1000.0
            longest = float(watch["longest"])
            out.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(out / "boot.png"), timeout=60_000)
        browser.close()
    server.shutdown()
    return {
        "problems": problems,
        "ready_s": ready_s,
        "longest_frame_ms": longest,
        "sizes": sizes(build),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export's folder (build/web)")
    parser.add_argument("out", type=Path, help="where boot.json and boot.png go")
    parser.add_argument("--query", default="probe", help="the page's query string (default: probe)")
    parser.add_argument("--title", default="Web boot", help="the heading of the job summary's table")
    parser.add_argument("--limit-s", type=float, default=READY_LIMIT_S, help="seconds to wait for the first frames")
    parser.add_argument("--settle-s", type=float, default=SETTLE_S, help="seconds to watch after the first frames")
    args = parser.parse_args()
    if not (args.build / "index.html").is_file():
        print(f"no index.html in {args.build}: export the web build first", file=sys.stderr)
        return 1
    started = time.time()
    result = run(args.build, args.out, args.query, args.limit_s, args.settle_s)
    result["check_s"] = round(time.time() - started, 1)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "boot.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    text = report(args.title, result)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(text + "\n")
    for line in result["problems"]:
        print("FAIL " + line, file=sys.stderr)
    return 1 if result["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
