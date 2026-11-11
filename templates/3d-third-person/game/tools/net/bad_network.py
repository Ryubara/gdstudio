"""The thresholds of the bad-network proof, one set for the native bot and the browser probe.

A predicting client's report (`NetPlayReport`: the native `PREDICT_BOT` line of `tools/net/predict_bot.gd`, or
`window.gdnet.report` of the browser's `NetPlayProbe`) and the game server's log are judged here, so
`tools/net/bad_network_gate.py` and `tools/web_smoke/net_play_smoke.py` fail on the same numbers. Each threshold
names what it guards (kit docs: engines/godot/third-person/online-client.md#bad-network-gate).
"""

from __future__ import annotations

import itertools
import json
from dataclasses import dataclass, field
from pathlib import Path

# A freeze of the client's own thread (0.5, 2 and 5 s) leaves the body at most this far from the server's
# (issue #908; Deadnight's live server read 5.4 to 5.6 m at 5 s): the server walks its body on through the silence
# (`NetServer.command_ticks`, 30 steps of the last command: 3.25 m at a sprint), and the native 0.5 s freeze during a
# sprint reads 2.8 to 3.0 m. Judged per stall (`worst_stall_error_m`): a page that hitches again before the answer
# after a hitch comes back adds the server's walk-ons into one answer (four stalls in its first second read 7.1 m,
# 1.8 m a stall; kit issue #1070), and a body is lost only past 6 m a stall (`Reconciler.resync`).
WORST_ERROR_M = 6.0
# The join is one snap (the first answer after the WELCOME's teleport is taken whole) and so is each stall of the
# client's own thread the stall guard saw (a resync: the planned freezes, and in a software-drawn browser page its
# own hitches over 0.25 s): a snap more is an error past 2.5 m, a loop that does not settle.
SNAPS_A_FREEZE = 1
SNAPS_AT_JOIN = 1
# A stall of the commands' way makes the server repeat the last command, and two such stalls close together put the
# server's body 2.5 to 3.3 m ahead (the Linux runner, gdstudio #1110): an answer past `Reconciler.SNAP_DISTANCE`, which
# the reconciler takes whole. Such a snap (`size_snaps_m`: a snap that was not a resync) is a burst, not a loop that
# does not settle, when the run stalled the commands' way and it stays under `STALL_WORST_ERROR_M`; at most one an up
# stall. The settled gap and the corrections still judge the loop.
# Without freezes a stall of the network is a burst, never a wrong position: under 4 m. A stall of the commands' way
# outlasts the hold, so the server repeats the last command (30 steps at most) and the answer after it is off by that
# run: 1.4 to 1.6 m for one stall, 2.7 m when two came close together (with the jitter on top).
STALL_WORST_ERROR_M = 4.0
# Once the body has stood two seconds it is where the server says, to the wire's rounding (a TICK carries
# centimetres: 0.87 cm at most) and a little more.
END_GAP_M = 0.05
# The body moved by corrections (snaps not counted), metres a minute of play. With the server's hold a 30 s run with
# freezes corrects 0.7 m (1.4 m a minute); without the hold (two processes' frames drift, a command lands a step late
# about thirteen times a second) 19.8 m in 36 s: the hold's teeth. A stall of the commands' way (up) is longer than
# the hold, so the server repeats a command the client did not make: those runs get `CORRECTED_M_AN_UP_STALL` more.
CORRECTED_M_PER_MINUTE = 4.0
# Over a real network (a deployment, no relay) the commands' arrival jitters past the hold's four steps now and then,
# which the relay never does: the deployment on Railway read 3.1 m in 30 s at a 69 ms round trip (6.1 m a minute).
# The hard limits (lost, snaps, worst error, settled) stay the same.
CORRECTED_M_PER_MINUTE_REAL = 10.0
# Measured 0.5 to 1.6 m an up stall over seven runs; the freeze run, with no stalls, is the hold's teeth.
CORRECTED_M_AN_UP_STALL = 3.0
# A stall of the client's own thread that the run did not plan (a software-drawn page's hitch past 0.25 s): the
# commands around it come late, as around a freeze. The browser read 0.7 to 5.2 m with 7 to 9 hitches; without the
# hold 31 m.
CORRECTED_M_A_HITCH = 0.75
# A browser page (24 to 35 frames a second on SwiftShader, two or three steps a frame) corrects more after each stall
# of its thread than the native client does: 1 to 5 m in the second after a freeze, where the native client reads
# 0.7 to 0.9 m for all three. Its hitches used to hide that (0.75 m each, 8 to 9 of them); once the page joins after
# the level's warm-up it has none, and 11 runs with three freezes read 1.6 to 5.2 m (kit #1106). So a page is allowed
# this much for every stall of its thread, the planned freezes included (why: #1127); without the hold it read 45 m.
CORRECTED_M_A_PAGE_STALL = 1.5
# The puppets are drawn 100 ms behind: at a steady 100 ms each way they never starve (under 1 % of the steps,
# issue #908). A stall of the snapshots' way (down) starves them for what it holds past that delay and no longer:
# the stall's length less the delay, a snapshot's interval more (the burst shows the moves at once, never a wrong
# place), plus `STARVED_SLACK_STEPS` for the join.
STARVED_SHARE = 0.01
STARVED_SLACK_STEPS = 12
# A stall of the client's own thread ends in a frame of catch-up steps (at most the engine's 8 a frame) that move the
# puppets' clock on while a page receives nothing until the next frame: up to that many starved steps a puppet. The
# page read 0.7 to 1.3 % of its puppet-steps starved with 11 stalls of its thread.
STARVED_A_CLIENT_STALL = 8
# A server that lost more steps than this between two of its `stats` lines (ten seconds apart) was itself starved of
# the machine: its TICKs came late and every client's puppets starved with them. On the shared workstation 4 of 19
# browser runs lost 19 to 101 steps in a window, and each of them failed its starvation bound (279 to 657 puppet-steps)
# whatever the page did; the other 15 lost 0 to 10 (kit #1106). A quarter of a second, the stall guard's own stall.
SERVER_LOST_STEPS = 15
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
    real: bool = False
    page: bool = False

    def starved_allowed(self, steps: int, puppets: int, client_stalls: int = 0) -> int:
        """Puppet-steps that may starve (`RemotePlayers.starved` counts each puppet of a step)."""
        steady = int(steps * puppets * STARVED_SHARE) + STARVED_A_CLIENT_STALL * client_stalls * puppets
        if not self.stalls_down:
            return steady
        each = max(0.0, self.stall_s - PUPPET_DELAY_S) * TICK_RATE + TICK_RATE / SNAPSHOT_RATE + 1
        return max(steady, int((self.stalls_down * each + STARVED_SLACK_STEPS) * puppets))

    def corrected_allowed(self, client_stalls: int = 0) -> float:
        hitches = max(0, client_stalls - self.freezes)
        per_minute = CORRECTED_M_PER_MINUTE_REAL if self.real else CORRECTED_M_PER_MINUTE
        stalls = (
            CORRECTED_M_A_PAGE_STALL * max(client_stalls, self.freezes) if self.page else CORRECTED_M_A_HITCH * hitches
        )
        return per_minute * self.seconds / 60.0 + CORRECTED_M_AN_UP_STALL * self.stalls_up + stalls


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
    verdict.check(
        f"at most {LOST} answer(s) more than 6 m a stall off",
        report["lost"] <= LOST,
        {"lost": report["lost"], "most_stacked": report.get("most_stacked", 0)},
    )
    verdict.check(
        f"the client saw its {network.freezes} freezes",
        report["stalls"] >= network.freezes,
        {"stalls": report["stalls"], "skipped_ticks": report["skipped_ticks"]},
    )
    bursts = up_stall_bursts(report, network)
    snaps = SNAPS_AT_JOIN + SNAPS_A_FREEZE * max(network.freezes, report["stalls"]) + len(bursts)
    verdict.check(
        f"at most {snaps} snaps (the join, each stall of the client, each burst after an up stall)",
        report["snaps"] <= snaps,
        {
            "snaps": report["snaps"],
            "stalls": report["stalls"],
            "skipped_ticks": report["skipped_ticks"],
            "bursts_m": bursts,
        },
    )
    worst = WORST_ERROR_M if network.freezes else STALL_WORST_ERROR_M
    stall_error = report.get("worst_stall_error_m", report["worst_error_m"])
    verdict.check(
        f"worst error under {worst} m a stall",
        stall_error < worst,
        {
            "worst_stall_error_m": stall_error,
            "worst_error_m": report["worst_error_m"],
            "most_stacked": report.get("most_stacked", 0),
        },
    )
    gap = report.get("end_gap_m", report.get("gap_m", -1.0))
    verdict.check(f"settled under {END_GAP_M} m", 0.0 <= gap < END_GAP_M, gap)
    allowed = network.corrected_allowed(report["stalls"])
    verdict.check(
        f"corrected under {allowed:.2f} m",
        report["corrected_m"] < allowed,
        {"corrected_m": report["corrected_m"], "corrections": report["corrections"], "up_stalls": network.stalls_up},
    )
    if report.get("puppets", 0) > 0:
        starved = network.starved_allowed(report["steps"], report["puppets"], report["stalls"])
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


