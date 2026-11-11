"""The online probe: the web build's online game joins a game server in headless Chromium, two pages at once.

Starts the game server (`tools/net/gate_server.gd`, a free port; `--other-version`: a server of the next protocol
version, `tools/net/other_version_server.gd`), a TCP relay with `--delay-ms` each way (`tools/net/relay.py`; the
browser's own throttling does not touch WebSockets), optional bots for more puppets (`tools/net/server_bot.gd`),
serves the exported game (`build/web`) and opens `--pages` pages with `?url=ws://<relay>&bot=...&onlineprobe`: the
menu goes straight to the online game (`OnlineMain`), whose `PlayerBot` plays through the player's own input (the
first page walks the route to the door, the others watch and shoot), and whose `OnlineProbe` writes what the client
measured to `window.gdonline`. After `--seconds` of play it reads every page's report and checks: every page seated,
every page sees every player, a round trip read, no body lost, the body within a metre of the server's point, no
`Buffer payload full` or other console error, and no ERROR or kick in the server's log. The pages open together and
join once their level's warm-up is over and their frames settle (`JoinWait`, kit #1142); each page records every
frame's length (`FRAME_WATCH` of `net_play_smoke.py`), and a page fails with more than `JOIN_HITCHES` frames past
0.25 s in the 3 s after its seat (the bad-network gate's bound). The frame time and the puppets' cost are recorded for
the docs (one page sees a puppet for each bot: `--bots` 1, 4 and 7 give 1, 4 and 7 puppets; with two pages, one more).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/online.py build/web build/online \\
        --godot <pinned godot> --project game [--pages 2] [--bots 0] [--delay-ms 100] [--seconds 20]
        [--url wss://<deployment> --delay-ms 0] [--gpu [--uncapped] [--warm-up 20]] [--other-version [--expect-refused]]

`--gpu` draws with the machine's GPU (ANGLE on Direct3D 11 on Windows). A first page plays `--warm-up` seconds before
the measured ones (20 with `--gpu`): Chrome compiles each shader program the first time it draws it, on the page's
thread, 12 to 14 s at once on a cold start, and the server hangs up on a socket that says no hello in 10 s; the
browser keeps what it compiled, so the measured pages read a returning player's frames. `--uncapped` turns vsync and
the frame cap off, so the frame time is the page's work and not 16.7 ms.

`--other-version` alone must fail (no page is seated: the teeth); with `--expect-refused` it passes only when every
page shows the overlay's "another version" message. `result.json`, the logs and a screenshot of each page go to the
second argument. Exits 1 on any check that fails. Run it under `gds quiet`.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import Browser, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "net"))
from bad_network import Verdict, judge_server, server_log
from bad_network_gate import godot_cmd, start, stop, wait_for_port
from net_play_smoke import (
    FRAME_WATCH,
    GPU_ARGS,
    HITCH_S,
    JOIN_HITCHES,
    JOIN_WINDOW_S,
    SOFTWARE_ARGS,
    hitches,
    serve,
    wait_for,
)
from relay import Relay

READY_TIMEOUT_S = 120.0
# Seconds a first page plays on the GPU before the measured pages open: Chrome on ANGLE's Direct3D 11 compiles each
# shader program the first time it draws it, blocking the page's thread (12 to 14 s at once on an RTX 5080), and the
# server hangs up on a socket that says no hello in `NetServer.hello_seconds` (10 s). The browser keeps what it
# compiled for its later pages, so the measured pages read a returning player's frames.
GPU_WARM_UP_S = 20.0
# Chrome's flags for frames as fast as the page can make them (`--uncapped`): with vsync a GPU page reads 16.7 ms at
# any load, which hides what a puppet costs.
UNCAPPED_ARGS = ["--disable-gpu-vsync", "--disable-frame-rate-limit"]
# The body may trail the server's point by what a round trip of walking covers (6 m/s sprinting, 0.25 s), plus the
# corrections under way.
GAP_M = 1.5
OLD_VERSION_TEXT = "another version"
# True once a page has stopped loading (`JoinWait`) and connecting: seated, refused or closed.
SETTLED = "window.gdonline && ['connecting', 'loading'].indexOf(window.gdonline.state) < 0"


def report_of(page: Page) -> dict:
    text = page.evaluate("() => (window.gdonline && window.gdonline.report) || '{}'")
    report = json.loads(text or "{}")
    report["state"] = page.evaluate("() => window.gdonline ? window.gdonline.state : 'no probe'")
    return report


def warm_up(browser: Browser, url: str, viewport: dict, seconds: float) -> dict:
    """Plays one page for `seconds` after it settles, so the browser has compiled the game's shaders; returns how long
    it took to settle, its state then and its frame times."""
    page = browser.new_context(viewport=viewport).new_page()
    began = time.time()
    page.goto(url)
    wait_for(page, SETTLED, READY_TIMEOUT_S)
    settled_s = time.time() - began
    time.sleep(seconds)
    report = report_of(page)
    page.context.close()
    keys = ("state", "fps", "frame_us_p50", "frame_us_p95")
    return {"settled_s": round(settled_s, 1)} | {k: report.get(k) for k in keys}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export folder (index.html)")
    parser.add_argument("out", type=Path, help="folder for result.json, the logs and the screenshots")
    parser.add_argument("--godot", required=True, help="the pinned Godot (console build on Windows)")
    parser.add_argument("--project", type=Path, required=True, help="the game folder (project.godot)")
    parser.add_argument("--url", default="", help="a running server (ws:// or wss://) instead of a local one")
    parser.add_argument("--pages", type=int, default=2, help="browser pages that join")
    parser.add_argument("--bots", type=int, default=0, help="headless bots that give the pages more puppets")
    parser.add_argument("--delay-ms", type=float, default=100.0, help="relay delay each way (0: no relay)")
    parser.add_argument("--seconds", type=float, default=20.0, help="seconds of play after the last page is seated")
    parser.add_argument("--gpu", action="store_true", help="draw with the machine's GPU instead of SwiftShader")
    parser.add_argument(
        "--warm-up",
        type=float,
        default=-1.0,
        help=f"seconds a first page plays before the measured ones (default {GPU_WARM_UP_S:g} with --gpu, else 0)",
    )
    parser.add_argument("--uncapped", action="store_true", help="with --gpu: vsync and the frame cap off")
    parser.add_argument("--viewport", default="320x180", help="each page's size, WxH (a small page draws faster)")
    parser.add_argument("--other-version", action="store_true", help="a server of the next protocol version")
    parser.add_argument("--expect-refused", action="store_true", help="pass only when every page was refused")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    project = args.project.resolve()
    verdict = Verdict()
    result: dict = {"args": {k: str(v) for k, v in vars(args).items()}}
    errors: list[str] = []
    server = bots = None
    relay: Relay | None = None
    http_server, http_port = serve(args.build)
    try:
        url = args.url
        if not url:
            script = (
                "res://tools/net/other_version_server.gd" if args.other_version else "res://tools/net/gate_server.gd"
            )
            server = start(godot_cmd(args.godot, project, script, "--port", "0"), args.out / "server.log")
            url = f"ws://127.0.0.1:{wait_for_port(args.out / 'server.log', server)}"
        page_url = url
        if args.delay_ms > 0:
            scheme, rest = url.split("://", 1)
            host, _, port = rest.partition(":")
            if scheme != "ws":
                raise SystemExit("the relay passes ws:// only: add --delay-ms 0 for a wss:// server")
            relay = Relay(host, int(port), args.delay_ms / 1000.0)
            page_url = f"ws://127.0.0.1:{relay.start_in_thread()}"
        warm = args.warm_up if args.warm_up >= 0 else (GPU_WARM_UP_S if args.gpu else 0.0)
        if args.bots > 0:
            seconds = int(READY_TIMEOUT_S * (args.pages + 1) + warm + args.seconds + 60)
            bot_args = ["--connect", url, "--bots", str(args.bots), "--seconds", str(seconds)]
            bots = start(
                godot_cmd(args.godot, project, "res://tools/net/server_bot.gd", *bot_args), args.out / "bots.log"
            )
        with sync_playwright() as playwright:
            launch_args = GPU_ARGS + (UNCAPPED_ARGS if args.uncapped else []) if args.gpu else SOFTWARE_ARGS
            browser = playwright.chromium.launch(args=launch_args)
            width, height = (int(n) for n in args.viewport.split("x"))
            viewport = {"width": width, "height": height}
            if warm > 0:
                warm_url = f"http://127.0.0.1:{http_port}/index.html?url={page_url}&bot=route&name=Warm&onlineprobe"
                result["warm_up"] = warm_up(browser, warm_url, viewport, warm)
                print(f"WARM-UP: {result['warm_up']}", flush=True)
            pages: list[Page] = []
            # Every page opens first and then each is waited for: a page opened after another was seated would load
            # its level, and SwiftShader its shaders, inside the first page's join window.
            for index in range(args.pages):
                page = browser.new_context(viewport=viewport).new_page()
                page.add_init_script(FRAME_WATCH)
                page.on(
                    "console", lambda m, i=index: errors.append(f"page {i}: {m.text}") if m.type == "error" else None
                )
                page.on("pageerror", lambda e, i=index: errors.append(f"page {i}: {e}"))
                plan = "route" if index == 0 else "watch"
                page.goto(
                    f"http://127.0.0.1:{http_port}/index.html?url={page_url}&bot={plan}&name=Web{index}&onlineprobe"
                )
                pages.append(page)
            for page in pages:
                wait_for(page, SETTLED, READY_TIMEOUT_S * args.pages)
            seated = all(report_of(page)["state"] == "seated" for page in pages)
            if seated:
                time.sleep(args.seconds)
            else:
                time.sleep(2.0)
            reports = [report_of(page) for page in pages]
            for page, report in zip(pages, reports):
                report["hitches"] = hitches(page)
            for index, page in enumerate(pages):
                page.screenshot(path=str(args.out / f"page{index + 1}.png"))
            browser.close()
        result["pages"] = reports
    finally:
        stop(bots)
        stop(server)
        if relay is not None:
            relay.stop()
            result["relay"] = relay.counts()
        http_server.shutdown()
    players = args.pages + args.bots
    if args.expect_refused:
        for index, report in enumerate(reports):
            verdict.check(
                f"page {index + 1} was refused for its version", report["state"] == "refused version", report["state"]
            )
            verdict.check(
                f"page {index + 1} says the server runs another version",
                OLD_VERSION_TEXT in report.get("message", ""),
                report.get("message", ""),
            )
    else:
        for index, report in enumerate(reports):
            name = f"page {index + 1}"
            verdict.check(f"{name} was seated", report["state"] == "seated", report["state"])
            verdict.check(
                f"{name} sees all {players} players", report.get("players", 0) == players, report.get("players")
            )
            verdict.check(f"{name} read a round trip", report.get("rtt_ms", -1) > 0, report.get("rtt_ms"))
            verdict.check(f"{name} lost no answer", report.get("lost", -1) == 0, report.get("lost"))
            gap = report.get("gap_m", -1.0)
            verdict.check(f"{name} is within {GAP_M} m of the server's point", 0.0 <= gap <= GAP_M, gap)
            seen = report.get("hitches", {})
            verdict.check(
                f"{name} drew at most {JOIN_HITCHES} frame past {HITCH_S} s in the {JOIN_WINDOW_S:g} s after its seat",
                seen.get("in_join_window", JOIN_HITCHES + 1) <= JOIN_HITCHES,
                {k: seen.get(k) for k in ("in_join_window", "join_window_ms", "unplanned", "worst_unplanned_ms")},
            )
        if server is not None:
            log = server_log(args.out / "server.log")
            result["server"] = log
            judge_server(log, verdict)
    payload_full = [e for e in errors if "Buffer payload full" in e]
    verdict.check("no Buffer payload full in the console", not payload_full, len(payload_full))
    verdict.check("no other console or page error", not errors, errors[:10])
    result["checks"] = verdict.checks
    result["passed"] = verdict.passed
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    verdict.print("[online] ")
    for index, report in enumerate(reports):
        keys = ("state", "players", "rtt_ms", "gap_m", "corrections", "corrected_m", "fps", "frame_us_p50")
        line = ", ".join(f"{k} {report.get(k)}" for k in keys)
        line += f", frame_us_p95 {report.get('frame_us_p95')}, puppets_us_p50 {report.get('puppets_us_p50')}"
        seen = report.get("hitches", {})
        line += f", settle_ms {report.get('settle_ms')}, wait_ms {report.get('wait_ms')}"
        line += f", hitches {seen.get('unplanned')} (join window {seen.get('in_join_window')}, worst"
        line += f" {seen.get('worst_unplanned_ms')} ms), links_after_seat {seen.get('links_after_seat')}"
        print(f"PAGE {index + 1}: {line}", flush=True)
    print("ALL PASSED" if verdict.passed else "FAILED: " + ", ".join(verdict.failures()), flush=True)
    return 0 if verdict.passed else 1


if __name__ == "__main__":
    sys.exit(main())
