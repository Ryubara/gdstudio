"""The bad-network gate, native half: a predicting client over a bad socket must stay with the server.

Starts the game server (`tools/net/gate_server.gd`, a free port), bots that give the client puppets to draw
(`tools/net/server_bot.gd`), a TCP relay with a delay each way (`tools/net/relay.py`), and the predicting client
(`tools/net/predict_bot.gd`) through the relay, in two runs: `freeze` (100 ms each way, the client's own thread frozen
for 0.5, 2 and 5 s) and `stalls` (100 ms each way, 1 % of the relayed chunks held 300 ms more, and everything behind
them: what a lost packet costs on TCP). Then it judges each client's report and the server's log against
`tools/net/bad_network.py` and exits 1 on any failed check.

    python tools/net/bad_network_gate.py --godot <pinned godot> --project game --out <folder>
        [--runs freeze,stalls] [--delay-ms 100] [--stall-chance 0.01] [--stall-ms 300] [--seconds 30] [--bots 3]
        [--url wss://<deployment>]      a running server instead of a local one (no relay: add --delay-ms 0)
        [--break hold|reconciler]       the teeth check: the server's hold or the client's #483 fix taken out
        [--expect-fail]                 exit 0 only when the gate failed (CI runs the teeth check with it)

Each process writes its output to a file under `--out` (a pipe kept a client from connecting:
multiplayer.md#measuring), and `result.json` holds each run's report, the relay's bytes and every check.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bad_network import Network, Verdict, errors_in, judge_client, judge_server, server_log  # noqa: E402
from relay import Relay  # noqa: E402

FREEZES = "8:500,16:2000,24:5000"
SETTLE_S = 2.0
START_TIMEOUT_S = 60.0
# name: (the client's freezes, the relay's stall chance; None takes --stall-chance)
RUNS: dict[str, tuple[str, float | None]] = {
    "freeze": (FREEZES, 0.0),
    "stalls": ("", None),
}


def godot_cmd(godot: str, project: Path, script: str, *args: str) -> list[str]:
    return [godot, "--headless", "--path", str(project), "-s", script, "--", *args]


def start(cmd: list[str], log: Path) -> subprocess.Popen:
    handle = log.open("w", encoding="utf-8")
    return subprocess.Popen(cmd, stdout=handle, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)


def stop(process: subprocess.Popen | None) -> None:
    """Stops a process and what the Windows console wrapper started (the tree), by its PID."""
    if process is None or process.poll() is not None:
        return
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(process.pid)], capture_output=True, check=False)
    else:
        process.kill()
    try:
        process.wait(10)
    except subprocess.TimeoutExpired:
        pass


def wait_for_port(log: Path, process: subprocess.Popen) -> int:
    began = time.monotonic()
    while time.monotonic() - began < START_TIMEOUT_S:
        if log.exists():
            for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith("{") and '"listening"' in line:
                    return int(json.loads(line)["port"])
        if process.poll() is not None:
            break
        time.sleep(0.2)
    raise SystemExit(f"the server did not start; read {log}")


def line_of(log: Path, tag: str) -> dict:
    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    for line in text.splitlines():
        if line.startswith(tag + " "):
            return json.loads(line[len(tag) + 1 :])
    return {"error": f"no {tag} line"}


def run(args: argparse.Namespace, name: str, out: Path) -> tuple[Verdict, dict]:
    """One run: a server (unless `--url`), the bots, the relay and the client; its verdict and its numbers."""
    out.mkdir(parents=True, exist_ok=True)
    freeze, stall_chance = RUNS[name]
    if stall_chance is None:
        stall_chance = args.stall_chance
    project = args.project.resolve()
    server = bots = client = None
    relay: Relay | None = None
    verdict = Verdict()
    result: dict = {"run": name, "freeze": freeze, "stall_chance": stall_chance}
    try:
        url = args.url
        if not url:
            server_args = ["--port", "0"] + (["--hold-ticks", "0"] if args.broken == "hold" else [])
            server = start(
                godot_cmd(args.godot, project, "res://tools/net/gate_server.gd", *server_args), out / "server.log"
            )
            url = f"ws://127.0.0.1:{wait_for_port(out / 'server.log', server)}"
        client_url = url
        if args.delay_ms > 0:
            scheme, rest = url.split("://", 1)
            host, _, port = rest.partition(":")
            if scheme != "ws":
                raise SystemExit("the relay passes ws:// only (a wss:// certificate names its own host)")
            relay = Relay(host, int(port), args.delay_ms / 1000.0, 0, stall_chance, args.stall_ms / 1000.0, args.seed)
            client_url = f"ws://127.0.0.1:{relay.start_in_thread()}"
        if args.bots > 0:
            bot_seconds = str(args.seconds + int(SETTLE_S) + 30)
            bot_args = ["--connect", url, "--bots", str(args.bots), "--seconds", bot_seconds]
            bots = start(godot_cmd(args.godot, project, "res://tools/net/server_bot.gd", *bot_args), out / "bots.log")
            time.sleep(3.0)
        client_args = ["--connect", client_url, "--seconds", str(args.seconds), "--freeze", freeze]
        if args.broken == "reconciler":
            client_args += ["--break", "reconciler"]
        client = start(
            godot_cmd(args.godot, project, "res://tools/net/predict_bot.gd", *client_args), out / "client.log"
        )
        try:
            client.wait(args.seconds + 120)
        except subprocess.TimeoutExpired:
            pass
    finally:
        stop(client)
        stop(bots)
        stop(server)
        if relay is not None:
            relay.stop()
    report = line_of(out / "client.log", "PREDICT_BOT")
    result["client"] = report
    network = Network(
        seconds=args.seconds,
        freezes=len([p for p in freeze.split(",") if p]),
        stall_s=args.stall_ms / 1000.0,
        stalls_up=relay.stalls_up if relay else 0,
        stalls_down=relay.stalls_down if relay else 0,
    )
    if relay is not None:
        result["relay"] = relay.counts()
    judge_client(report, network, verdict)
    client_errors = errors_in(out / "client.log")
    verdict.check("no ERROR in the client's log", not client_errors, client_errors)
    if server is not None:
        log = server_log(out / "server.log")
        result["server"] = log
        judge_server(log, verdict)
    result["checks"] = verdict.checks
    result["passed"] = verdict.passed
    return verdict, result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", required=True, help="the pinned Godot (console build on Windows)")
    parser.add_argument("--project", type=Path, required=True, help="the game folder (project.godot)")
    parser.add_argument("--out", type=Path, required=True, help="folder for the logs and result.json")
    parser.add_argument("--runs", default="freeze,stalls", help="the runs, comma-separated: freeze, stalls")
    parser.add_argument("--url", default="", help="a running server (ws:// or wss://) instead of a local one")
    parser.add_argument("--delay-ms", type=float, default=100.0, help="relay delay each way (0: no relay)")
    parser.add_argument("--stall-chance", type=float, default=0.01, help="chance a relayed chunk stalls (stalls run)")
    parser.add_argument("--stall-ms", type=float, default=300.0, help="what a stall costs")
    parser.add_argument("--seed", type=int, default=1, help="seed of the stalls")
    parser.add_argument("--seconds", type=int, default=30, help="seconds the client walks")
    parser.add_argument("--bots", type=int, default=3, help="bots that give the client puppets")
    parser.add_argument("--break", dest="broken", choices=["hold", "reconciler"], default="", help="teeth check")
    parser.add_argument("--expect-fail", action="store_true", help="exit 0 only when the gate failed")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.url and args.broken == "hold":
        raise SystemExit("--break hold needs the local server")
    names = [n for n in args.runs.split(",") if n]
    for name in names:
        if name not in RUNS:
            raise SystemExit(f"no run {name}: {', '.join(RUNS)}")

    results = []
    failures: list[str] = []
    for name in names:
        print(f"== {name}", flush=True)
        verdict, result = run(args, name, args.out / name)
        verdict.print(f"[{name}] ")
        if "relay" in result:
            print(f"RELAY [{name}] {result['relay']}", flush=True)
        results.append(result)
        failures += [f"{name}: {f}" for f in verdict.failures()]
    passed = not failures
    (args.out / "result.json").write_text(json.dumps({"runs": results, "passed": passed}, indent=2), encoding="utf-8")
    if args.expect_fail:
        print(
            "TEETH: the gate failed as it must: " + "; ".join(failures)
            if not passed
            else "TEETH FAILED: the gate passed with the fix taken out",
            flush=True,
        )
        return 0 if not passed else 1
    print("ALL PASSED" if passed else "FAILED: " + "; ".join(failures), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
