"""The GL programs the web build links, recorded for `ShaderPrelink`, and how long a cold page waits for them.

The Compatibility renderer links each program at its first draw and waits for it, one after another: a browser that
has never drawn the game waited about 21 s on its GPU (kit issue #1164). `ShaderPrelink` (`addons/gds_game/`) links a
recorded list all at once while the menu scene starts; this writes that list and measures the result.

Record (the page with `?noprelink`, so the game's own links are what is seen; SwiftShader writes the same programs as a
GPU, give `--gpu` to use one):

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/shader_programs.py build/web build/shader_programs \\
        --write assets/shaders/web/shader_programs.json [--query play] [--merge]

Measure a cold page (a fresh browser profile each run) with the list in the build, or without it (`--off`):

    ... shader_programs.py build/web build/shader_programs --gpu [--off] [--runs 3] [--warm]

Each run waits for the first program and then until none is linked for `--quiet-s`, and reports the programs the
game linked, their milliseconds, the seconds from the page's start to the end of the last link (`last_link_s`), the
slowest frames and, with the list, how many of the game's programs it lacked (`missed`) and its own seconds
(`prelink_ms`). `--warm` loads the page twice in one browser profile and measures the second (a returning player).
`--write` keeps every program seen in any run (with `--merge`, also those already in the file). Exits 1 when a page
links nothing or a run times out. Run it under `gds quiet`.
"""

from __future__ import annotations

import argparse
import functools
import hashlib
import http.server
import json
import shutil
import tempfile
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from playwright.sync_api import Page

FORMAT = 1
GPU_ARGS = ["--enable-gpu", "--ignore-gpu-blocklist"]
SOFTWARE_ARGS = ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
# A shared line run shorter than this is written out: a reference costs about as much as two short lines.
LEAST_RUN = 2
# How many earlier places of a line the encoder tries for the longest run from it.
CANDIDATES = 48

# Every program the game links (its shaders' sources, attribute bindings and transform feedback), the milliseconds
# from `linkProgram` to the `LINK_STATUS` read that waits for it, and every frame's length. A context whose
# A program whose `__prelink` flag is set is ShaderPrelink's own and is left out.
HOOK = r"""
(() => {
  const w = window;
  w.__programs = []; w.__links = []; w.__frames = [];
  const proto = WebGL2RenderingContext.prototype;
  const source = proto.shaderSource, attach = proto.attachShader, bind = proto.bindAttribLocation;
  const feedback = proto.transformFeedbackVaryings, link = proto.linkProgram, param = proto.getProgramParameter;
  proto.shaderSource = function (s, text) { s.__source = text; return source.call(this, s, text); };
  proto.attachShader = function (p, s) { (p.__stages = p.__stages || []).push(s); return attach.call(this, p, s); };
  proto.bindAttribLocation = function (p, at, name) {
    (p.__attributes = p.__attributes || []).push([at, name]); return bind.call(this, p, at, name);
  };
  proto.transformFeedbackVaryings = function (p, names, mode) {
    p.__feedback = [Array.from(names), mode]; return feedback.call(this, p, names, mode);
  };
  proto.linkProgram = function (p) {
    if (!p.__prelink) {
      const stages = (p.__stages || []).map((s) => [this.getShaderParameter(s, this.SHADER_TYPE), s.__source]);
      w.__programs.push({ stages, attributes: p.__attributes || [], feedback: p.__feedback || null });
      p.__t = performance.now();
    }
    return link.call(this, p);
  };
  proto.getProgramParameter = function (p, n) {
    const r = param.call(this, p, n);
    if (n === this.LINK_STATUS && p.__t) { w.__links.push([p.__t, performance.now() - p.__t]); p.__t = 0; }
    return r;
  };
  let last = -1;
  const tick = () => {
    const now = performance.now();
    if (last >= 0) { w.__frames.push([last, now - last]); }
    last = now; requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
})();
"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves the export without a log line a request."""

    def log_message(self, *_args: object) -> None:
        return


def program_key(program: dict) -> str:
    """One program's identity: its sources, bindings and feedback."""
    return hashlib.sha1(json.dumps(program, sort_keys=True).encode()).hexdigest()


