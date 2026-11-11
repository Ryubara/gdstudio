"""The thresholds of the bad-network proof, one set for the native bot and the browser probe.

A predicting client's report (`NetPlayReport`: the native `PREDICT_BOT` line of `tools/net/predict_bot.gd`, or
`window.gdnet.report` of the browser's `NetPlayProbe`) and the game server's log are judged here, so
`tools/net/bad_network_gate.py` and `tools/web_smoke/net_play_smoke.py` fail on the same numbers. Each threshold
names what it guards (kit docs: engines/godot/third-person/online-client.md#bad-network-gate).
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

# A freeze of the client's own thread (0.5, 2 and 5 s) leaves the body at most this far from the server's
# (issue #908; Deadnight's live server read 5.4 to 5.6 m at 5 s): the 5 s freeze reads 2.8 m here.
WORST_ERROR_M = 6.0
# The join is one snap (the first answer after the WELCOME's teleport is taken whole) and so is each stall of the
# client's own thread the stall guard saw (a resync: the planned freezes, and in a software-drawn browser page its
# own hitches over 0.25 s): a snap more is an error past 2.5 m, a loop that does not settle.
SNAPS_A_FREEZE = 1
SNAPS_AT_JOIN = 1
# Without freezes a stall of the network is a burst, never a wrong position: no snap (2.5 m off).
STALL_WORST_ERROR_M = 2.5
# Once the body has stood two seconds it is where the server says, to the wire's rounding (a TICK carries
# centimetres: 0.87 cm at most) and a little more.
END_GAP_M = 0.05
# The body moved by corrections (snaps not counted), metres a minute of play. With the server's hold a 30 s run with
# freezes corrects 0.7 m (1.4 m a minute); without the hold (two processes' frames drift, a command lands a step late
# about thirteen times a second) 19.8 m in 36 s: the hold's teeth. A stall of the commands' way (up) is longer than
# the hold, so the server repeats a command the client did not make: those runs get `CORRECTED_M_AN_UP_STALL` more.
CORRECTED_M_PER_MINUTE = 4.0
CORRECTED_M_AN_UP_STALL = 1.0
# A stall of the client's own thread that the run did not plan (a software-drawn page's hitch past 0.25 s): the
# commands around it come late, as around a freeze. The browser read 0.7 to 2.6 m with 7 to 9 hitches; without the
# hold 31 m.
CORRECTED_M_A_HITCH = 0.5
# The puppets are drawn 100 ms behind: at a steady 100 ms each way they never starve (under 1 % of the steps,
# issue #908). A stall of the snapshots' way (down) starves them for what it holds past that delay and no longer:
# the stall's length less the delay, a snapshot's interval more (the burst shows the moves at once, never a wrong
# place), plus `STARVED_SLACK_STEPS` for the join.
STARVED_SHARE = 0.01
STARVED_SLACK_STEPS = 12
# A body more than 6 m off is lost: never.
LOST = 0
TICK_RATE = 60
SNAPSHOT_RATE = 30
PUPPET_DELAY_S = 0.1


@dataclass
class Network:
    """The network a run played through: freezes of the client's thread and the relay's stalls each way."""

    seconds: float
    freezes: int = 0
    stall_s: float = 0.3
    stalls_up: int = 0
    stalls_down: int = 0

    def starved_allowed(self, steps: int, puppets: int) -> int:
        """Puppet-steps that may starve (`RemotePlayers.starved` counts each puppet of a step)."""
        steady = int(steps * puppets * STARVED_SHARE)
        if not self.stalls_down:
            return steady
        each = max(0.0, self.stall_s - PUPPET_DELAY_S) * TICK_RATE + TICK_RATE / SNAPSHOT_RATE + 1
        return max(steady, int((self.stalls_down * each + STARVED_SLACK_STEPS) * puppets))

    def corrected_allowed(self, client_stalls: int = 0) -> float:
        hitches = max(0, client_stalls - self.freezes)
        return (
            CORRECTED_M_PER_MINUTE * self.seconds / 60.0
            + CORRECTED_M_AN_UP_STALL * self.stalls_up
            + CORRECTED_M_A_HITCH * hitches
        )


@dataclass
class Verdict:
    """The checks of one run: each a name, whether it passed and what it read."""

    checks: list[dict] = field(default_factory=list)

    def check(self, name: str, ok: bool, detail: object) -> None:
        self.checks.append({"name": name, "ok": bool(ok), "detail": detail})

    @property
    def passed(self) -> bool:
        return bool(self.checks) and all(c["ok"] for c in self.checks)

    def failures(self) -> list[str]:
        return [c["name"] for c in self.checks if not c["ok"]]

    def print(self, prefix: str = "") -> None:
        for c in self.checks:
            print(("PASS " if c["ok"] else "FAIL ") + prefix + c["name"] + f": {c['detail']}", flush=True)


def judge_client(report: dict, network: Network, verdict: Verdict | None = None) -> Verdict:
    """Judges a client's report against what the `network` it played through allows."""
    verdict = verdict or Verdict()
    if "error" in report or report.get("slot", -1) < 0:
        verdict.check("the client was seated", False, report)
        return verdict
    verdict.check("the client was seated", True, {"slot": report["slot"], "rtt_ms": report.get("rtt_ms")})
    verdict.check(f"no body lost (more than 6 m off): {LOST}", report["lost"] <= LOST, report["lost"])
    verdict.check(
        f"the client saw its {network.freezes} freezes",
        report["stalls"] >= network.freezes,
        {"stalls": report["stalls"], "skipped_ticks": report["skipped_ticks"]},
    )
    snaps = SNAPS_AT_JOIN + SNAPS_A_FREEZE * max(network.freezes, report["stalls"])
    verdict.check(
        f"at most {snaps} snaps (the join and each stall of the client)",
        report["snaps"] <= snaps,
        {"snaps": report["snaps"], "stalls": report["stalls"], "skipped_ticks": report["skipped_ticks"]},
    )
    worst = WORST_ERROR_M if network.freezes else STALL_WORST_ERROR_M
    verdict.check(f"worst error under {worst} m", report["worst_error_m"] < worst, report["worst_error_m"])
    gap = report.get("end_gap_m", report.get("gap_m", -1.0))
    verdict.check(f"settled under {END_GAP_M} m", 0.0 <= gap < END_GAP_M, gap)
    allowed = network.corrected_allowed(report["stalls"])
    verdict.check(
        f"corrected under {allowed:.2f} m",
        report["corrected_m"] < allowed,
        {"corrected_m": report["corrected_m"], "corrections": report["corrections"], "up_stalls": network.stalls_up},
    )
    if report.get("puppets", 0) > 0:
        starved = network.starved_allowed(report["steps"], report["puppets"])
        verdict.check(
            f"puppets starved in at most {starved} puppet-steps",
            report["starved_steps"] <= starved,
            {
                "starved_steps": report["starved_steps"],
                "steps": report["steps"],
                "share": report["starved_share"],
                "down_stalls": network.stalls_down,
            },
        )
    return verdict


def server_log(path: Path) -> dict:
    """What the server's log says: the `kicked` and `left` lines, engine errors, the last `stats` lines."""
    kicked: list[dict] = []
    left: list[dict] = []
    stats: list[dict] = []
    errors: list[str] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "ERROR" in line or "SCRIPT ERROR" in line:
            errors.append(line.strip())
        if not line.startswith("{"):
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        event = entry.get("event")
        if event == "kicked":
            kicked.append(entry)
        elif event == "left":
            left.append(entry)
        elif event == "stats":
            stats.append(entry)
    return {"kicked": kicked, "left": left, "stats": stats[-3:], "errors": errors[:10]}


def judge_server(log: dict, verdict: Verdict) -> Verdict:
    verdict.check("the server kicked nobody", not log["kicked"], log["kicked"][:3])
    verdict.check("no ERROR in the server's log", not log["errors"], log["errors"])
    return verdict


def errors_in(path: Path) -> list[str]:
    """Engine and script errors of a Godot log."""
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    return [line.strip() for line in text.splitlines() if "ERROR" in line][:10]
