"""The bad-network gate, browser half: the web build's predicting client stays with the server through a bad socket
and a frozen tab.

Starts the game server (`tools/net/gate_server.gd`, a free port), bots that give the page puppets to draw
(`tools/net/server_bot.gd`) and a TCP relay with 100 ms each way (`tools/net/relay.py`; the browser's own throttling
does not touch WebSockets), serves the exported game (`build/web`) and opens it in headless Chromium with
`?play&netplay&url=ws://<relay>`: the game's `NetPlayProbe` plays online with a predicting client whose body walks
circles, and writes what it measured to `window.gdnet`. The page's main thread is frozen (a busy loop, the freeze a
player gets) for 0.5, 2 and 5 s at 8, 16 and 24 s; at 30 s the body stands, and two seconds later the report is
judged with the native gate's thresholds (`tools/net/bad_network.py`): no body lost, a snap for the join and for each
freeze, worst error under 6 m a stall (hitches closer than a round trip add up), settled under 5 cm, corrections and
starved puppets within what the network allows, no `Buffer payload full` or other console error, nobody kicked and no
ERROR in the server's log. The page also records every frame's length and the GL programs linked in it: the report's
`hitches` lists each frame past 0.25 s after the seat (the planned freezes marked), and the gate fails on more than
one in the first 3 s after the seat (the probe joins after the level's warm-up and its last slow frames, kit #1106).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/net_play_smoke.py build/web build/net_play \\
        --godot <pinned godot> --project game [--url wss://<deployment> --delay-ms 0] [--stall-chance 0.01]
        [--break hold --expect-fail]

With `--ai 40` the server also runs a crowd of 40 AI characters (`gate_server.gd --ai`): the page draws them from the
TICK's AI block and its report's `ai` holds what applying them cost (gdstudio #970).

With `--unread 60` the page does not freeze: the relay stops reading what the server sends for 60 s from 8 s after
the seat (the page still plays and sends; a page that also stops sending is hung up on after the server's 15 s of
silence), with `--bots 7` for eight players' TICKs; then the burst of what waited must reach the page without a
`Buffer payload full`, the body must settle on the server's place and nobody is kicked.

`result.json` and the logs go to the second argument. Exits 1 on any check that fails. Run it under `gds quiet`.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "net"))
from bad_network import END_GAP_M, Network, Verdict, judge_client, judge_server, judge_server_clock, server_log
from bad_network_gate import godot_cmd, start, stop, wait_for_port
from relay import Relay

READY_TIMEOUT_S = 120.0
# Seconds after the seat, milliseconds of the page's thread frozen.
FREEZES = [(8.0, 500), (16.0, 2000), (24.0, 5000)]
WALK_S = 30.0
SETTLE_S = 2.0
# Seconds the page walks on after a stalled downlink before it stands (`--unread`).
UNREAD_CATCH_UP_S = 10.0
# A page drawn slower than this runs fewer physics steps than the server (the engine's catch-up is 8 a frame) and
# hitches past the stall guard's 0.25 s: SwiftShader drew the 1280x720 page at 6 frames a second, 320x180 at 40.
MIN_FPS = 20
SOFTWARE_ARGS = ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
GPU_ARGS = ["--enable-gpu", "--ignore-gpu-blocklist"]
# A frame longer than this is a hitch: the stall guard's `STALL_SECONDS`, past which the client resyncs.
HITCH_S = 0.25
# Hitches of `HITCH_S` allowed in the join's window: a page that joins after the warm-up had none in six of seven runs
# and one of 302 ms with nothing linked in the seventh (the machine); one that joined during it had four to six.
JOIN_HITCHES = 1
# A frame longer than the server's hold (four steps at 60 a second) sends its commands too late for it: the server
# repeats the last one, and the answers correct the body. Counted, not judged.
HOLD_MS = 4000 / 60
# A frame longer than two at 60 a second: the join's window lists each one (gdstudio #1208).
SLOW_MS = 2000 / 60
# The seconds after the seat whose hitches the report lists apart (kit issue #1106: the join's).
JOIN_WINDOW_S = 3.0
# Before the game loads: every frame's length (`performance.now()` read inside the requestAnimationFrame callback,
# web-probes.md#boot-check), the GL programs linked in it and their milliseconds (first-use-hitches.md#how-to-find-it),
# the moment the probe said `seated` (`window.gdnet`, or the online game's `window.gdonline`: `online.py`) and the
# planned freezes, so a hitch is told from a freeze and its cause named.
FRAME_WATCH = """
(() => {
  const w = window;
  w.__frames = []; w.__freezes = []; w.__seat = -1;
  let links = 0, linkMs = 0, last = -1;
  const proto = WebGL2RenderingContext.prototype;
  const link = proto.linkProgram, param = proto.getProgramParameter;
  proto.linkProgram = function (p) { p.__t = performance.now(); return link.call(this, p); };
  proto.getProgramParameter = function (p, n) {
    const r = param.call(this, p, n);
    if (n === this.LINK_STATUS && p.__t) { links += 1; linkMs += performance.now() - p.__t; p.__t = 0; }
    return r;
  };
  const tick = () => {
    const now = performance.now();
    const probe = w.gdnet || w.gdonline;
    if (w.__seat < 0 && probe && probe.state === 'seated') { w.__seat = now; }
    if (last >= 0) { w.__frames.push([last, now - last, links, Math.round(linkMs)]); }
    links = 0; linkMs = 0; last = now;
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


def wait_for(page: Page, expression: str, timeout_s: float) -> bool:
    began = time.monotonic()
    while time.monotonic() - began < timeout_s:
        if page.evaluate(f"() => {{ try {{ return !!({expression}); }} catch (e) {{ return false; }} }}"):
            return True
        time.sleep(0.2)
    return False


def report_of(page: Page) -> dict:
    text = page.evaluate("() => (window.gdnet && window.gdnet.report) || '{}'")
    return json.loads(text or "{}")


def hitches(page: Page) -> dict:
    """The page's frames past `HITCH_S` after the seat, the planned freezes told apart, with the programs each linked."""
    seat, frames, freezes = page.evaluate("() => [window.__seat, window.__frames, window.__freezes]")
    if seat < 0:
        return {"error": "no seat seen"}
    out = []
    for began, ms, links, link_ms in frames:
        if began + ms < seat or ms < HITCH_S * 1000:
            continue
        planned = any(began <= at + 50 and at <= began + ms for at, _ in freezes)
        at_s = round((began - seat) / 1000, 2)
        out.append({"at_s": at_s, "ms": round(ms), "links": links, "link_ms": link_ms, "planned": planned})
    unplanned = [h for h in out if not h["planned"]]
    joined = [h for h in unplanned if h["at_s"] < JOIN_WINDOW_S]
    after = [f for f in frames if f[0] >= seat]
    lengths = sorted(f[1] for f in after if not any(f[0] <= at + 50 and at <= f[0] + f[1] for at, _ in freezes))
    # The longest frame of the join's window, whatever its length (the first AI snapshot's puppets, gdstudio #1208).
    joining = [f for f in after if f[0] - seat < JOIN_WINDOW_S * 1000]
    join_frames = [f[1] for f in joining]
    return {
        "frames": len(after),
        "frame_ms_p50": round(lengths[len(lengths) // 2]) if lengths else -1,
        "frame_ms_p95": round(lengths[int(len(lengths) * 0.95)]) if lengths else -1,
        "over_hold": sum(1 for ms in lengths if ms > HOLD_MS),
        "unplanned": len(unplanned),
        "in_join_window": len(joined),
        "join_window_ms": sum(h["ms"] for h in joined),
        "join_worst_ms": round(max(join_frames, default=0)),
        # Each frame of the join's window longer than two at 60 a second: seconds after the seat, its length, programs
        # linked and their milliseconds.
        "join_slow": [[round((f[0] - seat) / 1000, 2), round(f[1]), f[2], f[3]] for f in joining if f[1] > SLOW_MS],
        "links_after_seat": sum(f[2] for f in after),
        "worst_unplanned_ms": max((h["ms"] for h in unplanned), default=0),
        "list": out,
    }


def play(page: Page, relay: Relay | None = None, unread_s: float = 0.0) -> dict:
    """Walks, freezes the page's thread at the planned moments (or stalls its downlink `unread_s` from the first
    freeze's moment), stands, and returns the report."""
    seated_at = time.monotonic()
    walk_s = WALK_S
    if unread_s > 0.0 and relay is not None:
        time.sleep(FREEZES[0][0])
        relay.hold_down(unread_s)
        walk_s = FREEZES[0][0] + unread_s + UNREAD_CATCH_UP_S
    for at, ms in FREEZES if unread_s <= 0.0 else []:
        wait = at - (time.monotonic() - seated_at)
        if wait > 0:
            time.sleep(wait)
        page.evaluate(
            f"() => {{ const t = performance.now(), end = t + {ms}; window.__freezes.push([t, {ms}]);"
            " while (performance.now() < end) {} }"
        )
    time.sleep(max(0.0, walk_s - (time.monotonic() - seated_at)))
    page.evaluate("() => { window.gdnet.stop = true; }")
    wait_for(page, "JSON.parse(window.gdnet.report).standing", 10)
    time.sleep(SETTLE_S)
    report = report_of(page)
    report["walk_s"] = round(time.monotonic() - seated_at, 1)
    report["hitches"] = hitches(page)
    report["settle_ms"] = page.evaluate("() => window.gdnet.settle_ms === undefined ? -1 : window.gdnet.settle_ms")
    return report


def judge_unread(report: dict, verdict: Verdict) -> None:
    """A stalled downlink: the puppets starve and the answers stop for its length by design, so only what must hold
    after it is judged: seated throughout, no body lost, settled on the server's place."""
    seated = "error" not in report and report.get("slot", -1) >= 0
    verdict.check("the client was seated", seated, {"slot": report.get("slot"), "error": report.get("error")})
    if not seated:
        return
    verdict.check("no answer more than 6 m off", report["lost"] == 0, report["lost"])
    gap = report.get("end_gap_m", report.get("gap_m", -1.0))
    verdict.check(f"settled under {END_GAP_M} m", 0.0 <= gap < END_GAP_M, gap)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="the web export folder (index.html)")
    parser.add_argument("out", type=Path, help="folder for result.json and the logs")
    parser.add_argument("--godot", required=True, help="the pinned Godot (console build on Windows)")
    parser.add_argument("--project", type=Path, required=True, help="the game folder (project.godot)")
    parser.add_argument("--url", default="", help="a running server (ws:// or wss://) instead of a local one")
    parser.add_argument("--delay-ms", type=float, default=100.0, help="relay delay each way (0: no relay)")
    parser.add_argument("--stall-chance", type=float, default=0.0, help="chance a relayed chunk stalls")
    parser.add_argument("--stall-ms", type=float, default=300.0, help="what a stall costs")
    parser.add_argument("--bots", type=int, default=3, help="bots that give the page puppets")
    parser.add_argument("--break", dest="broken", choices=["hold"], default="", help="teeth check: no server hold")
    parser.add_argument("--unread", type=float, default=0.0, help="seconds the downlink stalls instead of freezes")
    parser.add_argument("--expect-fail", action="store_true", help="exit 0 only when the gate failed")
    parser.add_argument("--gpu", action="store_true", help="draw with the machine's GPU instead of SwiftShader")
    parser.add_argument("--viewport", default="320x180", help="the page's size, WxH (a small page draws faster)")
    parser.add_argument("--ai", type=int, default=0, help="an AI crowd of this many on the server (gate_server --ai)")
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
            server_args = ["--port", "0"] + (["--hold-ticks", "0"] if args.broken else [])
            server_args += ["--ai", str(args.ai)] if args.ai > 0 else []
            server = start(
                godot_cmd(args.godot, project, "res://tools/net/gate_server.gd", *server_args),
                args.out / "server.log",
            )
            url = f"ws://127.0.0.1:{wait_for_port(args.out / 'server.log', server)}"
        page_url = url
        if args.delay_ms > 0 or args.unread > 0:
            scheme, rest = url.split("://", 1)
            host, _, port = rest.partition(":")
            if scheme != "ws":
                raise SystemExit("the relay passes ws:// only: add --delay-ms 0 for a wss:// server")
            relay = Relay(host, int(port), args.delay_ms / 1000.0, 0, args.stall_chance, args.stall_ms / 1000.0)
            page_url = f"ws://127.0.0.1:{relay.start_in_thread()}"
        if args.bots > 0:
            bot_args = [
                "--connect",
                url,
                "--bots",
                str(args.bots),
                "--seconds",
                str(int(READY_TIMEOUT_S + WALK_S + args.unread + 60)),
            ]
            bots = start(
                godot_cmd(args.godot, project, "res://tools/net/server_bot.gd", *bot_args), args.out / "bots.log"
            )
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(args=GPU_ARGS if args.gpu else SOFTWARE_ARGS)
            width, height = (int(n) for n in args.viewport.split("x"))
            page = browser.new_page(viewport={"width": width, "height": height})
            page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.add_init_script(FRAME_WATCH)
            page.goto(f"http://127.0.0.1:{http_port}/index.html?play&netplay&url={page_url}")
            seated = wait_for(page, "window.gdnet && window.gdnet.state === 'seated'", READY_TIMEOUT_S)
            state = page.evaluate("() => window.gdnet ? window.gdnet.state : 'no probe'")
            if seated:
                report = play(page, relay, args.unread)
            else:
                report = {"error": f"not seated: {state}"}
            report["end_gap_m"] = report.get("gap_m", -1.0)
            result["client"] = report
            page.screenshot(path=str(args.out / "page.png"))
            browser.close()
    finally:
        stop(bots)
        stop(server)
        if relay is not None:
            relay.stop()
            result["relay"] = relay.counts()
        http_server.shutdown()
    network = Network(
        seconds=WALK_S,
        freezes=len(FREEZES),
        stall_s=args.stall_ms / 1000.0,
        stalls_up=relay.stalls_up if relay else 0,
        stalls_down=relay.stalls_down if relay else 0,
        real=bool(args.url) and relay is None,
        page=True,
    )
    fps = result["client"].get("fps", 0)
    verdict.check(
        f"the page drew at least {MIN_FPS} frames a second (else the run measures the machine)", fps >= MIN_FPS, fps
    )
    if args.unread > 0:
        judge_unread(result["client"], verdict)
    else:
        judge_client(result["client"], network, verdict)
    if "hitches" in result["client"]:
        joined = result["client"]["hitches"].get("in_join_window", -1)
        verdict.check(
            f"at most {JOIN_HITCHES} hitch past {HITCH_S} s in the {JOIN_WINDOW_S:.0f} s after the seat (the warm-up's)",
            0 <= joined <= JOIN_HITCHES,
            {k: v for k, v in result["client"]["hitches"].items() if k != "list"},
        )
    payload_full = [e for e in errors if "Buffer payload full" in e]
    verdict.check("no Buffer payload full in the console", not payload_full, len(payload_full))
    verdict.check("no other console or page error", not errors, errors[:10])
    if server is not None:
        log = server_log(args.out / "server.log")
        result["server"] = log
        judge_server(log, verdict)
        judge_server_clock(log, verdict)
    result["checks"] = verdict.checks
    result["passed"] = verdict.passed
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    verdict.print("[browser] ")
    if "relay" in result:
        print("RELAY " + result["relay"], flush=True)
    if args.expect_fail:
        print(
            "TEETH: the gate failed as it must: " + ", ".join(verdict.failures())
            if not verdict.passed
            else "TEETH FAILED: the gate passed with the fix taken out",
            flush=True,
        )
        return 0 if not verdict.passed else 1
    print("ALL PASSED" if verdict.passed else "FAILED: " + ", ".join(verdict.failures()), flush=True)
    return 0 if verdict.passed else 1


if __name__ == "__main__":
    sys.exit(main())
