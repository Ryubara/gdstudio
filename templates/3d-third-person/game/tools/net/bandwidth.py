"""What online play costs each client in bytes, down and up, for 2, 4 and 8 players, against the research's budgets.

For each player count it starts the game server (`tools/net/gate_server.gd`, a free port), `N - 1` bots
(`tools/net/server_bot.gd`: a command a tick, two pings a second) and one predicting client
(`tools/net/predict_bot.gd`: circles, sprints, jumps), every one of them through `tools/net/relay.py`, which counts the
bytes of each connection each way (WebSocket framing included, TCP/IP headers not). Once all are seated it reads the
counts over `--seconds`, and judges every client's rate against the budgets of the networking research (kit
docs/engines/godot/multiplayer.md, `test_net_server_cost.gd`): down under 5 KB/s and up under 2 KB/s a client at any
player count. It prints a table and writes `result.json` under `--out`; exits 1 when a client is over a budget or a
run did not seat everyone.

    python tools/net/bandwidth.py --godot <pinned godot> --project game --out <folder> [--players 2,4,8] [--seconds 10]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bad_network_gate import godot_cmd, start, stop, wait_for_port
from relay import Relay

# Bytes a second a client, the research's budgets (gdstudio #883; `test_net_server_cost.gd` checks the same at 8).
DOWN_BUDGET = 5000
UP_BUDGET = 2000
# Seconds for the bots to be seated, then for the predicting client to load the map and be seated.
BOTS_SEATED_S = 3.0
CLIENT_SEATED_S = 8.0


def measure(args: argparse.Namespace, players: int, out: Path) -> dict:
    """One player count: every client's bytes a second each way over the window."""
    out.mkdir(parents=True, exist_ok=True)
    project = args.project.resolve()
    server = bots = client = None
    relay: Relay | None = None
    result: dict = {"players": players}
    try:
        server = start(
            godot_cmd(args.godot, project, "res://tools/net/gate_server.gd", "--port", "0"), out / "server.log"
        )
        port = wait_for_port(out / "server.log", server)
        relay = Relay("127.0.0.1", port, 0.0)
        url = f"ws://127.0.0.1:{relay.start_in_thread()}"
        life = str(int(BOTS_SEATED_S + CLIENT_SEATED_S + args.seconds + 20))
        if players > 1:
            bot_args = ["--connect", url, "--bots", str(players - 1), "--seconds", life]
            bots = start(godot_cmd(args.godot, project, "res://tools/net/server_bot.gd", *bot_args), out / "bots.log")
            time.sleep(BOTS_SEATED_S)
        client_args = ["--connect", url, "--seconds", str(int(CLIENT_SEATED_S + args.seconds + 5))]
        client = start(
            godot_cmd(args.godot, project, "res://tools/net/predict_bot.gd", *client_args), out / "client.log"
        )
        time.sleep(CLIENT_SEATED_S)
        first = [dict(c) for c in relay.per_connection]
        began = time.monotonic()
        time.sleep(args.seconds)
        last = [dict(c) for c in relay.per_connection]
        seconds = time.monotonic() - began
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
    result["seated"] = len(rates) == players and all(r["down_bytes_per_s"] > 0 for r in rates)
    if rates:
        result["down_max"] = max(r["down_bytes_per_s"] for r in rates)
        result["up_max"] = max(r["up_bytes_per_s"] for r in rates)
        result["down_mean"] = round(sum(r["down_bytes_per_s"] for r in rates) / len(rates))
        result["up_mean"] = round(sum(r["up_bytes_per_s"] for r in rates) / len(rates))
        own = [r for r in rates if r["who"] == "client"]
        result["client"] = own[0] if own else None
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", required=True, help="the pinned Godot (console build on Windows)")
    parser.add_argument("--project", type=Path, required=True, help="the game folder (project.godot)")
    parser.add_argument("--out", type=Path, required=True, help="folder for the logs and result.json")
    parser.add_argument("--players", default="2,4,8", help="player counts, comma-separated")
    parser.add_argument("--seconds", type=float, default=10.0, help="seconds counted once everyone is seated")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    results = []
    failures: list[str] = []
    print("| Players | Down a client, B/s (mean / most; the predicting client) | Up a client, B/s | Budget down / up |")
    print("| ---: | ---: | ---: | ---: |")
    for players in [int(p) for p in args.players.split(",") if p]:
        result = measure(args, players, args.out / f"players_{players}")
        results.append(result)
        if not result["seated"]:
            failures.append(f"{players} players: not everyone was seated ({len(result['connections'])} connections)")
            continue
        client = result["client"] or {}
        print(
            f"| {players} | {result['down_mean']} / {result['down_max']}; {client.get('down_bytes_per_s')} "
            f"| {result['up_mean']} / {result['up_max']}; {client.get('up_bytes_per_s')} | {DOWN_BUDGET} / {UP_BUDGET} |",
            flush=True,
        )
        if result["down_max"] >= DOWN_BUDGET:
            failures.append(f"{players} players: a client got {result['down_max']} B/s down")
        if result["up_max"] >= UP_BUDGET:
            failures.append(f"{players} players: a client sent {result['up_max']} B/s up")
    passed = not failures
    (args.out / "result.json").write_text(json.dumps({"runs": results, "passed": passed}, indent=2), encoding="utf-8")
    print("ALL PASSED" if passed else "FAILED: " + "; ".join(failures), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
