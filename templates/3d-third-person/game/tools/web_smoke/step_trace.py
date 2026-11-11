"""Whether the character's step gives the same numbers in the web build as on the desktop: the step trace.

Opens the exported game (`build/web`) in headless Chromium with `?play&steptrace` (the game's `StepTraceProbe` steps a
body 1800 times with commands of the step's number alone and writes its positions to `window.gdtrace`), runs the same
trace natively with the given Godot (`--headless --path <game> -- --play --steptrace`, its `STEP_TRACE` line), and
compares them with any traces given as files (`--trace linux.json`, a `STEP_TRACE` line or its JSON, from a Linux
Godot). It prints, for each pair, the largest distance between two positions of the same step and the first step at
which they differ, and writes every trace and the comparison to `<out>/step_trace.json`. Exits 1 when the web trace
and the native one differ by more than `--tolerance` metres (default 0: the same floats).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/step_trace.py build/web build/step_trace \\
        --godot <pinned godot> --project game [--trace linux.json] [--tolerance 0.001]
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
from net_play_smoke import SOFTWARE_ARGS, serve, wait_for

TIMEOUT_S = 180.0


def parse(text: str) -> list[tuple[float, float, float]]:
    """The positions of a `STEP_TRACE` line, or of its JSON."""
    text = text.strip()
    if text.startswith("STEP_TRACE "):
        text = text[len("STEP_TRACE ") :]
    data = json.loads(text)
    return [tuple(float(n) for n in point.split(",")) for point in data["trace"]]


def native(godot: str, project: Path, out: Path) -> list[tuple[float, float, float]]:
    log = out / "native.log"
    with log.open("w", encoding="utf-8") as handle:
        subprocess.run(
            [godot, "--headless", "--path", str(project), "--", "--play", "--steptrace"],
            stdout=handle,
            stderr=subprocess.STDOUT,
            timeout=TIMEOUT_S,
            check=False,
        )
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("STEP_TRACE "):
            return parse(line)
    raise SystemExit(f"no STEP_TRACE line in {log}")


def web(build: Path) -> list[tuple[float, float, float]]:
    http_server, port = serve(build)
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(args=SOFTWARE_ARGS)
            page = browser.new_page(viewport={"width": 320, "height": 180})
            page.goto(f"http://127.0.0.1:{port}/index.html?play&steptrace")
            if not wait_for(page, "window.gdtrace && window.gdtrace.done", TIMEOUT_S):
                raise SystemExit("the page wrote no trace")
            text = page.evaluate("() => window.gdtrace.trace")
            browser.close()
    finally:
        http_server.shutdown()
    return parse(text)


def compare(a: list, b: list, every: int) -> dict:
    gaps = [math.dist(p, q) for p, q in zip(a, b, strict=False)]
    first = next((i for i, gap in enumerate(gaps) if gap > 0.0), -1)
    return {
        "worst_m": max(gaps) if gaps else -1.0,
        "end_m": gaps[-1] if gaps else -1.0,
        "first_step": (first + 1) * every if first >= 0 else -1,
        "points": len(gaps),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export folder (index.html)")
    parser.add_argument("out", type=Path, help="folder for step_trace.json and the native log")
    parser.add_argument("--godot", required=True, help="the pinned Godot (console build on Windows)")
    parser.add_argument("--project", type=Path, required=True, help="the game folder (project.godot)")
    parser.add_argument("--trace", type=Path, action="append", default=[], help="another platform's trace file")
    parser.add_argument("--tolerance", type=float, default=0.0, help="metres the web and native traces may differ")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    traces = {"web": web(args.build), "native": native(args.godot, args.project.resolve(), args.out)}
    for path in args.trace:
        traces[path.stem] = parse(path.read_text(encoding="utf-8"))
    names = list(traces)
    result: dict = {"traces": {k: [list(p) for p in v] for k, v in traces.items()}, "pairs": {}}
    for i, first in enumerate(names):
        for second in names[i + 1 :]:
            pair = compare(traces[first], traces[second], 30)
            result["pairs"][f"{first}-{second}"] = pair
            print(
                f"{first} vs {second}: worst {pair['worst_m']:.9f} m, end {pair['end_m']:.9f} m, "
                f"first differs at step {pair['first_step']}",
                flush=True,
            )
    (args.out / "step_trace.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    worst = result["pairs"]["web-native"]["worst_m"]
    print("SAME" if worst <= args.tolerance else f"DIFFERENT: {worst:.9f} m", flush=True)
    return 0 if worst <= args.tolerance else 1


if __name__ == "__main__":
    sys.exit(main())