def up_stall_bursts(report: dict, network: Network) -> list[float]:
    """The snaps taken for their size (`size_snaps_m`) that a stall of the commands' way explains: none without up
    stalls, only those under `STALL_WORST_ERROR_M`, and at most one an up stall."""
    if network.stalls_up <= 0:
        return []
    bursts = [e for e in report.get("size_snaps_m", []) if e < STALL_WORST_ERROR_M]
    return bursts[: network.stalls_up]


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
    return {"kicked": kicked, "left": left, "stats": stats[-3:], "errors": errors[:10], "lost_steps": lost_steps(stats)}


def lost_steps(stats: list[dict]) -> int:
    """The most steps the server fell further behind its clock between two `stats` lines (0 with fewer than two)."""
    behind = [round(entry["t"] * TICK_RATE) - entry["tick"] for entry in stats if "t" in entry and "tick" in entry]
    return max((b - a for a, b in itertools.pairwise(behind)), default=0)


def judge_server_clock(log: dict, verdict: Verdict) -> Verdict:
    """Fails a run whose server lost the machine (its TICKs late), so its starved puppets are named for what they are."""
    lost = log.get("lost_steps", 0)
    verdict.check(
        f"the server lost at most {SERVER_LOST_STEPS} steps in a window (else the run measures the machine)",
        lost <= SERVER_LOST_STEPS,
        lost,
    )
    return verdict


def judge_server(log: dict, verdict: Verdict) -> Verdict:
    verdict.check("the server kicked nobody", not log["kicked"], log["kicked"][:3])
    verdict.check("no ERROR in the server's log", not log["errors"], log["errors"])
    return verdict


def errors_in(path: Path) -> list[str]:
    """Engine and script errors of a Godot log."""
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    return [line.strip() for line in text.splitlines() if "ERROR" in line][:10]
