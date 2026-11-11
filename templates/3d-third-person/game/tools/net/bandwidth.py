"""What online play costs each client in bytes, down and up, for 2, 4 and 8 players, against the research's budgets.

For each player count it starts the game server (`tools/net/gate_server.gd`, a free port), `N - 1` bots
(`tools/net/server_bot.gd`: a command a tick, two pings a second) and one predicting client
(`tools/net/predict_bot.gd`: circles, sprints, jumps), every one of them through `tools/net/relay.py`, which counts the
bytes of each connection each way (WebSocket framing included, TCP/IP headers not). Once all are seated it reads the
counts over `--seconds`, and judges every client's rate against the budgets of the networking research (kit
docs/engines/godot/multiplayer.md, `test_net_server_cost.gd`): down under 5 KB/s and up under 2 KB/s a client at any
player count. It prints a table and writes `result.json` under `--out`; exits 1 when a client is over a budget or a
run did not seat everyone.

With `--ai 40,120` each player count runs again with a crowd of that many AI characters on the server
(`gate_server.gd --ai`, every one walking: an upper bound), judged against `AI_DOWN_BUDGET`; the table adds the
server's cost of the AI blocks a TICK and its step (its `stats` lines) and the predicting client's cost of applying
them (its `PREDICT_BOT` line). `--delay-ms` delays the relay each way (150: a 300 ms round trip) and `--freeze` freezes
the predicting client's thread (`8:5000`: 5 s at 8 s), as the measurement of gdstudio #970 asks.

    python tools/net/bandwidth.py --godot <pinned godot> --project game --out <folder> [--players 2,4,8] [--seconds 10]
        [--ai 0,40,120] [--delay-ms 150] [--freeze 8:5000]
"""

from __future__ import annotations

import argparse
import contextlib
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bad_network_gate import godot_cmd, start, stop, wait_for_port
from relay import Relay

# Bytes a second a client, the research's budgets (gdstudio #883; `test_net_server_cost.gd` checks the same at 8).
DOWN_BUDGET = 5000
UP_BUDGET = 2000
# Bytes a second down a client with an AI crowd: Deadnight's 561 B a tick at 120 characters with an interest radius
# (16.8 KB/s at 30 TICKs a second; 67 KB/s for four players) and the players' own budget.
AI_DOWN_BUDGET = 561 * 30 + DOWN_BUDGET
# Seconds for the bots to be seated, then for the predicting client to load the map and be seated.
BOTS_SEATED_S = 3.0
CLIENT_SEATED_S = 8.0
# Seconds the predicting client may take after the window to end its run and print its line.
CLIENT_REPORT_S = 30.0


def measure(args: argparse.Namespace, players: int, out: Path, ai: int = 0) -> dict:
    """One player count: every client's bytes a second each way over the window."""
    out.mkdir(parents=True, exist_ok=True)
    project = args.project.resolve()
    server = bots = client = None
    relay: Relay | None = None
    result: dict = {"players": players, "ai": ai}
    server_args = ["--port", "0"] + (["--ai", str(ai)] if ai > 0 else [])
    try:
        server = start(
            godot_cmd(args.godot, project, "res://tools/net/gate_server.gd", *server_args),
            out / "server.log",
        )
        port = wait_for_port(out / "server.log", server)
        relay = Relay("127.0.0.1", port, args.delay_ms / 1000.0)
        url = f"ws://127.0.0.1:{relay.start_in_thread()}"
        life = str(int(BOTS_SEATED_S + CLIENT_SEATED_S + args.seconds + 20))
        if players > 1:
            bot_args = ["--connect", url, "--bots", str(players - 1), "--seconds", life]
            bots = start(
                godot_cmd(args.godot, project, "res://tools/net/server_bot.gd", *bot_args),
                out / "bots.log",
            )
            time.sleep(BOTS_SEATED_S)
        client_args = [
            "--connect",
            url,
            "--seconds",
            str(int(CLIENT_SEATED_S + args.seconds + 5)),
        ]
        if args.freeze:
            client_args += ["--freeze", args.freeze]
        client = start(
            godot_cmd(args.godot, project, "res://tools/net/predict_bot.gd", *client_args),
            out / "client.log",
        )
        time.sleep(CLIENT_SEATED_S)
        first = [dict(c) for c in relay.per_connection]
        began = time.monotonic()
        time.sleep(args.seconds)
        last = [dict(c) for c in relay.per_connection]
        seconds = time.monotonic() - began
        # Its report line comes when its own run ends (a freeze included): wait for it, not kill it.
        with contextlib.suppress(subprocess.TimeoutExpired):
            client.wait(timeout=CLIENT_REPORT_S)
    finally:
        stop(client)
        stop(bots)
        stop(server)
        if relay is not None:
            relay.stop()
    rates = []
    for index, (a, b) in enumerate(zip(first, last, strict=False)):
        rates.append(
            {
                "connection": index,
                "who": "client" if index == len(first) - 1 and len(first) == players else "bot",
                "down_bytes_per_s": round((b["down"] - a["down"]) / seconds),
                "up_bytes_per_s": round((b["up"] - a["up"]) / seconds),
            }
        )
    result["connections"] = rates
    result["server"] = server_stats(out / "server.log")
    result["predict"] = predict_line(out / "client.log")
    result["seated"] = len(rates) == players and all(r["down_bytes_per_s"] > 0 for r in rates)
    if rates:
        result["down_max"] = max(r["down_bytes_per_s"] for r in rates)
        result["up_max"] = max(r["up_bytes_per_s"] for r in rates)
        result["down_mean"] = round(sum(r["down_bytes_per_s"] for r in rates) / len(rates))
        result["up_mean"] = round(sum(r["up_bytes_per_s"] for r in rates) / len(rates))
        own = [r for r in rates if r["who"] == "client"]
        result["client"] = own[0] if own else None
    return result