def encode(programs: list[dict], godot: str) -> dict:
    """The list ShaderPrelink reads: each shader once, its lines written out or as runs of the lines before it."""
    shader_index: dict[tuple[int, str], int] = {}
    for program in programs:
        for kind, text in program["stages"]:
            shader_index.setdefault((kind, text), len(shader_index))
    stream: list[str] = []
    places: dict[str, list[int]] = {}
    shaders = []
    for kind, text in shader_index:
        lines = text.split("\n")
        items: list = []
        at = 0
        while at < len(lines):
            best_start, best_length = 0, 0
            for start in places.get(lines[at], [])[-CANDIDATES:]:
                length = 0
                while (
                    at + length < len(lines)
                    and start + length < len(stream)
                    and stream[start + length] == lines[at + length]
                ):
                    length += 1
                if length > best_length:
                    best_start, best_length = start, length
            if best_length >= LEAST_RUN:
                items.append([best_start, best_length])
                at += best_length
            else:
                items.append(lines[at])
                at += 1
        for line in lines:
            places.setdefault(line, []).append(len(stream))
            stream.append(line)
        shaders.append([kind, items])
    encoded_programs = [
        [[shader_index[(kind, text)] for kind, text in p["stages"]], p["attributes"], p["feedback"]] for p in programs
    ]
    return {"format": FORMAT, "godot": godot, "shaders": shaders, "programs": encoded_programs}


def decode(data: dict) -> list[dict]:
    """The programs of a list `encode` wrote (the page's decoder, in Python: the tests and `--merge`)."""
    stream: list[str] = []
    texts: list[tuple[int, str]] = []
    for kind, items in data["shaders"]:
        lines: list[str] = []
        for item in items:
            if isinstance(item, str):
                lines.append(item)
            else:
                lines.extend(stream[item[0] : item[0] + item[1]])
        stream.extend(lines)
        texts.append((kind, "\n".join(lines)))
    return [
        {"stages": [list(texts[i]) for i in stages], "attributes": attributes, "feedback": feedback}
        for stages, attributes, feedback in data["programs"]
    ]


def unique(programs: list[dict]) -> list[dict]:
    """Each program once, in the order first seen."""
    seen: dict[str, dict] = {}
    for program in programs:
        seen.setdefault(program_key(program), program)
    return list(seen.values())


def measure(page: Page, url: str, quiet_s: float, timeout_s: float) -> dict:
    """Loads the page and waits until it has linked something and then nothing for `quiet_s`."""
    began = time.monotonic()
    page.goto(url)
    count, changed = 0, time.monotonic()
    while time.monotonic() - began < timeout_s:
        now = page.evaluate("() => window.__links.length")
        if now != count:
            count, changed = now, time.monotonic()
        if now > 0 and time.monotonic() - changed > quiet_s:
            break
        time.sleep(0.25)
    else:
        return {"error": f"still linking after {timeout_s} s"}
    return page.evaluate(
        "() => ({programs: window.__programs, links: window.__links, frames: window.__frames,"
        " godot: window.gdsEngine || '', prelink: window.gdsPrelink ? {total: window.gdsPrelink.total,"
        " began: window.gdsPrelink.began, ms: window.gdsPrelink.ms, done: window.gdsPrelink.done, skipped: window.gdsPrelink.skipped} : null})"
    )


def defines(program: dict) -> str:
    """A program's `#define` lines, the hint of which material and variant it is."""
    lines = (line for _, text in program["stages"] for line in text.split("\n"))
    return " ".join(line.removeprefix("#define ") for line in lines if line.startswith("#define "))[:160]


def slowest_links(seen: dict, keys: list[str], listed: set[str], count: int = 6) -> list[list]:
    """The slowest links: milliseconds, the second it began, whether the list had the program, its defines."""
    # Every program recorded at `linkProgram` is read at once (`LINK_STATUS`), so the two lists keep one order.
    rows = [
        [
            round(ms),
            round(at / 1000, 2),
            keys[i] in listed if i < len(keys) else None,
            defines(seen["programs"][i]) if i < len(keys) else "",
        ]
        for i, (at, ms) in enumerate(seen["links"])
    ]
    return sorted(rows, key=lambda row: -row[0])[:count]