def server_stats(log: Path) -> dict:
    """The last `stats` line of the server's log with players seated: its AI and step costs."""
    found: dict = {}
    if log.exists():
        for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("{") and '"stats"' in line:
                fields = json.loads(line)
                if fields.get("players", 0) > 0:
                    found = fields
    keys = (
        "ai",
        "ai_build_us",
        "ai_encode_us_per_tick",
        "step_ms_p50",
        "step_ms_p95",
        "out_bytes_per_s",
    )
    return {key: found.get(key) for key in keys}


def predict_line(log: Path) -> dict:
    """The predicting client's `PREDICT_BOT` line (its AI part and its corrections), or {}."""
    if not log.exists():
        return {}
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("PREDICT_BOT "):
            report = json.loads(line[len("PREDICT_BOT ") :])
            keep = (
                "ai",
                "stalls",
                "snaps",
                "worst_stall_error_m",
                "end_gap_m",
                "client_us_p95",
                "drops",
            )
            return {key: report.get(key) for key in keep}
    return {}


def row(result: dict, ai: int) -> str:
    """One line of the table."""
    client = result["client"] or {}
    stats = result["server"]
    own_ai = (result["predict"] or {}).get("ai") or {}
    down_budget = AI_DOWN_BUDGET if ai > 0 else DOWN_BUDGET
    return (
        f"| {result['players']} | {ai} | {result['down_mean']} / {result['down_max']}; "
        f"{client.get('down_bytes_per_s')} "
        f"| {result['up_mean']} / {result['up_max']}; {client.get('up_bytes_per_s')} | {down_budget} / {UP_BUDGET} "
        f"| {stats.get('ai_encode_us_per_tick')} us, {stats.get('step_ms_p95')} ms "
        f"| {own_ai.get('apply_us_p50')} / {own_ai.get('apply_us_p95')} us, {own_ai.get('puppets')} |"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", required=True, help="the pinned Godot (console build on Windows)")
    parser.add_argument("--project", type=Path, required=True, help="the game folder (project.godot)")
    parser.add_argument("--out", type=Path, required=True, help="folder for the logs and result.json")
    parser.add_argument("--players", default="2,4,8", help="player counts, comma-separated")
    parser.add_argument(
        "--seconds",
        type=float,
        default=10.0,
        help="seconds counted once everyone is seated",
    )
    parser.add_argument(
        "--ai",
        default="0",
        help="AI crowd sizes on the server, comma-separated (0: none)",
    )
    parser.add_argument(
        "--delay-ms",
        type=float,
        default=0.0,
        help="the relay's delay each way, milliseconds",
    )
    parser.add_argument(
        "--freeze",
        default="",
        help="the predicting client's freezes, `s:ms,...` (predict_bot.gd)",
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    results = []
    failures: list[str] = []
    print(
        "| Players | AI | Down a client, B/s (mean / most; the predicting client) | Up a client, B/s "
        "| Budget down / up | Server: AI blocks a TICK, step p95 | Client: apply p50 / p95, puppets |"
    )
    print("| ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for ai in [int(a) for a in args.ai.split(",") if a]:
        for players in [int(p) for p in args.players.split(",") if p]:
            result = measure(args, players, args.out / f"players_{players}_ai_{ai}", ai)
            results.append(result)
            if not result["seated"]:
                failures.append(
                    f"{players} players: not everyone was seated ({len(result['connections'])} connections)"
                )
                continue
            print(row(result, ai), flush=True)
            down_budget = AI_DOWN_BUDGET if ai > 0 else DOWN_BUDGET
            if result["down_max"] >= down_budget:
                failures.append(f"{players} players, {ai} AI: a client got {result['down_max']} B/s down")
            if result["up_max"] >= UP_BUDGET:
                failures.append(f"{players} players, {ai} AI: a client sent {result['up_max']} B/s up")
    passed = not failures
    (args.out / "result.json").write_text(json.dumps({"runs": results, "passed": passed}, indent=2), encoding="utf-8")
    print("ALL PASSED" if passed else "FAILED: " + "; ".join(failures), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