def summary(seen: dict, listed: set[str]) -> dict:
    """The numbers of one page: links, milliseconds, the end of the last link, the slowest frames, what was missed."""
    links = seen["links"]
    keys = [program_key(p) for p in seen["programs"]]
    return {
        "programs": len(links),
        "link_ms": round(sum(ms for _, ms in links)),
        "first_link_s": round(links[0][0] / 1000, 2) if links else -1,
        "last_link_s": round((links[-1][0] + links[-1][1]) / 1000, 2) if links else -1,
        "slowest_frames_ms": sorted((round(ms) for _, ms in seen["frames"]), reverse=True)[:5],
        "missed": sum(1 for key in set(keys) if key not in listed) if listed else -1,
        "slowest_links": slowest_links(seen, keys, listed),
        "prelink": seen["prelink"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export folder (index.html)")
    parser.add_argument("out", type=Path, help="folder for result.json")
    parser.add_argument("--write", type=Path, default=None, help="write the list of programs seen here")
    parser.add_argument("--merge", action="store_true", help="with --write: keep the programs already in the file")
    parser.add_argument("--list", type=Path, default=None, help="the list in the build, to count what it missed")
    parser.add_argument("--query", default="play", help="the page's query (`play`: straight to the game)")
    parser.add_argument("--gpu", action="store_true", help="draw with the machine's GPU instead of SwiftShader")
    parser.add_argument("--off", action="store_true", help="measure without the prelink (`?noprelink`)")
    parser.add_argument("--warm", action="store_true", help="measure a second load in the same browser profile")
    parser.add_argument("--runs", type=int, default=1, help="cold pages, each in a fresh browser")
    parser.add_argument("--quiet-s", type=float, default=10.0, help="seconds without a link that end a run")
    parser.add_argument("--timeout-s", type=float, default=240.0, help="seconds a run may take")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    query = args.query + ("&noprelink" if args.off or args.write else "")
    listed: set[str] = set()
    if args.list and args.list.is_file():
        listed = {program_key(p) for p in decode(json.loads(args.list.read_text(encoding="utf-8")))}
    handler = functools.partial(QuietHandler, directory=str(args.build))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_address[1]}/index.html?{query}"
    from playwright.sync_api import sync_playwright  # here: the encoder's tests run without a browser

    runs: list[dict] = []
    programs: list[dict] = []
    godot = ""
    failed = False
    try:
        with sync_playwright() as playwright:
            for _ in range(args.runs):
                profile = Path(tempfile.mkdtemp(prefix="gds-prelink-"))
                try:
                    context = playwright.chromium.launch_persistent_context(
                        str(profile),
                        args=GPU_ARGS if args.gpu else SOFTWARE_ARGS,
                        viewport={"width": 640, "height": 360},
                    )
                    context.add_init_script(HOOK)
                    page = context.new_page()
                    if args.warm:
                        measure(page, url, args.quiet_s, args.timeout_s)
                    seen = measure(page, url, args.quiet_s, args.timeout_s)
                    context.close()
                finally:
                    shutil.rmtree(profile, ignore_errors=True)
                if "error" in seen or not seen["links"]:
                    failed = True
                    runs.append({"error": seen.get("error", "nothing linked")})
                    continue
                godot = seen["godot"] or godot
                programs.extend(seen["programs"])
                runs.append(summary(seen, listed))
                print(json.dumps(runs[-1]))
    finally:
        server.shutdown()
    result = {"query": query, "gpu": args.gpu, "warm": args.warm, "runs": runs}
    if args.write and programs:
        if not godot:
            print("the page did not say which Godot made it (window.gdsEngine): is ShaderPrelink started?")
            return 1
        if args.merge and args.write.is_file():
            programs = decode(json.loads(args.write.read_text(encoding="utf-8"))) + programs
        kept = unique(programs)
        args.write.parent.mkdir(parents=True, exist_ok=True)
        text = json.dumps(encode(kept, godot), separators=(",", ":")) + "\n"
        args.write.write_text(text, encoding="utf-8", newline="\n")
        result["written"] = {"path": str(args.write), "programs": len(kept), "bytes": args.write.stat().st_size}
        print(json.dumps(result["written"]))
    (args.out / "result.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
